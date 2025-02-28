{ autoPatchelfHook, makeWrapper, lib, stdenv, fetchurl, openjdk, zlib, alsa-lib, libglvnd, libXi, freetype, libXtst, libXrender, libX11, libXext, fontconfig, dpkg }:

stdenv.mkDerivation rec {
  owner = "amir1376";
  pname = "ab-download-manager";
  version = "1.5.2";

  src = fetchurl {
    url = "https://github.com/${owner}/${pname}/releases/download/v${version}/ABDownloadManager_${version}_linux_x64.deb";
    sha256 = "592cdd94b27899208eaa06e6162dc2c2a6453d6112feb76af651c2a4a351d8eb";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper ];

  buildInputs = [
    openjdk
    zlib
    alsa-lib
    libglvnd
    libXi
    freetype
    libXtst
    libXrender
    libX11
    libXext
    fontconfig
  ];

  propagatedBuildInputs = [ libXext ];

  unpackPhase = ''
    # tar -xvzf $src -C $out
    dpkg -x $src $out  # 使用 dpkg 解压 .deb 文件
  '';

  patchPhase = ''
    sed -i 's|AB Download Manager|Network;|' $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
    sed -i 's|Icon=\/opt\/abdownloadmanager\/lib\/ABDownloadManager.png|Icon=abdownloadmanager|' $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
    sed -i 's|Comment=ABDownloadManager|Comment=Download Manager that speeds up your downloads|' $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
    sed -i 's|MimeType=|StartupNotify=false|' $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
    echo 'StartupWMClass=com.abdownloadmanager.ABDownloadManager' >> $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
    echo 'GenericName=Download Manager' >> $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop
  '';

  installPhase = ''
    rm -rf $out/opt/abdownloadmanager/share
    cp -r $out/opt/abdownloadmanager $out/
    mkdir -p $out/usr/share/applications
    cp $out/opt/abdownloadmanager/lib/abdownloadmanager-ABDownloadManager.desktop $out/usr/share/applications/
    mkdir -p $out/usr/share/icons/hicolor/512x512/apps
    cp $out/opt/abdownloadmanager/lib/ABDownloadManager.png $out/usr/share/icons/hicolor/512x512/apps/abdownloadmanager.png
  '';

  meta = with lib; {
    description = "A Download Manager that speeds up your downloads";
    # license = licenses.apache20;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
    homepage = "https://abdownloadmanager.com/";
  };
}

