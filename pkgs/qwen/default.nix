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

    postPatch = ''
      echo "Patching package.json for platform-specific dependencies..."

      if [ "$(uname)" = "Darwin" ]; then
        echo "Detected Darwin: removing node-pty to avoid build failure"

        # 根 package.json
        ${jq}/bin/jq 'del(.dependencies."node-pty", .dependencies."@lydell/node-pty")
                      | .optionalDependencies?"node-pty" //= "optional"' package.json > package.json.tmp
        mv package.json.tmp package.json

        # core 包 package.json
        ${jq}/bin/jq 'del(.dependencies."node-pty", .dependencies."@lydell/node-pty")
                      | .optionalDependencies?"node-pty" //= "optional"' packages/core/package.json > core.tmp
        mv core.tmp packages/core/package.json

        # package-lock.json
        ${jq}/bin/jq 'del(.dependencies."node-pty", .dependencies."@lydell/node-pty")' package-lock.json > lock.tmp
        mv lock.tmp package-lock.json

      else
        echo "Non-Darwin platform: pin node-pty to @lydell/node-pty@1.1.0"

        # 根 package.json
        ${jq}/bin/jq '.dependencies."node-pty"="@lydell/node-pty@1.1.0"' package.json > package.json.tmp
        mv package.json.tmp package.json

        # core 包 package.json
        ${jq}/bin/jq '.dependencies."node-pty"="@lydell/node-pty@1.1.0"' packages/core/package.json > core.tmp
        mv core.tmp packages/core/package.json

        # package-lock.json
        ${jq}/bin/jq '(.dependencies."node-pty".version="1.1.0")
                     | (.dependencies."node-pty".resolved="https://registry.npmjs.org/@lydell/node-pty/-/node-pty-1.1.0.tgz")' package-lock.json > lock.tmp
        mv lock.tmp package-lock.json
      fi

      grep -R "node-pty" || echo "node-pty removed"
    '';

    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out/
      chmod -R u+w $out
    '';
  };
in
buildNpmPackage (finalAttrs: {
  inherit pname version src;

  npmDepsHash = "sha256-tI8s3e3UXE+wV81ctuRsJb3ewL67+a+d9R5TnV99wz4=";

  patches = [
    ./add-missing-resolved-integrity-fields.patch
  ];

  nativeBuildInputs = [ git ];

  buildPhase = ''
    runHook preBuild
    npm install --legacy-peer-deps
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
