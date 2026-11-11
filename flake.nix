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
        };
    in
    {
      packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
        let
          packages = packageSet system (import nixpkgs { inherit system; });
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
        default = {
          imports = [ self.homeManagerModules.eden self.homeManagerModules.cemu ];
        };
      };
    };
}
