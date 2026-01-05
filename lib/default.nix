{ pkgs }:

let
  # Import the fetch-npm-deps functionality
  fetchNpmDeps = import ./fetch-npm-deps.nix {
    inherit (pkgs) lib stdenv stdenvNoCC rustPlatform makeSetupHook makeWrapper pkg-config
             curl gnutar gzip cacert config nodejs_24 diffutils jq;
    srcOnly = pkgs.nix-src.srcOnly;
  };
in
with pkgs.lib; {
  # Add your library functions here
  #
  # hexint = x: hexvals.${toLower x};

  # Export functions from fetch-npm-deps
  fetchNpmDepsWithPackuments = fetchNpmDeps.fetchNpmDepsWithPackuments;
  npmConfigHook = fetchNpmDeps.npmConfigHook;
  prefetch-npm-deps = fetchNpmDeps."prefetch-npm-deps";
}
