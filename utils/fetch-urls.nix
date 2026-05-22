{
  lib,
  callPackage,

  versionCommand,
  hashUrls,
  versionFile,

  prefetchUnpack ? false,
  extraPreScript ? "",
}:

let
  inherit (lib)
    toUpper
    replaceStrings
    concatStringsSep
    mapAttrsToList
    ;

  sanitize = system: toUpper (replaceStrings ["-"] ["_"] system);

  # Shorthand: hashUrls = { x86_64-linux = "url"; }
  # Long form:  hashUrls = { x86_64-linux = { url = "url"; hashKey = "key"; }; }
  normalized = builtins.mapAttrs (_system: val:
    if builtins.isString val then { url = val; }
    else val
  ) hashUrls;

  hashSystems = builtins.attrNames normalized;

  preScript = ''
    VERSION=$(${versionCommand})

    CURRENT_VERSION=$(jq -r '.version' "${versionFile}" 2>/dev/null || echo "")
    [ "$VERSION" = "$CURRENT_VERSION" ] && cat "${versionFile}" && exit 0

    tmpdir=$(mktemp -d)
    ${concatStringsSep "\n    " (mapAttrsToList (system: cfg: ''
      (nix-prefetch-url ${if prefetchUnpack then "--unpack " else ""}"${cfg.url}" --type sha256 \
        | xargs nix-hash --to-sri --type sha256 > "$tmpdir/${system}") &
    '') normalized)}
    wait

    ${concatStringsSep "\n    " (mapAttrsToList (system: _: ''
      _HASH_${sanitize system}=$(cat "$tmpdir/${system}")
    '') normalized)}
    rm -rf "$tmpdir"

    ${extraPreScript}
  '';

  commands = { version = "echo $VERSION"; } // builtins.listToAttrs (builtins.map
    (system: let
      cfg = normalized.${system};
      hashKey = cfg.hashKey or "${system}-hash";
    in {
      name = hashKey;
      value = "echo $_HASH_${sanitize system}";
    })
    hashSystems);

in
callPackage ./json.nix { inherit preScript commands; }
