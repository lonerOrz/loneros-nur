{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "qwen-code";
  version = "0.0.7";

  src = fetchFromGitHub {
    owner = "QwenLM";
    repo = "qwen-code";
    rev = "v${finalAttrs.version}";
    hash = "sha256-eumtANV/z3pjP/X6ljVnPLRjZtjW+fsB0cvLS7HmQOo=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "sha256-EP2xvXC5+oJ6a3DjDY8ISf7dsLeshIAi6oisN2ZRPgg=";
  };

  buildPhase = ''
    runHook preBuild

    npm run generate
    npm run bundle

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r bundle/* $out/
    patchShebangs $out
    ln -s $out/gemini.js $out/bin/qwen

    runHook postInstall
  '';

  meta = {
    description = "Qwen-code is a coding agent that lives in digital world";
    homepage = "https://github.com/QwenLM/qwen-code";
    mainProgram = "qwen";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ lonerOrz ];
  };
})
