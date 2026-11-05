{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  callPackage,
}:

let
  current = lib.trivial.importJSON ./version.json;
  version = current.version;

  # Upstream asset names spell the arch differently than nix system names.
  assetArch = {
    x86_64-linux = "x86_64";
    aarch64-linux = "aarch64";
  };

  releaseBase = "https://github.com/chi11321/CrabPort/releases/download";

  # "$VERSION" stays literal in Nix strings, so the updater can substitute it.
  urlFor = v: system: "${releaseBase}/v${v}/CrabPort-v${v}-linux-${assetArch.${system}}.AppImage";

  sourceMap = lib.mapAttrs (
    system: _:
    fetchurl {
      url = urlFor version system;
      hash = current.${system + "-hash"};
    }
  ) assetArch;
in
appimageTools.wrapType2 (finalAttrs: {
  pname = "crabport";
  inherit version;

  src = sourceMap.${stdenv.hostPlatform.system};

  extraInstallCommands = ''
    install -Dm644 ${finalAttrs.contents}/CrabPort.desktop $out/share/applications/CrabPort.desktop
    cp -r ${finalAttrs.contents}/usr/share/icons $out/share/
  '';

  # fetch-urls.nix prefetches every hashUrls entry, so both platforms refresh together.
  passthru.updateScript =
    let
      versionFile = "pkgs/crabport/version.json";
    in
    callPackage ../../utils/update.nix {
      pname = "crabport";
      inherit versionFile;
      updateMethod = "none";
      fetchMetaCommand = "${lib.getExe (
        callPackage ../../utils/fetch-urls.nix {
          inherit versionFile;
          versionCommand = ''
            ${
              (callPackage ../../utils/fetcher.nix { }).githubRelease {
                owner = "chi11321";
                repo = "CrabPort";
              }
            } | jq -r '.version'
          '';
          hashUrls = lib.mapAttrs (system: _: urlFor "$VERSION" system) assetArch;
        }
      )}";
    };

  meta = {
    description = "Modern, cross-platform SSH / SFTP client built with Rust and GPUI";
    homepage = "https://github.com/chi11321/CrabPort";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sourceMap;
    maintainers = with lib.maintainers; [ lonerOrz ];
    mainProgram = finalAttrs.pname;
  };
})
