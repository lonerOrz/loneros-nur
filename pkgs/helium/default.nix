{
  lib,
  fetchurl,
  appimageTools,
  stdenv,
  callPackage,
  ...
}:
let
  current = lib.trivial.importJSON ./version.json;
  version = current.version;

  # Upstream asset names spell the arch differently than nix system names.
  assetArch = {
    x86_64-linux = "x86_64";
    aarch64-linux = "arm64";
  };

  releaseBase = "https://github.com/imputnet/helium-linux/releases/download";

  # "$VERSION" stays literal in Nix strings, so the updater can substitute it.
  urlFor = v: system: "${releaseBase}/${v}/helium-${v}-${assetArch.${system}}.AppImage";

  sourceMap = lib.mapAttrs (
    system: _:
    fetchurl {
      url = urlFor version system;
      hash = current.${system + "-hash"};
    }
  ) assetArch;
in
appimageTools.wrapType2 (finalAttrs: {
  pname = "helium";
  inherit version;

  src = sourceMap.${stdenv.hostPlatform.system};

  extraInstallCommands = ''
    mkdir -p $out/share/{applications,lib/helium}

    cp -r ${finalAttrs.contents}/opt/${finalAttrs.pname}/locales "$out/share/lib/helium"
    cp -r ${finalAttrs.contents}/usr/share/* "$out/share"

    cp "${finalAttrs.contents}/${finalAttrs.pname}.desktop" "$out/share/applications/"
  '';

  # fetch-urls.nix prefetches every hashUrls entry, so both platforms refresh together.
  passthru.updateScript =
    let
      versionFile = "pkgs/helium/version.json";
    in
    callPackage ../../utils/update.nix {
      pname = "helium";
      inherit versionFile;
      updateMethod = "none";
      fetchMetaCommand = "${lib.getExe (
        callPackage ../../utils/fetch-urls.nix {
          inherit versionFile;
          versionCommand = ''
            ${
              (callPackage ../../utils/fetcher.nix { }).githubRelease {
                owner = "imputnet";
                repo = "helium-linux";
              }
            } | jq -r '.version'
          '';
          hashUrls = lib.mapAttrs (system: _: urlFor "$VERSION" system) assetArch;
        }
      )}";
    };

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    homepage = "https://github.com/imputnet/helium-chromium";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${version}";
    platforms = builtins.attrNames sourceMap;
    license = lib.licenses.gpl3;
    maintainers = with lib.maintainers; [ lonerOrz ];
    mainProgram = "helium";
  };
})
