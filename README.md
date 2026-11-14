# nix-emulators

Emulator packages for Linux and macOS, with Home Manager modules.

## Packages

| Package | Linux x86_64 | Linux aarch64 | macOS Apple Silicon |
| --- | :---: | :---: | :---: |
| `cemu-git` | ✓ | ✓ | ✓ |
| `eden-nightly-bin` (also `default`) | ✓ | ✓ | ✓ |
| `eden-nightly-bin-pgo` | ✓ | ✓ | — |
| `eden-nightly-bin-zen2` | ✓ | — | — |
| `eden-nightly-bin-zen2-pgo` | ✓ | — | — |
| `eden-nightly-bin-zen4` | ✓ | — | — |
| `eden-nightly-bin-zen4-pgo` | ✓ | — | — |
| `pcsx2-git` | ✓ | — | — |
| `rpcs3-git` | ✓ | ✓ | ✓ |
| `ryubing-git` | ✓ | ✓ | ✓ |
| `shadps4-git` | ✓ | — | — |
| `xenia-canary-git` | ✓ | — | — |
| `xenia-edge-git` | ✓ | — | — |

### Run or install

```sh
nix run github:tolkonepiu/nix-emulators#eden-nightly-bin

nix profile add github:tolkonepiu/nix-emulators#cemu-git
```

### NixOS / Home Manager

Add the flake input:

```nix
inputs.nix-emulators.url = "github:tolkonepiu/nix-emulators";
inputs.nix-emulators.inputs.nixpkgs.follows = "nixpkgs";
```

Pass `inputs` to your configuration and select packages:

```nix
environment.systemPackages = with inputs.nix-emulators.packages.${pkgs.stdenv.hostPlatform.system}; [
  eden-nightly-bin
  cemu-git
];
```

For Home Manager, use `home.packages` instead. Alternatively, use the overlay:

```nix
nixpkgs.overlays = [ inputs.nix-emulators.overlays.default ];
environment.systemPackages = [ pkgs.eden-nightly-bin pkgs.cemu-git ];
```

## Home Manager modules

Import the individual modules shown below, or use
`inputs.nix-emulators.homeManagerModules.default` to make all of them available.
Each module installs its default package; override `package` to select another
build, or set `package = null` to manage configuration without installing it.

### Eden

```nix
{ inputs, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.eden ];

  programs.eden = {
    enable = true; # Uses eden-nightly-bin.
    # Configuration defaults to $XDG_CONFIG_HOME/eden on Linux and macOS.
    settings = {
      # Native qt-config.ini sections; omitted settings use upstream defaults.
      Renderer.backend = 1;
      Controls.player_0_profile_name = "MyController";
    };
    controllerProfiles.MyController.Controls = {
      # Writes input/MyController.ini; replace with your native mapping.
      button_a = "engine:sdl,button:0";
    };
  };
}
```

### Cemu

```nix
{ inputs, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.cemu ];

  programs.cemu = {
    enable = true; # Uses cemu-git.
    # Configuration defaults to $XDG_CONFIG_HOME/Cemu on Linux,
    # or ~/Library/Application Support/Cemu on macOS.
    settings = {
      # Contents of settings.xml's <content> root; omit the root itself.
      GamePaths.Entry = [ "/home/me/Games/Wii U" ];
      Audio.TVVolume = 50;
    };
    controllerProfiles.controller0 = {
      # controller0 is player one; omit the <emulated_controller> root.
      type = "Wii U GamePad";
      controller = [{
        api = "Keyboard";
        uuid = "Keyboard";
        # Lists represent repeated XML tags; @name denotes an attribute,
        # and #text denotes text alongside attributes.
        mappings.entry = [
          { mapping = 1; button = 65; }
          { mapping = 2; button = 66; }
        ];
      }];
    };
    gameProfiles."0005000010101c00" = {
      # Lowercase 16-digit title ID → native game-profile INI sections.
      CPU.cpuMode = "Auto";
      Graphics.graphics_api = 1;
    };
  };
}
```

### Ryubing

```nix
{ inputs, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.ryubing ];

  programs.ryubing = {
    enable = true; # Uses ryubing-git.
    # Configuration defaults to $XDG_CONFIG_HOME/Ryujinx on Linux,
    # or ~/Library/Application Support/Ryujinx on macOS.
    settings = {
      # Native Config.json overrides, merged onto this build's upstream defaults.
      # Do not set the schema version. Arrays replace upstream arrays.
      docked_mode = true;
      res_scale = 2;
    };
    # settings = null; # Default: leave Config.json unmanaged.
  };
}
```

### Xenia Canary

Xenia modules support x86_64 Linux and share an implementation, with independent
configuration and data directories for each fork.

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.xenia-canary ];

  programs.xenia-canary = {
    enable = true; # Uses xenia-canary-git.
    # These are the defaults; paths must be absolute and outside /nix/store.
    configDir = "${config.xdg.configHome}/xenia-canary";
    dataDir = "${config.xdg.dataHome}/xenia-canary";
    settings = {
      # Native sections and keys in xenia-canary.config.toml.
      GPU.gpu = "vulkan";
    };
    profile = {
      # Optional: omit profile entirely for native creation/login behavior.
      # Name: 1–15 ASCII letters/digits, single internal spaces, letter first.
      name = "Player One";
      # Stable offline identity: exactly 16 hex digits, starting with E.
      xuid = "E000000000000001";
      autoLogin = true; # Default: select this profile as player one.
    };
  };
}
```

### Xenia Edge

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.xenia-edge ];

  programs.xenia-edge = {
    enable = true; # Uses xenia-edge-git; otherwise the same options as Canary.
    configDir = "${config.xdg.configHome}/xenia-edge";
    dataDir = "${config.xdg.dataHome}/xenia-edge";
    settings.GPU.gpu = "vulkan"; # Written to xenia-edge.config.toml.
    profile = {
      name = "Player One"; # Used only when creating a new profile.
      xuid = "E000000000000002"; # Keep unchanged to retain this identity.
      autoLogin = false; # Create/load the profile without signing it in.
    };
  };
}
```

## Binary cache

The flake declares this cache in `nixConfig`; accept Nix's prompt to use it
with commands such as `nix run`. For persistent configuration, use either method below.

Enable the public [Cachix cache](https://nix-emulators.cachix.org):

```sh
nix run nixpkgs#cachix -- use nix-emulators
```

Or configure it on NixOS / nix-darwin:

```nix
nix.settings = {
  extra-substituters = [ "https://nix-emulators.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-emulators.cachix.org-1:8lg5Ku12bMegHXq3KWenzzaR4jnv3ddT5W4r75nyCPA="
  ];
};
```

Apply your system configuration afterwards. Enabling the cache means trusting
this project's signed binaries. Only builds already published to it are available.

## Automated updates and CI

Daily update workflows open or refresh one PR per git package. Eden has its own
PR for the shared nightly manifest, including all binary variants.

PRs and pushes to `main` build only affected packages on their supported systems.
Shared packaging or flake changes rebuild all packages; manual CI runs do too.
Only source-package outputs from pushes to `main` are uploaded to Cachix.
Binary packages, update jobs, and PR builds never upload to the cache.
