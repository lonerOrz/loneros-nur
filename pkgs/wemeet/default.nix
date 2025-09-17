{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  nss,
  xorg,
  libpulseaudio,
  dbus,
  udev,
  libGL,
  fontconfig,
  freetype,
  wayland,
  libdrm,
  harfbuzz,
  glib,
  libXcursor,
  systemdLibs,
  openssl,
  libsForQt5,
  pkg-config,
  pipewire,
  fetchgit,
  xkeyboard_config,
}:

let
  # Wrapper library for mitigating file transfer crashes
  libwemeetwrap = stdenv.mkDerivation {
    pname = "libwemeetwrap";
    version = "0-unstable-2023-12-14";

    src = fetchgit {
      url = "https://aur.archlinux.org/wemeet-bin.git";
      rev = "8f03fbc4d5ae263ed7e670473886cfa1c146aecc";
      hash = "sha256-ExzLCIoLu4KxaoeWNhMXixdlDTIwuPiYZkO+XVK8X10=";
    };

    dontWrapQtApps = true;

    nativeBuildInputs = [ pkg-config ];

    buildInputs = [
      libpulseaudio
      openssl
      pipewire
      xorg.libX11
      libGL
    ];

    buildPhase = ''
      runHook preBuild

      read -ra libpulse_args < <(pkg-config --cflags --libs libpulse)
      $CC $CFLAGS -Wall -Wextra -fPIC -shared \
        "''${libpulse_args[@]}" \
        -o libwemeetwrap.so wrap.c -D WRAP_FORCE_SINK_HARDWARE \
        -lssl -lcrypto
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 ./libwemeetwrap.so $out/lib/libwemeetwrap.so
      runHook postInstall
    '';

    meta.license = lib.licenses.unfree;
  };

  selectSystem =
    attrs:
    attrs.${stdenv.hostPlatform.system}
      or (throw "wemeet: ${stdenv.hostPlatform.system} is not supported");
in

stdenv.mkDerivation {
  pname = "wemeet";
  version = "3.26.10.400";

  src = selectSystem {
    x86_64-linux = fetchurl {
      url = "https://updatecdn.meeting.qq.com/cos/9cfd93b10ee81b2fc3ad26357f27ed13/TencentMeeting_0300000000_3.26.10.400_x86_64_default.publish.officialwebsite.deb";
      hash = "sha256-7gN40mkAD/0/k0E+bBNfiMcY+YtIaLWycFoI+hhrjgc=";
    };
    aarch64-linux = fetchurl {
      url = "https://updatecdn.meeting.qq.com/cos/e5f447f30343e27c49438db8d035ae23/TencentMeeting_0300000000_3.26.10.400_arm64_default.publish.officialwebsite.deb";
      hash = "sha256-ShxcDwwBThwe2YKNy/5+HmYcnnodPhrMaOwkw3gTq0E=";
    };
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    nss
    libGL
    libdrm
    fontconfig
    freetype
    wayland
    udev
    glib
    harfbuzz
    dbus
    libpulseaudio
    xorg.libX11
    xorg.libSM
    xorg.libICE
    xorg.libXtst
    libXcursor
    libsForQt5.qt5.qtwebengine
    libsForQt5.qt5.qtbase
    libsForQt5.qt5.qtdeclarative
    systemdLibs
    xkeyboard_config
  ];

  dontWrapQtApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/app
    cp -r opt/wemeet $out/app/wemeet
    cp -r usr/share $out/share

    substituteInPlace $out/share/applications/wemeetapp.desktop \
      --replace-fail "/opt/wemeet/wemeetapp.sh" "wemeet" \
      --replace-fail "/opt/wemeet/wemeet.svg" "wemeet"
    substituteInPlace $out/app/wemeet/bin/qt.conf \
      --replace-fail "Prefix = ../" "Prefix = $out/app/wemeet/lib"

    ln -s $out/app/wemeet/bin/raw/xcast.conf $out/app/wemeet/bin/xcast.conf
    cp -r $out/app/wemeet/icons $out/share/icons
    install -Dm0644 $out/app/wemeet/wemeet.svg $out/share/icons/hicolor/scalable/apps/wemeet.svg
    ln -s $out/app/wemeet/plugins $out/app/wemeet/lib/plugins
    ln -s $out/app/wemeet/resources $out/app/wemeet/lib/resources
    ln -s $out/app/wemeet/translations $out/app/wemeet/lib/translations

    mkdir -p $out/share/X11
    ln -s ${xkeyboard_config}/share/X11/xkb $out/share/X11/xkb
    ln -s ${systemdLibs}/lib/libudev.so.1 $out/app/wemeet/lib/libudev.so.0

    runHook postInstall
  '';

  preFixup =
    let
      baseWrapperArgs = [
        "--set LP_NUM_THREADS 2"
        "--set QT_STYLE_OVERRIDE fusion"
        "--set IBUS_USE_PORTAL 1"
        "--set XKB_CONFIG_ROOT $out/share/X11/xkb"
        "--set QT_XKB_CONFIG_ROOT $out/share/X11/xkb"
        "--set WEMEET_HOME $out/app/wemeet/lib"
        "--prefix XDG_DATA_DIRS : $out/share"
        "--prefix LD_LIBRARY_PATH : $out/app/wemeet/lib:/run/opengl-driver/lib:${systemdLibs}/lib"
        "--prefix PATH : $out/bin"
        "--prefix QT_PLUGIN_PATH : $out/app/wemeet/lib/plugins"
        "--prefix QTWEBENGINEPROCESS_PATH : $out/app/wemeet/bin/QtWebEngineProcess"
        "--set QT_XCB_GL_INTEGRATION xcb_egl"
        "--set QT_OPENGL desktop"
        "--run 'export QTWEBENGINE_CHROMIUM_FLAGS=\"--enable-gpu --no-sandbox --ignore-gpu-blacklist --enable-native-gpu-memory-buffers\"'"
        "--run 'export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib'"
      ];
      commonWrapperArgs = baseWrapperArgs ++ [
        "--prefix LD_PRELOAD : ${libwemeetwrap}/lib/libwemeetwrap.so"
      ];
      xwaylandWrapperArgs = baseWrapperArgs ++ [
        "--set XDG_SESSION_TYPE x11"
        "--unset WAYLAND_DISPLAY"
      ];
    in
    ''
      makeWrapper $out/app/wemeet/bin/wemeetapp $out/bin/wemeet \
        ${lib.concatStringsSep " " commonWrapperArgs}
      makeWrapper $out/app/wemeet/bin/wemeetapp $out/bin/wemeet-xwayland \
        ${lib.concatStringsSep " " xwaylandWrapperArgs}
    '';

  meta = {
    description = "Tencent Video Conferencing";
    homepage = "https://wemeet.qq.com";
    license = lib.licenses.unfree;
    mainProgram = "wemeet";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ lonerOrz ];
  };
}
