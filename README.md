# nix-emulators

A collection of emulator packages for Nix. Currently provides prebuilt
[Eden nightly](https://git.eden-emu.dev/eden-ci/nightly/releases) binaries,
pinned to a release URL and SHA-256 hash rather than a moving `latest` download.

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
The default is the standard build for the selected system.

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

CI builds all native variants on Linux x86_64 and macOS Apple Silicon. Linux
aarch64 derivations are evaluated, but need an aarch64 builder for native build
and runtime coverage. Building a package does not verify game compatibility,
GPU behavior, or optimized CPU variants on their target hardware.

Eden is GPL-3.0-or-later. These packages redistribute upstream binaries, not
source builds; their performance and compatibility follow upstream's artifacts.
