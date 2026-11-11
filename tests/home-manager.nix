{ pkgs, home-manager, modules }:
let
  inherit (pkgs) lib;
  fixtureHome = "/nix-emulators-hm-fixture";
  evaluate = module: extra: home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ module {
      home.username = "hm-test";
      home.homeDirectory = fixtureHome;
      home.stateVersion = "24.11";
    } extra ];
  };
  configuration = extra: evaluate modules.default extra;
  disabled = configuration { };
  defaults = configuration {
    programs.eden.enable = true;
    programs.cemu.enable = true;
  };
  settingsXML = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <content><GamePaths><Entry>/games/雪 &amp; ice</Entry><Entry>/games/two</Entry></GamePaths>
    <GraphicPack><Entry filename="packs/A&amp;B" enabled="true"/><Entry filename="packs/雪" enabled="false"/></GraphicPack></content>
  '';
  controllerXML = ''
    <emulated_controller><type>Wii U GamePad</type><controller api="SDL" uuid="A&amp;B"><mapping>1</mapping><mapping>2</mapping></controller><controller api="Keyboard"/></emulated_controller>
  '';
  enabledOptions = {
    xdg.configHome = "${fixtureHome}/custom-config";
    xdg.stateHome = "${fixtureHome}/custom-state";
    programs.eden = {
      enable = true;
      package = null;
      settings = {
        UI = { theme = "雪"; "theme\\default" = true; };
        Controls = { player_0_button_a = "engine:sdl,button:0"; "favorites\\1\\name" = "first"; };
      };
      controllerProfiles = {
        pad.Controls.button_a = "engine:sdl,button:1";
        empty = { };
      };
    };
    programs.cemu = {
      enable = true;
      package = null;
      settings = settingsXML;
      controllerProfiles.controller0 = controllerXML;
      gameProfiles."00050000101abcde" = {
        General = { name = "雪"; loadSharedLibraries = true; };
        Graphics.graphics_api = 1;
      };
    };
  };
  enabled = configuration enabledOptions;
  removed = configuration (enabledOptions // {
    programs = {
      eden = enabledOptions.programs.eden // {
        settings = { UI.theme = "updated"; };
        controllerProfiles = { };
      };
      cemu = enabledOptions.programs.cemu // {
        settings = "<content><changed>true</changed></content>";
        controllerProfiles = { };
        gameProfiles = { };
      };
    };
  });
  off = configuration (enabledOptions // {
    programs = {
      eden = enabledOptions.programs.eden // { enable = false; };
      cemu = enabledOptions.programs.cemu // { enable = false; };
    };
  });
  override = configuration {
    programs.eden = { enable = true; package = pkgs.hello; configDir = "${fixtureHome}/eden-override"; };
    programs.cemu = { enable = true; package = pkgs.hello; configDir = "${fixtureHome}/cemu-override"; };
  };
  rejects = extra: !(builtins.tryEval (configuration extra).activationPackage.drvPath).success;
  badProfile = name: program: rejects {
    programs.${program} = {
      enable = true;
      package = null;
      controllerProfiles.${name} = if program == "eden" then { } else controllerXML;
    };
  };
  checks = [
    (!disabled.config.programs.eden.enable && !disabled.config.programs.cemu.enable)
    (defaults.config.programs.eden.package.pname == "eden-nightly-bin")
    (defaults.config.programs.cemu.package.pname == "cemu-git")
    (lib.elem defaults.config.programs.eden.package defaults.config.home.packages)
    (lib.elem defaults.config.programs.cemu.package defaults.config.home.packages)
    (enabled.config.programs.eden.package == null && enabled.config.programs.cemu.package == null)
    (map toString enabled.config.home.packages == map toString off.config.home.packages)
    (lib.elem pkgs.hello override.config.home.packages)
    (override.config.programs.eden.configDir == "${fixtureHome}/eden-override")
    (override.config.programs.cemu.configDir == "${fixtureHome}/cemu-override")
    (disabled.config.programs.eden.configDir == "${fixtureHome}/.config/eden")
    (disabled.config.programs.cemu.configDir == (if pkgs.stdenv.hostPlatform.isDarwin
      then "${fixtureHome}/Library/Application Support/Cemu" else "${fixtureHome}/.config/Cemu"))
    (enabled.config.programs.eden.configDir == "${fixtureHome}/custom-config/eden")
    (enabled.config.programs.cemu.configDir == (if pkgs.stdenv.hostPlatform.isDarwin
      then "${fixtureHome}/Library/Application Support/Cemu" else "${fixtureHome}/custom-config/Cemu"))
    (builtins.isString (evaluate modules.eden { }).activationPackage.drvPath)
    (builtins.isString (evaluate modules.cemu { }).activationPackage.drvPath)
    (builtins.isString enabled.activationPackage.drvPath)
    (builtins.isString disabled.activationPackage.drvPath)
    (lib.all (name: badProfile name "eden" && badProfile name "cemu") [ "" "." ".." "../escape" "a/b" "a\\b" ])
    (lib.all (program: rejects { programs.${program} = { enable = true; package = null; configDir = "relative"; }; }) [ "eden" "cemu" ])
    (lib.all (title: rejects { programs.cemu = { enable = true; package = null; gameProfiles.${title} = { }; }; })
      [ "00050000101ABCDE" "1234" "00050000101abcdeg" "../00050000101abcde" ])
  ];
  activation = cfg: lib.concatMapStringsSep "\n" (name: cfg.config.home.activation.${name}.data) [ "eden" "cemu" ];
  scripts = lib.mapAttrs (name: cfg: pkgs.writeText "hm-${name}.sh" (activation cfg)) {
    inherit enabled removed off;
  };
