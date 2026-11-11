{ config, lib, pkgs, name, files }:
let
  manifest = pkgs.writeText "${name}-managed-files.json" (builtins.toJSON files);
  state = "${config.xdg.stateHome}/nix-emulators/${name}.json";
in
assert lib.assertMsg (builtins.match "[a-zA-Z0-9_-]+" name != null) "Invalid managed-files name";
lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
  ${pkgs.python3}/bin/python3 ${./managed-files.py} \
    ${lib.escapeShellArg (toString manifest)} ${lib.escapeShellArg state} \
    ''${DRY_RUN_CMD:+--dry-run} ''${VERBOSE:+--verbose}
''
