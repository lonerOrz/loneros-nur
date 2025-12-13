{
  flakes,
  nixpkgs ? flakes.nixpkgs,
  self ? flakes.self,
  selfOverlay ? self.overlays.default,
  rust-overlay ? flakes.rust-overlay,
  nixpkgsExtraConfig ? { },
}:
final: prev:

let
  # Required to load version files.
  inherit (final.lib.trivial) importJSON;

  # Our utilities/helpers.
  Utils = import ../lib/utils.nix {
    inherit (final) lib;
    lonerOverlay = selfOverlay;
  };
  inherit (Utils) multiOverride overrideDescription drvDropUpdateScript;

  # Helps when calling .nix that will override packages.
  callOverride =
    path: attrs:
    import path (
      {
        inherit
          final
          flakes
          Utils
          prev
          gitOverride
          rustPlatform_latest
          ;
      }
      // attrs
    );

  # Helps when calling .nix that will override i686-packages.
  callOverride32 =
    path: attrs:
    import path (
      {
        inherit flakes Utils gitOverride;
        final = final.pkgsi686Linux;
        final64 = final;
        prev = prev.pkgsi686Linux;
      }
      // attrs
    );

  # Magic helper for _git packages.
  gitOverride = import ../lib/git-override.nix {
    inherit (final)
      lib
      callPackage
      fetchFromGitHub
      fetchFromGitLab
      fetchFromGitea
      ;
    inherit (final.rustPlatform) fetchCargoVendor;
    lonerosNur = self;
    fetchRevFromGitHub = final.callPackage ../lib/github-rev-fetcher.nix { };
    fetchRevFromGitLab = final.callPackage ../lib/gitlab-rev-fetcher.nix { };
    fetchRevFromGitea = final.callPackage ../lib/gitea-rev-fetcher.nix { };
  };

  rustc_latest = rust-overlay.packages.${final.stdenv.hostPlatform.system}.rust;

  # Latest rust toolchain from Fenix
  rustPlatform_latest = final.makeRustPlatform {
    cargo = rustc_latest;
    rustc = rustc_latest;
  };

  # Too much variations
  cachyosPackages = callOverride ../pkgs/linux-cachyos { };

  # Microarch stuff
  makeMicroarchPkgs = import ../lib/make-microarch.nix {
    inherit
      nixpkgs
      final
      selfOverlay
      nixpkgsExtraConfig
      ;
  };

  # Required for 32-bit packages
  has32 = final.stdenv.hostPlatform.isLinux && final.stdenv.hostPlatform.isx86;

  # Required for kernel packages
  inherit (final.stdenv) isLinux;
in
{
  inherit Utils rustc_latest;
  generic-git-update = final.callPackage ./generic-git-update { };

  evil-helix_git = callOverride ./helix-git { evil = true; };
  helix_git = callOverride ./helix-git { };
}
