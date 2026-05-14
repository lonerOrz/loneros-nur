{
  lib,
  stdenv,
  fetchzip,
  fetchurl,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  electron_40,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "duolingo-desktop";
  version = "4.2.0";

  src = fetchzip {
    url = "https://github.com/hmlendea/dl-desktop/releases/download/v${finalAttrs.version}/dl-desktop_${finalAttrs.version}_linux.zip";
    hash = "sha256-eQm3a+/Va3kr/8gObBTC0YRPguWpzXNGCoJsvq1wgao=";
    stripRoot = false;
  };

  icon = fetchurl {
    url = "https://raw.githubusercontent.com/hmlendea/dl-desktop/v${finalAttrs.version}/icon.png";
    hash = "sha256-Z2Qs0DokH/CXqDgA855ELFM+i3qSqSNcA3Xvhmpwjw4=";
  };

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    electron_40
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "duolingo-desktop";
      desktopName = "DL: language lessons";
      comment = "Unofficial desktop client for Duolingo language learning";
      exec = "duolingo-desktop";
      icon = "duolingo-desktop";
      categories = [ "Education" ];
      terminal = false;
      startupWMClass = "ro.go.hmlendea.DL-Desktop";
    })
  ];

  installPhase = ''
    runHook preInstall

    appDir="$out/lib/${finalAttrs.pname}"
    install -d $appDir
    cp -r ./* $appDir/

    install -d $out/bin
    makeWrapper ${electron_40}/bin/electron $out/bin/duolingo-desktop \
      --add-flags $appDir/resources/app.asar \
      --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
      --set-default GDK_BACKEND wayland,x11 \
      --set-default NIXOS_OZONE_WL 1

    install -d $out/share/icons/hicolor/512x512/apps
    install -m 0644 $icon $out/share/icons/hicolor/512x512/apps/duolingo-desktop.png

    runHook postInstall
  '';

  meta = {
    description = "Unofficial desktop client for Duolingo";
    homepage = "https://github.com/hmlendea/dl-desktop";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ lonerOrz ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "duolingo-desktop";
  };
})
