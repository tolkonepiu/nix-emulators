{ lib, stdenv, ryubing, buildDotnetModule, dotnetCorePackages, SDL2, sdl3, runCommand, jq, src, version }:
(ryubing.override {
  buildDotnetModule = args: buildDotnetModule (args // {
    dotnet-sdk = dotnetCorePackages.sdk_10_0;
    dotnet-runtime = dotnetCorePackages.runtime_10_0;
    nugetDeps = ./deps.json;
    runtimeDeps = lib.subtractLists [ SDL2 ] args.runtimeDeps ++ [ sdl3 ];
  });
}).overrideAttrs (finalAttrs: old: {
  pname = "ryubing-git";
  inherit src version;
  patches = (old.patches or [ ]) ++ [ ./dump-default-config.patch ];
  # MSBuild imports Nix's unstable version from the environment during restore.
  dotnetFlags = old.dotnetFlags ++ [ "-p:Version=0.0.0" ];
  versionForDotnet = "0.0.0";
  # Use the git source's renamed desktop entry and PNG icon.
  preFixup = builtins.replaceStrings [
    "${old.src}" "Ryujinx.desktop" "../misc/Logo.svg"
    "icons/hicolor/scalable" "apps/Ryujinx.svg"
  ] [
    "${src}" "app.ryujinx.Ryujinx.desktop" "../misc/Logo.png"
    "icons/hicolor/256x256" "apps/app.ryujinx.Ryujinx.png"
  ] old.preFixup;
  meta = old.meta // {
    changelog = "https://git.ryujinx.app/projects/Ryubing/commits/commit/${src.rev}";
  };
  passthru = (old.passthru or { }) // {
    tests = (old.passthru.tests or { }) // {
      dump-default-config = runCommand "ryubing-default-config-test" {
        nativeBuildInputs = [ jq ];
      } ''
        export HOME="$TMPDIR/home"
        mkdir "$HOME"
        unset DISPLAY WAYLAND_DISPLAY
        ${lib.getExe finalAttrs.finalPackage} --dump-default-config "$TMPDIR/first.json"
        ${lib.getExe finalAttrs.finalPackage} --dump-default-config "$TMPDIR/second.json"
        cmp "$TMPDIR/first.json" "$TMPDIR/second.json"
        jq -e '
          (.version | type == "number") and (.version > 0) and
          (.graphics_backend == "${if stdenv.hostPlatform.isDarwin then "Vulkan" else "OpenGl"}") and
          (.preferred_gpu == "") and (.game_dirs == []) and (.autoload_dirs == []) and
          (.input_config | length > 0)
        ' "$TMPDIR/first.json"
        test -z "$(find "$HOME" -mindepth 1 -print -quit)"
        cp "$TMPDIR/first.json" "$out"
      '';
    };
  };
} // lib.optionalAttrs (stdenv.hostPlatform.system == "aarch64-linux") {
  # Parallel NUnit workers segfault the ARM test host; keep the full suite serial.
  dotnetTestFlags = (old.dotnetTestFlags or [ ]) ++ [ "--" "NUnit.NumberOfTestWorkers=0" ];
})
