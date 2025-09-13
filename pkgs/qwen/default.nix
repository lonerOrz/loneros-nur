{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
  jq,
  git,
}:
let
  pname = "qwen-code";
  version = "0.0.11";

  # 原始源码
  srcOrig = fetchFromGitHub {
    owner = "QwenLM";
    repo = "qwen-code";
    tag = "v${version}";
    hash = "sha256-5qKSWbc0NPpgvt36T/gRSgm1+o2Pbdw3tgfcGba6YSs=";
  };

  src = stdenv.mkDerivation {
    name = "src-fixed";
    version = "v0.0.11-fixed";

    src = srcOrig;

    nativeBuildInputs = [ jq ];

    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
      chmod -R u+w $out

      # 先 patch package.json
      ${jq}/bin/jq 'del(.dependencies."node-pty")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-arm64")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-x64")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-linux-x64")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-arm64")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-x64")' $out/package.json > $out/package.json.tmp && mv $out/package.json.tmp $out/package.json

      # 再 patch package-lock.json
      ${jq}/bin/jq 'del(.dependencies."node-pty")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-arm64")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-x64")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-linux-x64")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-arm64")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-x64")' $out/package-lock.json > $out/package-lock.json.tmp && mv $out/package-lock.json.tmp $out/package-lock.json

      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."node-pty")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-arm64")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-darwin-x64")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-linux-x64")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-arm64")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
      ${jq}/bin/jq 'del(.dependencies."@lydell/node-pty-win32-x64")' $out/packages/core/package.json > $out/packages/core/package.json.tmp && mv $out/packages/core/package.json.tmp $out/packages/core/package.json
    '';
  };
in
buildNpmPackage (finalAttrs: {
  inherit pname version src;

  npmDepsHash = "sha256-tI8s3e3UXE+wV81ctuRsJb3ewL67+a+d9R5TnV99wz4=";

  patches = [
    # similar to upstream gemini-cli some node deps are missing resolved and integrity fields
    # upstream the problem is solved in master and in v0.4+, eventually the fix should arrive to qwen
    ./add-missing-resolved-integrity-fields.patch
  ];

  npmFlags = [
    "--no-optional"
    "--ignore-scripts"
  ];

  nativeBuildInputs = [ git ];

  buildPhase = ''
    runHook preBuild

    npm run generate
    npm run bundle

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/qwen-code
    cp -r bundle/* $out/share/qwen-code/
    patchShebangs $out/share/qwen-code
    ln -s $out/share/qwen-code/gemini.js $out/bin/qwen

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Coding agent that lives in digital world";
    homepage = "https://github.com/QwenLM/qwen-code";
    mainProgram = "qwen";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [
      lonerOrz
      taranarmo
    ];
  };
})
