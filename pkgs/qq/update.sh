#!/usr/bin/env nix-shell
#!nix-shell -i python3 --pure --keep GITHUB_TOKEN -p python3 nix curl cacert

import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path
from typing import NamedTuple, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
SOURCES_NIX = SCRIPT_DIR / "sources.nix"
SRI_SCRIPT = SCRIPT_DIR / "../../.github/script/fetch-sri-hash.sh"

# ── 1. Data Models ────────────────────────────────────────

class PackageSource(NamedTuple):
    version: str
    url: str
    hash: str


class PlatformConfig(NamedTuple):
    darwin: PackageSource
    linux_arm: PackageSource
    linux_x64: PackageSource


# ── 2. Input Parsing ──────────────────────────────────────

def extract_balanced_json(text: str, marker: str = "var params") -> str:
    """Extract outermost JSON object from JS snippet via brace balancing."""
    idx = text.find(marker)
    if idx == -1:
        raise RuntimeError(f"Marker '{marker}' not found in response")
    i = text.find("{", idx)
    if i == -1:
        raise RuntimeError("Opening brace '{' not found in response")

    depth = 0
    in_str = False
    esc = False

    for j in range(i, len(text)):
        c = text[j]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]

    raise RuntimeError("Unbalanced braces in JSON payload")


