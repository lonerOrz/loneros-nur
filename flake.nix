{
  description = "My personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      legacyPackages = forAllSystems (
        system:
        let

          lonerOverlay = (import ./overlays/default.nix { flakes = inputs; });
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              rust-overlay.overlays.default
              lonerOverlay
            ];
          };
          overlayPkgs = lonerOverlay pkgs pkgs;

          legacyPkgs =
            import ./default.nix {
              inherit pkgs;
            }
            // overlayPkgs;
        in
        legacyPkgs
      );

      packages = forAllSystems (
        system: nixpkgs.lib.filterAttrs (_: v: nixpkgs.lib.isDerivation v) self.legacyPackages.${system}
      );
    };
}
