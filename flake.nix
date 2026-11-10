{
  description = "Emulator packages for Linux and macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.cemu-src = {
    url = "git+https://github.com/cemu-project/Cemu?ref=main&submodules=1";
    flake = false;
  };

  outputs = { nixpkgs, cemu-src, ... }:
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
          cemu-git = pkgs.callPackage ./pkgs/cemu-git {
            src = cemu-src;
            version = "unstable-${builtins.substring 0 8 cemu-src.lastModifiedDate}-${cemu-src.shortRev}";
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
    };
}
