{ defaultPackage }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.ryubing;
  json = pkgs.formats.json { };
  package = if cfg.package != null then cfg.package else defaultPackage pkgs;
  files = lib.optionalAttrs (cfg.settings != null) {
    "${cfg.configDir}/Config.json" = pkgs.runCommand "ryubing-config.json" {
      nativeBuildInputs = [ pkgs.jq ];
    } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      unset DISPLAY WAYLAND_DISPLAY
      ${lib.getExe package} --dump-default-config "$TMPDIR/defaults.json"
      jq -s '.[0] * .[1]' "$TMPDIR/defaults.json" ${json.generate "ryubing-overrides.json" cfg.settings} > "$out"
    '';
  };
in
{
  options.programs.ryubing = {
    enable = lib.mkEnableOption "Ryubing";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage pkgs;
      defaultText = lib.literalExpression "defaultPackage pkgs";
      description = ''
        Ryubing package to install, or null to manage configuration only.
        When settings are managed, the package must support
        --dump-default-config <absolute-output-file>; null uses the default package
        to generate settings without installing it.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = if pkgs.stdenv.hostPlatform.isDarwin then
        "${config.home.homeDirectory}/Library/Application Support/Ryujinx"
      else
        "${config.xdg.configHome}/Ryujinx";
      description = "Absolute path to Ryubing's native user data directory.";
    };

    settings = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf json.type);
      default = null;
      description = ''
        Native snake_case Config.json overrides, recursively merged onto the
        complete upstream defaults exported by the selected package at build
        time. Arrays are replaced, not appended. The schema version is inherited
        automatically and must not be overridden. Null leaves settings unmanaged;
        {} manages the complete upstream defaults.
        Managed files are replaced with writable copies at each activation;
        initial originals are backed up by the activation helper.
      '';
    };
  };

  config = {
    assertions = lib.optionals cfg.enable [
      {
        assertion = lib.hasPrefix "/" cfg.configDir;
        message = "programs.ryubing.configDir must be an absolute path.";
      }
      {
        assertion = cfg.settings == null || !(cfg.settings ? version);
        message = "programs.ryubing.settings.version must not be set; the schema version is inherited from upstream defaults.";
      }
    ];

    home.packages = lib.optional (cfg.enable && cfg.package != null) cfg.package;

    home.activation.ryubing = import ./lib/managed-files.nix {
      inherit config lib pkgs;
      name = "ryubing";
      files = if cfg.enable then files else { };
    };
  };
}
