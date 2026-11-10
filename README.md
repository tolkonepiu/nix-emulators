# nix-emulators

A collection of emulator packages for Nix: prebuilt
[Eden nightly](https://git.eden-emu.dev/eden-ci/nightly/releases) binaries and
[Cemu](https://github.com/cemu-project/Cemu) built from a pinned commit of `main`.
Downloads and source trees are content-hash pinned, never unpinned `latest` builds.

## Cemu git

`cemu-git` builds upstream `main` from source for Linux (x86_64 and aarch64) and
macOS (Apple Silicon). The commit and recursive submodules are pinned
by the `cemu-src` input in `flake.lock`; building does not silently update them.
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
Eden remains the default. Intel macOS is not supported by the pinned nixpkgs.
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
binary. Intel Macs are not supported. Upstream labels macOS builds experimental
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

## Automatic updates

### Cemu

The **Update Cemu git** workflow runs daily at **06:43 UTC** and can also be
started manually. It runs `nix flake update cemu-src`, leaving the nixpkgs pin
unchanged, and proposes the `flake.lock` change on `automation/cemu-git`.
Updates are not auto-merged. To update locally:

```sh
nix flake update cemu-src
nix flake check --all-systems --no-build
nix build .#cemu-git
```

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

python3 -m unittest discover -s tests -v
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
