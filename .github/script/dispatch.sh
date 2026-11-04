#!/usr/bin/env bash
# Compares two JSON fingerprints and dispatches a SINGLE build job with ALL changed packages.
#
# Usage: ./dispatch.sh --base <old.json> --head <new.json> [options]
#
# Required:
#   --base           JSON fingerprint from BASE (e.g. origin/main)
#   --head           JSON fingerprint from HEAD (e.g. PR branch)
#
# Optional:
#   --repo           Target repo (default: lonerOrz/nyx-loner)
#   --pr             PR number (required by downstream workflow)
#   --dry-run        Print payload without sending
#   --ref            Target branch for the workflow (default: main)

set -euo pipefail

BASE_FILE=""
HEAD_FILE=""
REPO="lonerOrz/loneros-nur"
PR=""
WORKFLOW_REPO="lonerOrz/nixpkgs-review-gha"
WORKFLOW_FILE="build-pr.yml"
REF="main"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --base <old.json> --head <new.json> [options]

Required:
  --base           Path to baseline JSON (before changes)
  --head           Path to current JSON (after changes)

Optional:
  --repo           Target repo (default: lonerOrz/nyx-loner)
  --pr             PR number (REQUIRED by downstream workflow)
  --dry-run        Print payload without sending
  --ref            Branch to dispatch (default: main)

Env:
  GH_TOKEN         GitHub token (required)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_FILE="$2"; shift 2 ;;
    --head) HEAD_FILE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --ref) REF="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# -----------------------------
# Validate inputs
# -----------------------------
[[ -z "$BASE_FILE" || -z "$HEAD_FILE" ]] && usage
[[ -z "$PR" ]] && { echo "Error: --pr is required" >&2; exit 1; }

AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[[ -z "$AUTH_TOKEN" ]] && { echo "Error: GH_TOKEN or GITHUB_TOKEN is required" >&2; exit 1; }

[[ ! -f "$BASE_FILE" || ! -f "$HEAD_FILE" ]] && {
  echo "Error: Input files not found"
  exit 1
}

# -----------------------------
# 1. Calculate Diff & Deduplicate
# -----------------------------
# Fingerprint shape: { pkg: { system: drvPath, ... }, ... }
# A package is "changed" when:
#   - it is entirely new in head (absent from base), OR
#   - on a system present in BOTH base and head, its drvPath differs, OR
#   - head builds it on a system that base did NOT build at all (e.g. the
#     flake newly declares aarch64-darwin) — that system is a new build target
#     and must be built.
# Merely sharing the same systems with identical drvPaths is NOT a change.
# If multiple packages map to the same drvPath (e.g. mesa_git, mesa32_git),
# we only dispatch one build to avoid redundancy.
#
# Base/head may be produced by different scan.sh versions: the old one emitted
# a FLAT { pkg: drv } (implicitly x86_64-linux), the new one emits the nested
# { pkg: { system: drv } }. Normalize both to the nested form so the diff works
# regardless of which scan.sh built the fingerprint.
NORMALIZE='
  # ($in) is a fingerprint; wrap flat entries under x86_64-linux.
  (if type == "object"
   then with_entries(
     if (.value | type) == "string"
     then { key: .key, value: { "x86_64-linux": .value } }
     else .
     end)
   else . end)
