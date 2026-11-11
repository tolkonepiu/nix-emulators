{ pkgs }:
{
  package,
  manifestPath,
  owner,
  repo,
  ref ? "main",
  fetchSubmodules ? false,
}:
let
  manifest = builtins.fromJSON (builtins.readFile (../. + "/${manifestPath}"));
  src = pkgs.fetchFromGitHub {
    inherit owner repo fetchSubmodules;
    forceFetchGit = true; # Match nix-prefetch-git even for repositories without submodules.
    inherit (manifest) rev hash;
  } // {
    inherit (manifest) lastModifiedDate;
    shortRev = builtins.substring 0 7 manifest.rev;
  };
  result = pkgs.callPackage package {
    inherit src;
    inherit (manifest) version;
  };
  updateScript = pkgs.writeShellApplication {
    name = "update-${result.pname}";
    runtimeInputs = [ pkgs.git pkgs.nix-prefetch-git pkgs.python3 ];
    text = "exec " + pkgs.lib.escapeShellArgs ([
      "${pkgs.python3}/bin/python3"
      "${../scripts/update-git-package.py}"
      "--manifest" manifestPath
      "--owner" owner
      "--repo" repo
      "--ref" ref
    ] ++ pkgs.lib.optional fetchSubmodules "--fetch-submodules");
  };
in
result.overrideAttrs (old: {
  passthru = (old.passthru or { }) // { inherit updateScript; };
})
