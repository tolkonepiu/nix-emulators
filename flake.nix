{
  description = "Eden nightly binary packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      manifest = builtins.fromJSON (builtins.readFile ./pkgs/eden-nightly-bin/sources.json);
      packageSet = system: pkgs:
        nixpkgs.lib.mapAttrs' (variant: source: {
          name = "eden-nightly-bin" + nixpkgs.lib.optionalString (variant != "standard") "-${variant}";
          value = pkgs.callPackage ./pkgs/eden-nightly-bin {
            inherit variant source;
            inherit (manifest) version tag;
          };
        }) (manifest.sources.${system} or { });
    in
    {
      packages = nixpkgs.lib.genAttrs (builtins.attrNames manifest.sources) (system:
        let
          packages = packageSet system (import nixpkgs { inherit system; });
        in
        packages // { default = packages.eden-nightly-bin; }
      );

      overlays.default = final: prev: packageSet prev.stdenv.hostPlatform.system final;
    };
}
