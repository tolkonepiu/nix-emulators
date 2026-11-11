{ defaultPackage }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.cemu;
  ini = pkgs.formats.ini { };
  generateXML = name: root: text:
    pkgs.runCommand name {
      nativeBuildInputs = [ pkgs.python3 ];
      passAsFile = [ "text" ];
      inherit text;
      expectedRoot = root;
    } ''
      python - <<'PY'
      import os
      import shutil
      import xml.etree.ElementTree as ET

      source = os.environ["textPath"]
      root = ET.parse(source).getroot()
      if root.tag != os.environ["expectedRoot"]:
          raise ValueError(f"Expected XML root <{os.environ['expectedRoot']}>, got <{root.tag}>")
      shutil.copyfile(source, os.environ["out"])
      PY
    '';
  files = lib.optionalAttrs (cfg.settings != null) {
    "${cfg.configDir}/settings.xml" = generateXML "cemu-settings.xml" "content" cfg.settings;
  } // lib.mapAttrs' (name: text: lib.nameValuePair
    "${cfg.configDir}/controllerProfiles/${name}.xml"
    (generateXML "cemu-controller-${name}.xml" "emulated_controller" text)
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
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Complete native settings.xml document with a <content> root, or null
        to leave settings unmanaged. Raw XML preserves attributes, repeated
        elements, all settings categories, and graphics pack selections.
        Managed files are replaced with writable copies at each activation;
        initial originals are backed up by the activation helper.
      '';
    };

    controllerProfiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        Complete native XML documents with an <emulated_controller> root,
        keyed by filename stem without .xml. Use controller0 for the active
        player-one controller, or a named profile. Repeated controller and
        mapping elements and attributes are preserved verbatim.
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
