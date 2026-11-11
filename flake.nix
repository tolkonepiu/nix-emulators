{
  description = "Emulator packages and Home Manager modules for Linux and macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
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

      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
        import ./tests/home-manager.nix {
          pkgs = import nixpkgs { inherit system; };
          inherit home-manager;
          modules = self.homeManagerModules;
        }
      );
    };
}