in
{
  home-manager = assert lib.all (value: value) checks; pkgs.runCommand "home-manager-tests" {
    nativeBuildInputs = [ pkgs.python3 pkgs.bash ];
    enabledScript = scripts.enabled;
    removedScript = scripts.removed;
    offScript = scripts.off;
    cemuDir = lib.removePrefix fixtureHome enabled.config.programs.cemu.configDir;
  } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python3 - <<'PY'
    import configparser
    import json
    import os
    from pathlib import Path
    import re
    import stat
    import subprocess
    import xml.etree.ElementTree as ET

    home = Path(os.environ["HOME"])
    eden = home / "custom-config/eden"
    cemu = Path(str(home) + os.environ["cemuDir"])
    states = home / "custom-state/nix-emulators"

    def activate(generation, dry=False):
        # Run the real DAG commands, relocating fixture targets (including those
        # inside store manifests) into this build's isolated temporary HOME.
        script = Path(os.environ[generation + "Script"]).read_text()
        for index, source in enumerate(set(re.findall(r"/nix/store/[^\s'\"]+-managed-files\.json", script))):
            manifest = home.parent / f"{generation}-{index}.json"
            contents = json.loads(Path(source).read_text())
            manifest.write_text(json.dumps({key.replace("${fixtureHome}", str(home)): value for key, value in contents.items()}))
            script = script.replace(source, str(manifest))
        script = script.replace("${fixtureHome}", str(home))
        environment = dict(os.environ, DRY_RUN_CMD="echo" if dry else "", VERBOSE_ARG="")
        subprocess.run(["bash", "-eu", "-c", script], env=environment, check=True)

    def snapshot():
        return {str(path.relative_to(home)): (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
                for path in home.rglob("*") if path.is_file()}

    def ini(path):
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        parser.read(path)
        return parser

    activate("off")
    # Empty manifests may persist bookkeeping, but must not create emulator files.
    assert not eden.exists() and not cemu.exists()
    before = snapshot()
    activate("enabled", dry=True)
    assert snapshot() == before
    assert not eden.exists() and not cemu.exists()
    for directory, filename in [(eden, "qt-config.ini"), (cemu, "settings.xml")]:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / filename).write_text("original")
        (directory / "unmanaged").write_text("keep")
    activate("enabled")
    expected = [eden / "qt-config.ini", eden / "input/pad.ini", eden / "input/empty.ini",
                cemu / "settings.xml", cemu / "controllerProfiles/controller0.xml",
                cemu / "gameProfiles/00050000101abcde.ini"]
    for path in expected:
        assert path.is_file() and not path.is_symlink(), path
        assert stat.S_IMODE(path.stat().st_mode) & stat.S_IWUSR, path
    generated = {path: path.read_bytes() for path in expected}
    settings = ini(eden / "qt-config.ini")
    assert settings["UI"]["theme"] == "雪"
    assert settings["UI"]["theme\\default"] == "true"
    assert settings["Controls"]["player_0_button_a\\default"] == "false"
    assert settings["Controls"]["favorites\\1\\name"] == "first"
    assert settings["Controls"]["favorites\\1\\name\\default"] == "false"
    profile = ini(eden / "input/pad.ini")
    assert profile["Controls"]["button_a"] == "engine:sdl,button:1"
    assert profile["Controls"]["button_a\\default"] == "false"
    root = ET.parse(cemu / "settings.xml").getroot()
    assert root.tag == "content"
    assert [node.text for node in root.findall("GamePaths/Entry")] == ["/games/雪 & ice", "/games/two"]
    assert [node.attrib for node in root.findall("GraphicPack/Entry")] == [
        {"filename": "packs/A&B", "enabled": "true"}, {"filename": "packs/雪", "enabled": "false"}]
    root = ET.parse(cemu / "controllerProfiles/controller0.xml").getroot()
    assert root.tag == "emulated_controller" and len(root.findall("controller")) == 2
    assert root.find("controller").attrib["uuid"] == "A&B"
    assert [node.text for node in root.findall("controller/mapping")] == ["1", "2"]
    game = ini(cemu / "gameProfiles/00050000101abcde.ini")
    assert game["General"]["name"] == "雪" and game["General"]["loadSharedLibraries"] == "true"
    assert game["Graphics"]["graphics_api"] == "1"
    for name, directory in [("eden", eden), ("cemu", cemu)]:
        owned = json.loads((states / (name + ".json")).read_text())
        assert set(owned) == {str(path) for path in expected if path.is_relative_to(directory)}
    for path in expected:
        path.write_text("GUI edit")
    activate("enabled")
    assert all(path.read_bytes() == content for path, content in generated.items())
    for path in [eden / "qt-config.ini", cemu / "settings.xml"]:
        assert Path(str(path) + ".hm-backup").read_text() == "original"
    assert not Path(str(eden / "input/pad.ini") + ".hm-backup").exists()
    before = snapshot()
    activate("off", dry=True)
    assert snapshot() == before
    activate("removed")
    assert ini(eden / "qt-config.ini")["UI"]["theme"] == "updated"
    assert ET.parse(cemu / "settings.xml").getroot().findtext("changed") == "true"
    assert all(not path.exists() for path in expected if path.name not in ["qt-config.ini", "settings.xml"])
    activate("off")
    assert all(not path.exists() for path in expected)
    for name, directory in [("eden", eden), ("cemu", cemu)]:
        assert json.loads((states / (name + ".json")).read_text()) == []
        assert (directory / "unmanaged").read_text() == "keep"
    for path in [eden / "qt-config.ini", cemu / "settings.xml"]:
        assert Path(str(path) + ".hm-backup").read_text() == "original"
    PY
    touch "$out"
  '';

  managed-files = pkgs.runCommand "managed-files-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p source/modules/lib source/tests
    cp ${../modules/lib/managed-files.py} source/modules/lib/managed-files.py
    cp ${./test_managed_files.py} source/tests/test_managed_files.py
    python3 source/tests/test_managed_files.py
    touch "$out"
  '';
}