'
CHANGED_PKGS_RAW=$(jq -r -n \
  --slurpfile base "$BASE_FILE" \
  --slurpfile head "$HEAD_FILE" '
  ($base[0] | '"$NORMALIZE"') as $b |
  ($head[0] | '"$NORMALIZE"') as $h
  | ($h | keys) as $pkgs
  | $pkgs
  | map(. as $p | select(
      # package is brand new in head
      (($b[$p] // null) == null)
      or
      # a system shared by both has a different drvPath in head
      (($h[$p] | to_entries
        | map(select(.key as $s | ($b[$p][$s] != null)))
        | map(.value != ($b[$p][.key]))) | any)
      or
      # a system built in head but never in base => new build target
      (($h[$p] | to_entries | map(.key)) as $hs
        | ($b[$p]? | keys // []) as $bs
        | ($hs - $bs) != [])
    ))
  | sort
  | unique
  | group_by((. as $p | $h[$p] | to_entries | map(.value) | sort | join(",")))
  | map(.[0])
  | .[]
')

if [[ -z "$CHANGED_PKGS_RAW" ]]; then
  echo "No changes detected."
  exit 0
fi

# Safe conversion to array (avoids word splitting)
mapfile -t CHANGED_PKGS <<< "$CHANGED_PKGS_RAW"

# -----------------------------
# 2. Filter Policy
# -----------------------------
EXCLUDES=(
  '_v(2|3|4)$'     # Microarch variants
  '^firefox'       # Firefox family
  '^linux(_|$)'    # Linux kernel family
)

should_build() {
  local pkg="$1"
  for pattern in "${EXCLUDES[@]}"; do
    if [[ "$pkg" =~ $pattern ]]; then return 1; fi
  done
  return 0
}

VALID_PKGS=()
for pkg in "${CHANGED_PKGS[@]}"; do
  if should_build "$pkg"; then
    VALID_PKGS+=("$pkg")
  else
    echo "✗ Skip $pkg"
  fi
done

if [[ ${#VALID_PKGS[@]} -eq 0 ]]; then
  echo "No packages to dispatch after filtering."
  exit 0
fi

echo "Packages to dispatch:"
printf "→ %s\n" "${VALID_PKGS[@]}"
echo ""

# -----------------------------
# 3. Single Dispatch (All Packages as Matrix)
# -----------------------------
echo "→ Dispatching: ${VALID_PKGS[*]}"

# cleanup temp file on exit
cleanup() {
  [[ -n "${RESPONSE:-}" && -f "$RESPONSE" ]] && rm -f "$RESPONSE"
  return 0
}
trap cleanup EXIT

# Comma-separated for GitHub workflow input
DISPATCH_URL="https://api.github.com/repos/${WORKFLOW_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches"
PACKAGES_CSV=$(IFS=','; echo "${VALID_PKGS[*]}")

# CRITICAL: inputs values MUST be strings.
# The set of systems is whatever the flake declares (scan.sh scans exactly
# flake.packages' attribute names), so derive the switches from the head
# fingerprint rather than hardcoding them. Linux builds run natively; darwin
# builds use the sandbox-relaxed mode (the downstream runner provides macOS).
payload=$(jq -n \
  --arg repo "$REPO" \
  --arg pr "$PR" \
  --arg pkgs "$PACKAGES_CSV" \
  --arg ref "$REF" \
  --slurpfile head "$HEAD_FILE" \
  '
    # every system key present across all packages = flake-declared systems
    (reduce $head[0][] as $pkg ({}; . + $pkg) | keys) as $systems
    | ($systems | map(select(test("darwin$")))) as $darwin
    | ($systems - $darwin) as $linux
    # Drive every switch explicitly: a system the flake declares gets its
    # real value (linux -> true, darwin -> sandbox-relaxed), and any of the
    # four known systems the flake does NOT declare is sent as "no". This is
    # required because the downstream build-pr.yml defaults unset darwin
    # choices to yes_sandbox_relaxed; omitting them would build unwanted
    # systems (e.g. x86_64-darwin, which this repo never targets).
    | ( [ $linux[], $darwin[] ] ) as $declared
    | ( [ "x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin" ]
        | map(. as $s | {
            key: $s,
            val: ( if ($linux | index($s)) != null then "true"
                   else if ($darwin | index($s)) != null then "yes_sandbox_relaxed"
                   else "no" end end )
          }) )
    | map(. as $o | { ($o.key): $o.val }) | add as $sysInputs
    | {
        ref: $ref,
        inputs: (
          { repo: $repo, "pr-number": $pr, packages: $pkgs,
            "post-result": "true", "upload-cachix": "true" }
          + $sysInputs
        )
      }
  ')

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "$payload" | jq .
  exit 0
fi

RESPONSE=$(mktemp)

# simple retry (handles transient GitHub API / network issues)
for attempt in 1 2 3; do
  status=$(curl -s -o "$RESPONSE" -w "%{http_code}" -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    "$DISPATCH_URL" \
    -d "$payload")

  if [[ "$status" -eq 204 ]]; then
    echo "✅ Dispatched ${#VALID_PKGS[@]} package(s) successfully"
    exit 0
  fi

  echo "❌ Failed (HTTP $status) [attempt $attempt]" >&2
  cat "$RESPONSE" >&2

  if [[ "$attempt" -lt 3 ]]; then
    sleep $((attempt * 2))
  fi
done

echo "❌ All retries exhausted" >&2
exit 1
