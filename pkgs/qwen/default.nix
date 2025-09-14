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

    # postPatch = ''
    #   # 修改根 package.json
    #   ${jq}/bin/jq '.dependencies."node-pty"="@lydell/node-pty@1.1.0"' \
    #     package.json > package.json.tmp && mv package.json.tmp package.json
    #
    #   # 修改 core 包的 package.json
    #   ${jq}/bin/jq '.dependencies."node-pty"="@lydell/node-pty@1.1.0"' \
    #     packages/core/package.json > core.tmp && mv core.tmp packages/core/package.json
    #
    #   # 修改 lock 文件
    #   ${jq}/bin/jq '(.dependencies."node-pty".version="1.1.0")
    #                | (.dependencies."node-pty".resolved="https://registry.npmjs.org/@lydell/node-pty/-/node-pty-1.1.0.tgz")' \
    #     package-lock.json > lock.tmp && mv lock.tmp package-lock.json
    #
    #       grep -R "node-pty";
    # '';

    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
      chmod -R u+w $out

      echo "Patching getPty.ts in $out"
      sed -i 's/\bnode-pty\b/@lydell\/node-pty/g' $out/packages/core/src/utils/getPty.ts
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
