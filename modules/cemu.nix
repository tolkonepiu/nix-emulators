{ defaultPackage }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.cemu;
  ini = pkgs.formats.ini { };
  xml = pkgs.formats.xml { };
  files = lib.optionalAttrs (cfg.settings != null) {
    "${cfg.configDir}/settings.xml" = xml.generate "cemu-settings.xml" { content = cfg.settings; };
  } // lib.mapAttrs' (name: settings: lib.nameValuePair
    "${cfg.configDir}/controllerProfiles/${name}.xml"
    (xml.generate "cemu-controller-${name}.xml" { emulated_controller = settings; })
  ) cfg.controllerProfiles // lib.mapAttrs' (title: settings: lib.nameValuePair
    "${cfg.configDir}/gameProfiles/${title}.ini"
    (ini.generate "cemu-game-${title}.ini" settings)
  ) cfg.gameProfiles;
in
{
  options.programs.cemu = {
    enable = lib.mkEnableOption "Cemu";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage pkgs;
      defaultText = lib.literalExpression "defaultPackage pkgs";
      description = "Cemu package to install, or null to manage configuration only.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = if pkgs.stdenv.hostPlatform.isDarwin then
        "${config.home.homeDirectory}/Library/Application Support/Cemu"
      else
        "${config.xdg.configHome}/Cemu";
      description = "Absolute path to Cemu's native user data directory.";
    };

    settings = lib.mkOption {
      type = lib.types.nullOr xml.type;
      default = null;
      description = ''
        Structured contents of settings.xml; the <content> root is added
        automatically. Use attribute sets for child elements, lists for repeated
        children, @name keys for XML attributes, and #text for element text
        alongside attributes. Null leaves settings unmanaged; {} manages an
        empty <content> root. Raw XML strings are not accepted.
        Managed files are replaced with writable copies at each activation;
        initial originals are backed up by the activation helper.
      '';
    };

    controllerProfiles = lib.mkOption {
      type = lib.types.attrsOf xml.type;
      default = { };
      description = ''
        Structured profile contents keyed by filename stem without .xml; each
        <emulated_controller> root is added automatically. Use controller0 for
        the active player-one controller, or a named profile. Attribute sets
        represent child elements, lists repeat children, @name keys represent
        XML attributes, and #text holds text alongside attributes. Native
        controller entries use api, uuid, and mappings.entry child elements.
        Raw XML strings are not accepted.
      '';
    };

    gameProfiles = lib.mkOption {
      type = lib.types.attrsOf ini.type;
      default = { };
      description = "Native game profile INI settings keyed by lowercase, 16-digit hexadecimal title ID.";
    };
  };

  config = {
    assertions = lib.optionals cfg.enable [
      {
        assertion = lib.hasPrefix "/" cfg.configDir;
        message = "programs.cemu.configDir must be an absolute path.";
      }
      {
        assertion = lib.all (name:
          name != "" && name != "." && name != ".."
          && !lib.hasInfix "/" name && !lib.hasInfix "\\" name
        ) (builtins.attrNames cfg.controllerProfiles);
        message = "programs.cemu.controllerProfiles names must be nonempty filename stems without slashes; '.' and '..' are not allowed.";
      }
      {
        assertion = lib.all (title: builtins.match "[0-9a-f]{16}" title != null)
          (builtins.attrNames cfg.gameProfiles);
        message = "programs.cemu.gameProfiles keys must be exactly 16 lowercase hexadecimal digits.";
      }
    ];

    home.packages = lib.optional (cfg.enable && cfg.package != null) cfg.package;

    home.activation.cemu = import ./lib/managed-files.nix {
      inherit config lib pkgs;
      name = "cemu";
      files = if cfg.enable then files else { };
    };
  };
}
