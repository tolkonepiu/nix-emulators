{ defaultPackage }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.eden;
  ini = pkgs.formats.ini { };
  withDefaultFlags = lib.mapAttrs (_: section:
    lib.mapAttrs' (key: _: lib.nameValuePair "${key}\\default" false)
      (lib.filterAttrs (key: _: !lib.hasSuffix "\\default" key) section)
    // section
  );
  validProfileName = name:
    name != "" && name != "." && name != ".."
    && !lib.hasInfix "/" name && !lib.hasInfix "\\" name;
  files = lib.optionalAttrs cfg.enable (
    lib.optionalAttrs (cfg.settings != { }) {
      "${cfg.configDir}/qt-config.ini" = ini.generate "eden-qt-config.ini"
        (withDefaultFlags cfg.settings);
    }
    // lib.mapAttrs' (name: settings:
      lib.nameValuePair "${cfg.configDir}/input/${name}.ini"
        (ini.generate "eden-input-${name}.ini" (withDefaultFlags settings))
    ) cfg.controllerProfiles
  );
in
{
  options.programs.eden = {
    enable = lib.mkEnableOption "Eden";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage pkgs;
      defaultText = lib.literalExpression "defaultPackage pkgs";
      description = "Eden package to install, or null for configuration only.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/eden";
      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/eden"'';
      description = ''
        Absolute Eden configuration directory, using XDG on Linux and macOS.
        Use the normal nonportable path: Eden's cwd/user/config portable
        directory takes precedence when present.
      '';
    };

    settings = lib.mkOption {
      type = ini.type;
      default = { };
      description = ''
        Native qt-config.ini sections. Empty settings leave the file unmanaged.
        Managed files are owned in full and activation overwrites GUI edits.
        Scalar keys receive a literal key\default=false companion unless explicitly
        supplied; backslash array keys are otherwise unchanged. Global Controls
        bindings use player_0_button_a-style keys. No hardware-specific defaults
        are provided. Do not put secrets or emulator data here: files enter the Nix store.
      '';
    };

    controllerProfiles = lib.mkOption {
      type = lib.types.attrsOf ini.type;
      default = { };
      description = ''
        Native input/<name>.ini profiles, including empty profiles. Names must be
        nonempty filename stems without slashes or backslashes, excluding "." and "..".
        Controls bindings use button_a-style keys, without a player prefix.
        Default flags are added as for settings; no hardware defaults are supplied.
        Each file is owned in full and activation overwrites GUI edits.
        Do not include secrets or emulator data: files enter the Nix store.
      '';
    };
  };

  config = {
    assertions = lib.mkIf cfg.enable [
      {
        assertion = lib.hasPrefix "/" cfg.configDir;
        message = "programs.eden.configDir must be an absolute path.";
      }
      {
        assertion = lib.all validProfileName (builtins.attrNames cfg.controllerProfiles);
        message = "programs.eden.controllerProfiles names must be nonempty filename stems without / or \\, excluding \".\" and \"..\".";
      }
    ];

    home.packages = lib.mkIf (cfg.enable && cfg.package != null) [ cfg.package ];
    home.activation.eden = import ./lib/managed-files.nix {
      inherit config lib pkgs files;
      name = "eden";
    };
  };
}