def fetch_json_payload(url: str) -> dict:
    """Fetch CDN JS file and parse embedded JSON configuration."""
    res = subprocess.run(
        ["curl", "-sSf", url],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    return json.loads(extract_balanced_json(res.stdout))


def parse_version_from_url(url: str, fallback_date: Optional[str] = None) -> str:
    """
    Extract normalized version string from URL:
    1. Parse SemVer (e.g., 3.2.32, 6.9.99, 3.2.32.100).
    2. Parse 6-digit (YYMMDD) or 8-digit (YYYYMMDD) date -> normalize to YYYY-MM-DD.
    3. Fallback to payload updateDate or current date if URL lacks date segment.
    """
    filename = url.split("/")[-1]

    semver_match = re.search(r"[Qq][Qq](?:[Nn][Tt])?[-._]?([0-9]+(?:\.[0-9]+)+)", filename)
    if not semver_match:
        raise ValueError(f"Failed to parse SemVer from: {filename} (URL: {url})")
    semver = semver_match.group(1)

    ver_date = ""
    match_8d = re.search(r"_([2][0-9]{3})([0-1][0-9])([0-3][0-9])(?=_|\.|$)", filename)
    if match_8d:
        ver_date = f"{match_8d.group(1)}-{match_8d.group(2)}-{match_8d.group(3)}"
    else:
        match_6d = re.search(r"_([0-9]{2})([0-1][0-9])([0-3][0-9])(?=_|\.|$)", filename)
        if match_6d:
            ver_date = f"20{match_6d.group(1)}-{match_6d.group(2)}-{match_6d.group(3)}"

    if not ver_date:
        if fallback_date and re.match(r"^\d{4}-\d{2}-\d{2}$", fallback_date or ""):
            ver_date = fallback_date
        else:
            ver_date = date.today().isoformat()

    return f"{semver}-{ver_date}"


def semver_tuple(ver_str: str) -> Tuple[int, ...]:
    """Extract numeric SemVer tuple for rollback protection (excludes date suffix)."""
    return tuple(int(x) for x in ver_str.split("-", 1)[0].split("."))


def fetch_sri_hash(url: str) -> str:
    # No timeout here: Large payloads (400MB+ DMG/deb) need sufficient time on slow links
    res = subprocess.run(
        [str(SRI_SCRIPT), url],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    sri_hash = res.stdout.strip()
    if not sri_hash.startswith("sha256-"):
        raise ValueError(f"Invalid SRI hash format: '{sri_hash}' (URL: {url})")
    return sri_hash


# ── 3. Baseline Loader ────────────────────────────────────

def load_current_state() -> Optional[PlatformConfig]:
    """Evaluate sources.nix into memory via native Nix evaluator."""
    if not SOURCES_NIX.exists():
        return None

    expr = f"import {SOURCES_NIX} {{ fetchurl = x: x; }}"
    res = subprocess.run(
        ["nix", "eval", "--impure", "--extra-experimental-features", "nix-command",
         "--expr", expr, "--json"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if res.returncode != 0:
        return None

    try:
        data = json.loads(res.stdout)
        return PlatformConfig(
            darwin=PackageSource(
                version=data["aarch64-darwin"]["version"],
                url=data["aarch64-darwin"]["src"]["url"],
                hash=data["aarch64-darwin"]["src"]["hash"],
            ),
            linux_arm=PackageSource(
                version=data["aarch64-linux"]["version"],
                url=data["aarch64-linux"]["src"]["url"],
                hash=data["aarch64-linux"]["src"]["hash"],
            ),
            linux_x64=PackageSource(
                version=data["x86_64-linux"]["version"],
                url=data["x86_64-linux"]["src"]["url"],
                hash=data["x86_64-linux"]["src"]["hash"],
            ),
        )
    except Exception:
        return None


# ── 4. Resolution Engine ──────────────────────────────────

def resolve_source(
    name: str,
    new_url: str,
    fallback_date: Optional[str],
    current: Optional[PackageSource],
) -> PackageSource:
    """Resolve target package state with caching and anti-rollback guards."""
    new_version = parse_version_from_url(new_url, fallback_date)

    if current:
        # 1. URL unchanged -> short-circuit, reuse existing hash
        if current.url == new_url:
            print(f"[SKIP] {name}: Up to date ({current.version})")
            return current

        # 2. Upstream regression -> preserve current version
        if semver_tuple(new_version) < semver_tuple(current.version):
            print(f"[WARN] {name}: Upstream rollback detected ({new_version} < {current.version}), keeping current")
            return current

    # 3. New release -> compute SRI hash
    print(f"[INFO] {name}: {current.version if current else 'None'} -> {new_version}")
    new_hash = fetch_sri_hash(new_url)
    return PackageSource(version=new_version, url=new_url, hash=new_hash)


# ── 5. Nix Renderer ───────────────────────────────────────

def render_sources_nix(config: PlatformConfig) -> str:
    today_str = date.today().isoformat()
    return f"""# Generated by ./update.sh - do not update manually!
# Last updated: {today_str}
{{ fetchurl }}:
let
  any-darwin = {{
    version = "{config.darwin.version}";
    src = fetchurl {{
      url = "{config.darwin.url}";
      hash = "{config.darwin.hash}";
    }};
  }};
in
{{
  aarch64-darwin = any-darwin;
  x86_64-darwin = any-darwin;

  aarch64-linux = {{
    version = "{config.linux_arm.version}";
    src = fetchurl {{
      url = "{config.linux_arm.url}";
      hash = "{config.linux_arm.hash}";
    }};
  }};

  x86_64-linux = {{
    version = "{config.linux_x64.version}";
    src = fetchurl {{
      url = "{config.linux_x64.url}";
      hash = "{config.linux_x64.hash}";
    }};
  }};
}}
"""


# ── 6. Main Pipeline ──────────────────────────────────────

def main():
    darwin_payload = fetch_json_payload("https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/macOSConfig.js")
    linux_payload = fetch_json_payload("https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js")

    darwin_date = darwin_payload.get("updateDate")
    linux_date = linux_payload.get("updateDate")

    current = load_current_state()

    resolved = PlatformConfig(
        darwin=resolve_source(
            "macOS universal",
            darwin_payload["downloadUrl"],
            darwin_date,
            current.darwin if current else None,
        ),
        linux_arm=resolve_source(
            "Linux aarch64",
            linux_payload["armDownloadUrl"]["deb"],
            linux_date,
            current.linux_arm if current else None,
        ),
        linux_x64=resolve_source(
            "Linux x86_64",
            linux_payload["x64DownloadUrl"]["deb"],
            linux_date,
            current.linux_x64 if current else None,
        ),
    )

    if current is not None and resolved == current:
        print("\n[OK] No changes detected across all platforms")
        sys.exit(0)

    SOURCES_NIX.write_text(render_sources_nix(resolved))
    print("\n[OK] sources.nix updated successfully")


if __name__ == "__main__":
    main()
