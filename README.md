# nix-emulators

[Eden nightly](https://git.eden-emu.dev/eden-ci/nightly/releases),
[Cemu](https://github.com/cemu-project/Cemu), and
[Ryubing](https://git.ryujinx.app/projects/Ryubing) packages for Linux and macOS,
with Home Manager modules for Eden and Cemu.

## Packages

| Package | Linux x86_64 | Linux aarch64 | macOS Apple Silicon |
| --- | :---: | :---: | :---: |
| `eden-nightly-bin` (also `default`) | ✓ | ✓ | ✓ |
| `eden-nightly-bin-pgo` | ✓ | ✓ | — |
| `eden-nightly-bin-zen2` | ✓ | — | — |
| `eden-nightly-bin-zen2-pgo` | ✓ | — | — |
| `eden-nightly-bin-zen4` | ✓ | — | — |
| `eden-nightly-bin-zen4-pgo` | ✓ | — | — |
| `cemu-git` | ✓ | ✓ | ✓ |
| `ryubing-git` | ✓ | ✓ | ✓ |

### Run or install

```sh
nix run github:tolkonepiu/nix-emulators#eden-nightly-bin
nix run github:tolkonepiu/nix-emulators#cemu-git
nix run github:tolkonepiu/nix-emulators#ryubing-git

nix profile add github:tolkonepiu/nix-emulators#eden-nightly-bin
nix profile add github:tolkonepiu/nix-emulators#cemu-git
nix profile add github:tolkonepiu/nix-emulators#ryubing-git
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
  ryubing-git
];
```

For Home Manager, use `home.packages` instead. Alternatively, use the overlay:

```nix
nixpkgs.overlays = [ inputs.nix-emulators.overlays.default ];
environment.systemPackages = [ pkgs.eden-nightly-bin pkgs.cemu-git pkgs.ryubing-git ];
```

## Home Manager modules

Import `homeManagerModules.default` for both emulators, or
`homeManagerModules.eden` / `homeManagerModules.cemu` individually:

```nix
{ inputs, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.default ];

  programs.eden = {
    enable = true;
    settings = {
      Renderer.backend = 1;
      Controls.player_0_profile_name = "MyController";
    };
    controllerProfiles.MyController.Controls = {
      # Replace with your controller's native mapping.
      button_a = "engine:sdl,button:0";
    };
  };

  programs.cemu = {
    enable = true;
    settings = {
      GamePaths.Entry = [ "/home/me/Games/Wii U" ];
      Audio.TVVolume = 50;
    };
    controllerProfiles.controller0 = {
      type = "Wii U GamePad";
      controller = [{
        api = "Keyboard";
        uuid = "Keyboard";
        mappings.entry = [
          { mapping = 1; button = 65; }
          { mapping = 2; button = 66; }
        ];
      }];
    };
    gameProfiles."0005000010101c00" = {
      CPU.cpuMode = "Auto";
      Graphics.graphics_api = 1;
    };
  };
}
```

| Option | Eden | Cemu |
| --- | --- | --- |
| `package` | Defaults to `eden-nightly-bin` | Defaults to `cemu-git` |
| `settings` | INI sections and keys | Contents of `<content>` as Nix attributes |
| `controllerProfiles` | Profile name → INI sections and keys | Profile name → contents of `<emulated_controller>` as Nix attributes |
| `gameProfiles` | — | Lowercase 16-digit title ID → INI sections and keys |
| `configDir` | Absolute configuration directory override | Absolute configuration directory override |

Set `package = null` to configure an emulator without installing it. Profile
names omit their file extension; Cemu's `controller0` is the active first player.
Cemu settings use lists for repeated tags, `"@name"` for XML attributes and
`"#text"` for text alongside attributes. Omit the root elements. Configuration
can live in separate Nix files: `settings = import ./cemu-settings.nix;`.

Close emulators before applying Home Manager: declared files replace GUI edits.
Do not include secrets in settings, as they enter the Nix store.

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
