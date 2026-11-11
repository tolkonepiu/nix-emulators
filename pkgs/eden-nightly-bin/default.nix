{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  runCommand,
  dwarfs,
  undmg,
  makeWrapper,
  version,
  tag,
  source,
  variant ? "standard",
}:
let
  pname = "eden-nightly-bin" + lib.optionalString (variant != "standard") "-${variant}";
  src = fetchurl {
    inherit (source) url hash;
  };
  meta = {
    description = "Eden Switch emulator nightly (${variant} binary)";
    homepage = "https://eden-emu.dev/";
    changelog = "https://git.eden-emu.dev/eden-ci/nightly/releases/tag/${tag}";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "eden";
    platforms = [ stdenvNoCC.hostPlatform.system ];
  };
in
if stdenvNoCC.hostPlatform.isLinux then
  let
    dwarfsWithCloseCleanup = dwarfs.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./dwarfs-close-error-cleanup.patch ];
    });
    # Upstream uses DwarFS, which appimageTools.extractType2 cannot unpack.
    contents = runCommand "${pname}-${version}-extracted" {
      nativeBuildInputs = [ dwarfsWithCloseCleanup ];
    } ''
      mkdir -p "$out"
      set -o pipefail
      dwarfsextract --input ${src} --output "$out" --image-offset auto 2>&1 \
        | sed -u -E "/^W [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6} Can't set user=0\/group=0 for /d"
      test -x "$out/AppRun"
      test -f "$out/dev.eden_emu.eden.desktop"
    '';
  in
  appimageTools.wrapAppImage {
    inherit pname version src contents meta;
    extraPkgs = pkgs: [ pkgs.gamemode ];
    extraInstallCommands = ''
      mv "$out/bin/${pname}" "$out/bin/eden"
      install -Dm644 ${contents}/dev.eden_emu.eden.desktop \
        "$out/share/applications/dev.eden_emu.eden.desktop"
      substituteInPlace "$out/share/applications/dev.eden_emu.eden.desktop" \
        --replace-fail 'Exec=eden %f' "Exec=$out/bin/eden %f" \
        --replace-fail 'TryExec=eden' "TryExec=$out/bin/eden"
      install -Dm644 ${contents}/dev.eden_emu.eden.svg \
        "$out/share/icons/hicolor/scalable/apps/dev.eden_emu.eden.svg"
    '';
  }
else
  stdenvNoCC.mkDerivation {
    inherit pname version src meta;
    nativeBuildInputs = [ undmg makeWrapper ];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      app=$(find . -type d -name eden.app -print -quit)
      test -n "$app"
      test -x "$app/Contents/MacOS/eden"
      mkdir -p "$out/Applications" "$out/bin"
      cp -R "$app" "$out/Applications/eden.app"
      makeWrapper "$out/Applications/eden.app/Contents/MacOS/eden" "$out/bin/eden"
      runHook postInstall
    '';
  }
