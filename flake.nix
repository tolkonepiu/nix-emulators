{
  description = "Emulator packages and Home Manager modules for Linux and macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  nixConfig = {
    extra-substituters = [ "https://nix-emulators.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-emulators.cachix.org-1:8lg5Ku12bMegHXq3KWenzzaR4jnv3ddT5W4r75nyCPA="
    ];
  };

  outputs = { self, nixpkgs, ... }:
    let
      manifest = builtins.fromJSON (builtins.readFile ./pkgs/eden-nightly-bin/sources.json);
      packageSet = system: pkgs:
        nixpkgs.lib.mapAttrs' (variant: source: {
          name = "eden-nightly-bin" + nixpkgs.lib.optionalString (variant != "standard") "-${variant}";
          value = pkgs.callPackage ./pkgs/eden-nightly-bin {
            inherit variant source;
            inherit (manifest) version tag;
          };
        }) (manifest.sources.${system} or { }) // {
          cemu-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/cemu-git;
            manifestPath = "pkgs/cemu-git/manifest.json";
            owner = "cemu-project";
            repo = "Cemu";
            fetchSubmodules = true;
          };
          ryubing-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/ryubing-git;
            manifestPath = "pkgs/ryubing-git/manifest.json";
            domain = "git.ryujinx.app";
            owner = "projects";
            repo = "Ryubing";
            ref = "master";
          };
        } // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          shadps4-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/shadps4-git;
            manifestPath = "pkgs/shadps4-git/manifest.json";
            owner = "shadps4-emu";
            repo = "shadPS4";
            fetchSubmodules = true;
          };
          pcsx2-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/pcsx2-git;
            manifestPath = "pkgs/pcsx2-git/manifest.json";
            owner = "PCSX2";
            repo = "pcsx2";
            ref = "master";
          };
          xenia-canary-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/xenia-canary-git;
            manifestPath = "pkgs/xenia-canary-git/manifest.json";
            owner = "xenia-canary";
            repo = "xenia-canary";
            ref = "canary_experimental";
            fetchSubmodules = true;
          };
          xenia-edge-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/xenia-edge-git;
            manifestPath = "pkgs/xenia-edge-git/manifest.json";
            owner = "has207";
            repo = "xenia-edge";
            ref = "edge";
            fetchSubmodules = true;
          };
        } // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system || system == "aarch64-darwin") {
          rpcs3-git = (import ./shared/git-package.nix { inherit pkgs; }) {
            package = ./pkgs/rpcs3-git;
            manifestPath = "pkgs/rpcs3-git/manifest.json";
            owner = "RPCS3";
            repo = "rpcs3";
            ref = "master";
            fetchSubmodules = true;
          };
        };
    in
    {
      packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
        let
          packages = packageSet system (import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "rpcs3-git";
          });
        in
        packages // { default = packages.eden-nightly-bin; }
      );

      overlays.default = final: prev: packageSet prev.stdenv.hostPlatform.system final;

      homeManagerModules = {
        eden = import ./modules/eden.nix {
          defaultPackage = pkgs: (packageSet pkgs.stdenv.hostPlatform.system pkgs).eden-nightly-bin;
        };
        cemu = import ./modules/cemu.nix {
          defaultPackage = pkgs: (packageSet pkgs.stdenv.hostPlatform.system pkgs).cemu-git;
        };
        ryubing = import ./modules/ryubing.nix {
          defaultPackage = pkgs: (packageSet pkgs.stdenv.hostPlatform.system pkgs).ryubing-git;
        };
        default = {
          imports = [ self.homeManagerModules.eden self.homeManagerModules.cemu self.homeManagerModules.ryubing ];
        };
      };
    };
}
