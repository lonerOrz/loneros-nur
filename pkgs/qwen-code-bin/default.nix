{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
}:
let
  owner = "QwenLM";
  repo = "qwen-code";
  asset = "gemini.js";
  version = "0.0.11-nightly.8";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "qwen-code-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/${owner}/${repo}/releases/download/v${version}/${asset}";
    hash = "sha256-03lh6mfs1jrlh8ghcj5p11sdcqnmb4nmgyirq04nqrg58lrfr6rg";
  };

  phases = [
    "installPhase"
    "fixupPhase"
  ];

  strictDeps = true;

  buildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    install -D "$src" "$out/bin/qwen"

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Coding agent that lives in the digital world";
    homepage = "https://github.com/QwenLM/qwen-code";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ lonerOrz ];
    mainProgram = "qwen";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
})
