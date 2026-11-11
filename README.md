# nix-emulators

A collection of emulator packages for Nix: prebuilt
[Eden nightly](https://git.eden-emu.dev/eden-ci/nightly/releases) binaries and
[Cemu](https://github.com/cemu-project/Cemu) built from a pinned commit of `main`.
Downloads and source trees are content-hash pinned, never unpinned `latest` builds.

## Binary cache

CI publishes builds to the public [nix-emulators Cachix cache](https://nix-emulators.cachix.org).
Downloading from it does not require a token. Enable it before building:

```sh
nix run nixpkgs#cachix -- use nix-emulators
```

On NixOS or nix-darwin, configure it declaratively instead:

```nix
nix.settings = {
  extra-substituters = [ "https://nix-emulators.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-emulators.cachix.org-1:8lg5Ku12bMegHXq3KWenzzaR4jnv3ddT5W4r75nyCPA="
  ];
};
```

Apply your system configuration afterwards. Enabling the cache means trusting
this project's signed binaries; the default Nix cache remains enabled.
Only outputs already published by CI can be downloaded. Different nixpkgs pins
or package options may still require local builds.

## Cemu git

`cemu-git` builds upstream `main` from source for Linux (x86_64 and aarch64) and
macOS (Apple Silicon). The commit, recursive source hash and version are pinned
in `pkgs/cemu-git/manifest.json`; building does not silently update them.
Versions use `unstable-YYYYMMDDHHMMSS-<rev>` with the commit's UTC timestamp.
Upstream considers macOS support experimental.

```sh
nix run github:tolkonepiu/nix-emulators#cemu-git
nix profile add github:tolkonepiu/nix-emulators#cemu-git
# Build the checked-out version locally:
nix build .#cemu-git
```

The package is also available through the overlay as `pkgs.cemu-git` and can be
selected in NixOS `environment.systemPackages` or Home Manager `home.packages`
using the same input setup shown below for Eden. The executable is `cemu`.
Eden remains the default.
On macOS the bundle is installed under `Applications/Cemu.app` in the package.

## Eden packages

| Package | Linux x86_64 | Linux aarch64 | macOS Apple Silicon |
| --- | :---: | :---: | :---: |
| `eden-nightly-bin` (also `default`) | ✓ | ✓ | ✓ |
| `eden-nightly-bin-pgo` | ✓ | ✓ | — |
| `eden-nightly-bin-zen2` | ✓ | — | — |
| `eden-nightly-bin-zen2-pgo` | ✓ | — | — |
| `eden-nightly-bin-zen4` | ✓ | — | — |
| `eden-nightly-bin-zen4-pgo` | ✓ | — | — |

`zen2` selects upstream's Steam Deck build; `zen4` selects its ROG Ally build.
Both have standard and profile-guided optimization (PGO) versions. Selection
is explicit: the flake never detects your CPU or silently enables PGO.
The default Eden package is the standard build for the selected system.

The generic x86_64 builds target modern CPUs (Ryzen / Intel Haswell or newer);
upstream's separate legacy builds are not packaged. Do not install Zen-specific
builds on incompatible CPUs. Choose one variant per profile: they all provide
the `eden` executable and the same desktop application.

The current macOS DMG contains an **arm64-only** `eden.app`, not a universal
binary. Upstream labels macOS builds experimental
and warns about graphical glitches and crashes. Nix does not remove macOS
security checks; allow the application in Privacy & Security only if you trust it.

### Run or install

```sh
# Standard build for your system
nix run github:tolkonepiu/nix-emulators#eden-nightly-bin

# Steam Deck / Zen 2, with PGO
nix run github:tolkonepiu/nix-emulators#eden-nightly-bin-zen2-pgo

# Install instead of running once
nix profile add github:tolkonepiu/nix-emulators#eden-nightly-bin-zen2-pgo
```

Linux packages include a desktop entry and icon. On macOS the bundle is installed
under the package's `Applications/eden.app`, with an `eden` command-line launcher.
For local builds use `nix build .#eden-nightly-bin` (or another name above).

### NixOS / Home Manager

Add the flake input:

```nix
inputs.nix-emulators.url = "github:tolkonepiu/nix-emulators";
inputs.nix-emulators.inputs.nixpkgs.follows = "nixpkgs";
```

Pass `inputs` to your configuration, then select a package directly:

```nix
environment.systemPackages = [
  inputs.nix-emulators.packages.${pkgs.stdenv.hostPlatform.system}.eden-nightly-bin-zen2-pgo
];
```

For Home Manager use the same package in `home.packages`. Alternatively, apply
the overlay and select the package from `pkgs`:

```nix
nixpkgs.overlays = [ inputs.nix-emulators.overlays.default ];
environment.systemPackages = [ pkgs.eden-nightly-bin-zen2-pgo ];
```

## Home Manager modules

Import either `homeManagerModules.eden` or `homeManagerModules.cemu`, or
`homeManagerModules.default` for both. No overlay, NixOS, Jovian, Steam Deck,
or systemd/tmpfiles integration is required. Modules use your Home Manager
`pkgs` to build the default packages; the Home Manager flake input in this
repository is for tests, not an extra module to import into your configuration.

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-emulators.homeManagerModules.default ];

  programs.eden = {
    enable = true;
    # Optional; defaults to the generic eden-nightly-bin package.
    package = inputs.nix-emulators.packages.${pkgs.stdenv.hostPlatform.system}.eden-nightly-bin;
    settings = {
      Renderer = {
        backend = 1;
        use_disk_shader_cache = true;
      };
      Controls.player_0_profile_name = "MyController";
    };
    controllerProfiles.MyController.Controls = {
      # Replace with your controller's native Eden mapping strings.
      button_a = "engine:sdl,button:0";
      motion_enabled = true;
    };
  };

  programs.cemu = {
    enable = true;
    # Complete native XML, including the <content> root.
    settings = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <content>
        <GamePaths>
          <Entry>/home/me/Games/Wii U</Entry>
          <Entry>/mnt/games/Wii U</Entry>
        </GamePaths>
        <Audio><TVVolume>50</TVVolume></Audio>
      </content>
    '';
    # Read your native profile, including its <emulated_controller> root.
    # controller0 is the active first-player profile; other names are presets.
    controllerProfiles.controller0 = builtins.readFile ./controller0.xml;
    gameProfiles."0005000010101c00" = {
      CPU.cpuMode = "Auto";
      Graphics.graphics_api = 1;
    };
  };
}
```

### Options and native formats

| Option | Eden | Cemu |
| --- | --- | --- |
| `enable` | Install and configure Eden | Install and configure Cemu |
| `package` | Defaults to `eden-nightly-bin` | Defaults to `cemu-git` |
| `settings` | INI section/key attributes; `{ }` leaves settings unmanaged | Complete XML string; `null` leaves settings unmanaged |
| `controllerProfiles` | Filename stem → INI section/key attributes | Filename stem → complete native XML string |
| `gameProfiles` | — | Lowercase 16-digit title ID → INI section/key attributes |
| `configDir` | Absolute native configuration directory override | Absolute native configuration/user-data directory override |

Set `package = null` to manage configuration without installing an emulator.
Enabling a module alone does not take ownership of any configuration files.
Profile names omit `.ini`/`.xml` and cannot contain slashes or be `.`/`..`.

Eden uses `${XDG_CONFIG_HOME:-~/.config}/eden` on **both Linux and macOS**.
Cemu uses `${XDG_CONFIG_HOME:-~/.config}/Cemu` on Linux and
`~/Library/Application Support/Cemu` on macOS. Modules follow
`xdg.configHome` on the XDG paths. If you customize it, ensure the emulator
receives the matching `XDG_CONFIG_HOME` environment variable. `configDir`
changes where files are managed; it does not change an emulator's runtime path.
Eden's portable `user/config` directory in its working directory takes precedence;
avoid portable mode or point `configDir` at the directory actually used.
The provided Cemu package disables portable mode.

Eden settings are native INI, including literal backslash keys such as
`"Paths\\gamedirs\\1\\path"`. The module adds `key\default=false` companions
so upstream uses declared values; explicitly supplied default flags win.
Global controller keys have the `player_0_` prefix; keys inside an input profile
do not. Mapping strings, device identifiers, calibration, motion/UDP settings,
and other native sections remain user-supplied, without hardware assumptions.

Cemu XML is kept verbatim rather than converted from an attribute set, preserving
attributes and repeated elements for game paths, controller mappings, graphics
pack selections, and other native settings. XML is checked for well-formedness
and the expected root at build time. Start with files exported by your Cemu
version; the module does not invent device UUIDs or validate every emulator key.
Game profile options likewise use Cemu's native INI names. Game data, firmware,
keys, saves, shader caches, and graphics-pack assets are not managed by these
modules. Do not put secrets in settings: generated configuration is public in
the Nix store.

### Activation and existing installations

**Close the emulators before activating Home Manager.** Each declared file is
owned in full, not merged. Activation installs ordinary writable files, even
over an existing installation, and reapplies the declaration on **every**
activation, including reactivation of the same generation. GUI changes work
between activations but are overwritten by the next activation. This is not
one-time seeding or an immutable configuration symlink.

Before first replacing an existing file, the module preserves it beside the
original as `<filename>.hm-backup`. An existing backup is never overwritten;
if it differs from the original during first takeover, activation stops safely.
Move that backup somewhere safe before retrying.
Existing symlinks are replaced without modifying their source. Keep any wanted
GUI settings in Nix before activating; backups are migration safeguards, not a
history of later GUI edits.

Removing a declared file/profile or setting `enable = false` removes files
previously owned by that module on the next activation. Other files in the
directory, game data, and migration backups are left alone. Ownership is tracked
under `xdg.stateHome/nix-emulators/`; do not delete this state to reset settings.
To uninstall cleanly, disable and activate **before** removing the module import.
Removing an import cannot run its cleanup. Backups are not automatically restored.
Home Manager dry runs do not modify files.

The path and format choices follow upstream source: Eden's
[path selection](https://git.eden-emu.dev/eden-emu/eden/src/commit/cf654052c416f9e7c80cef0a7d321476b1c52f99/src/common/fs/path_util.cpp)
and [INI handling](https://git.eden-emu.dev/eden-emu/eden/src/commit/cf654052c416f9e7c80cef0a7d321476b1c52f99/src/frontend_common/config.cpp),
and Cemu's [platform paths](https://github.com/cemu-project/Cemu/blob/b487cb70ed96cf6a3b5385d1aeff6ea41eaa3f63/src/gui/wxgui/CemuApp.cpp)
and [controller profile serialization](https://github.com/cemu-project/Cemu/blob/b487cb70ed96cf6a3b5385d1aeff6ea41eaa3f63/src/input/InputManager.cpp).

### Module validation

```sh
nix flake check --all-systems --no-build
nix build --no-link .#checks.x86_64-linux.home-manager
nix build --no-link .#checks.x86_64-linux.managed-files
```

CI runs the checks natively on Linux x86_64/aarch64 and macOS Apple Silicon.
They evaluate Home Manager modules, inspect native configuration output, and
exercise existing-file migration, repeated activation, updates, and cleanup
without building or launching emulators. They do not test physical controllers,
game compatibility, or GUI behavior on real hardware.

## Automatic updates

### Git source packages

The **Update git packages** workflow runs daily at **06:43 UTC** and can also be
started manually. It discovers packages exposing an `updateScript`, resolves
their upstream branches and hashes the exact commits, including submodules when
requested. Only package manifests change; the nixpkgs pin stays unchanged.
Updates are proposed on `automation/git-packages` and are not auto-merged.
Failed downloads or invalid metadata leave the previous manifest intact.
To update Cemu locally from the repository root:

```sh
nix run .#cemu-git.updateScript
nix flake check --all-systems --no-build
nix build .#cemu-git
```

### Add another git package

The shared scheme is inspired by [Nyx's git packages](https://github.com/chaotic-cx/nyx).
Add a derivation under `pkgs/<name>-git` accepting `src` and `version`, then
generate its first manifest with the common updater:

```sh
nix shell --inputs-from . nixpkgs#git nixpkgs#nix-prefetch-git nixpkgs#python3 -c \
  python3 scripts/update-git-package.py \
  --manifest pkgs/example-git/manifest.json --owner OWNER --repo REPO --ref main
```

Add `--fetch-submodules` if required. Register the package in `flake.nix` using
`shared/git-package.nix`, following the Cemu entry: package path, manifest path,
owner/repository, branch and submodule setting. The helper supplies the pinned
source/version and `updateScript`; the workflow discovers it automatically.
No new flake input, updater script or workflow is needed for each package.

### Eden

The **Update Eden nightly** workflow runs daily at **06:23 UTC** and can also be
started manually. It reads the newest published release's Markdown download
links (the upstream API currently has an empty `assets` list), requires the
complete supported variant matrix, hashes every download without executing it,
and atomically updates `pkgs/eden-nightly-bin/sources.json`. Missing files or
failed downloads leave the previous manifest unchanged. Updates are proposed
on one reusable branch, `automation/eden-nightly`; they are not auto-merged.

### Update locally and verify

```sh
python3 scripts/update-eden-nightly.py
# Re-download and rehash even when the release tag is unchanged:
python3 scripts/update-eden-nightly.py --force

nix flake check --all-systems --no-build
nix eval --json .#packages --apply \
  'builtins.mapAttrs (_: builtins.mapAttrs (_: package: package.drvPath))'
nix build .#eden-nightly-bin .#eden-nightly-bin-zen2-pgo
```

CI builds the native packages on Linux x86_64/aarch64 and macOS Apple Silicon.
Building a package does not verify game compatibility, GPU behavior, or optimized
CPU variants on their target hardware.

Eden is GPL-3.0-or-later. Its packages redistribute upstream binaries, not
source builds; their performance and compatibility follow upstream's artifacts.
Cemu is MPL-2.0 and is built from source.
