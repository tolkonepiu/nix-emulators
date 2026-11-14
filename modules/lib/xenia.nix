{ name, executable, defaultPackage }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.${name};
  toml = pkgs.formats.toml { };
  configFile = "${cfg.configDir}/${name}.config.toml";
  profileSettings = if cfg.profile == null then { } else {
    profile_name = cfg.profile.name;
    profile_xuid = cfg.profile.xuid;
    profile_auto_login = cfg.profile.autoLogin;
  };
  settings = lib.recursiveUpdate (if cfg.settings == null then { } else cfg.settings)
    (lib.optionalAttrs (profileSettings != { }) { Profiles = profileSettings; });
  files = lib.optionalAttrs (cfg.settings != null || profileSettings != { }) {
    ${configFile} = toml.generate "${name}.config.toml" settings;
  };
  launcher = pkgs.writeShellScript "${name}-launcher" ''
    set -e
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArgs [ cfg.configDir "${cfg.dataDir}/content" ]}
    # A missing --config falls back to storage_root instead of configDir.
    if [ ! -e ${lib.escapeShellArg configFile} ]; then
      ${pkgs.coreutils}/bin/touch -- ${lib.escapeShellArg configFile}
    fi
    exec ${lib.escapeShellArg "${cfg.package}/bin/${executable}"} \
      ${lib.escapeShellArgs [ "--config=${configFile}" "--storage_root=${cfg.dataDir}" "--content_root=${cfg.dataDir}/content" ]} "$@"
  '';
  wrappedPackage = pkgs.symlinkJoin {
    name = "${name}-configured";
    paths = [ cfg.package ];
    postBuild = ''
      rm "$out/bin/${executable}"
      ln -s ${launcher} "$out/bin/${executable}"
      for desktop in "$out"/share/applications/*.desktop; do
        [ -e "$desktop" ] || continue
        cp --remove-destination "$(readlink -f "$desktop")" "$desktop"
        substituteInPlace "$desktop" \
          --replace-quiet 'Exec=${executable}' "Exec=$out/bin/${executable}"
      done
    '';
    meta = cfg.package.meta // { mainProgram = executable; };
  };
in
{
  options.programs.${name} = {
    enable = lib.mkEnableOption name;

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage pkgs;
      defaultText = lib.literalExpression "defaultPackage pkgs";
      description = "${name} package to install, or null to manage configuration only. Profile options require the nix-emulators native profile support.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/${name}";
      description = "Absolute writable directory for ${name}.config.toml. The installed launcher selects this file explicitly.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/${name}";
      description = "Absolute writable storage root. Native profiles and saves are stored in its content subdirectory.";
    };

    settings = lib.mkOption {
      type = lib.types.nullOr toml.type;
      default = null;
      description = ''
        Native TOML overrides grouped by section, preserving upstream defaults
        for omitted settings. Null leaves settings unmanaged unless profile
        fields are set. Managed files are replaced with writable copies at each
        activation; initial originals are backed up by the activation helper.
      '';
    };

    profile = lib.mkOption {
      default = null;
      description = "Optional native profile. Null preserves native profile and login behavior; changes apply on the next activation and emulator start.";
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Native gamertag: 1–15 ASCII letters, digits or single internal spaces, starting with a letter.";
          };
          xuid = lib.mkOption {
            type = lib.types.str;
            apply = lib.toUpper;
            description = "Offline profile XUID: exactly 16 hexadecimal digits beginning with E, normalized to uppercase for the native profile directory.";
          };
          autoLogin = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to sign in the managed native profile automatically.";
          };
        };
      });
    };
  };

  config = {
    assertions = lib.optionals cfg.enable [
      {
        assertion = lib.all (path:
          lib.hasPrefix "/" path && path != "/"
          && path != "/nix/store" && !lib.hasPrefix "/nix/store/" path
          && lib.all (part: !builtins.elem part [ "" "." ".." ])
            (lib.tail (lib.splitString "/" path))
        ) [ cfg.configDir cfg.dataDir ];
        message = "programs.${name}.configDir and dataDir must be normalized absolute directories outside /nix/store, not '/'.";
      }
      {
        assertion = cfg.profile == null || builtins.match "E[0-9A-F]{15}" cfg.profile.xuid != null;
        message = "programs.${name}.profile.xuid must be exactly 16 hexadecimal digits beginning with E (an offline account).";
      }
      {
        assertion = cfg.profile == null || (
          builtins.stringLength cfg.profile.name <= 15
          && builtins.match "[A-Za-z][A-Za-z0-9]*( [A-Za-z0-9]+)*" cfg.profile.name != null
        );
        message = "programs.${name}.profile.name must be 1–15 ASCII letters, digits or single internal spaces, starting with a letter.";
      }
      {
        assertion = cfg.profile == null || lib.all (key:
          !(builtins.hasAttr key ((if cfg.settings == null then { } else cfg.settings).Profiles or { }))
        ) [ "profile_name" "profile_xuid" "profile_auto_login" ];
        message = "programs.${name}: set profile fields through profile, not settings.Profiles, when profile is enabled.";
      }
    ];

    home.packages = lib.optional (cfg.enable && cfg.package != null) wrappedPackage;

    home.activation.${name} = import ./managed-files.nix {
      inherit config lib pkgs name;
      files = if cfg.enable then files else { };
    };
  };
}
