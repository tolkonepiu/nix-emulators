{ lib, ryubing, buildDotnetModule, dotnetCorePackages, SDL2, sdl3, src, version }:
(ryubing.override {
  buildDotnetModule = args: buildDotnetModule (args // {
    dotnet-sdk = dotnetCorePackages.sdk_10_0;
    dotnet-runtime = dotnetCorePackages.runtime_10_0;
    nugetDeps = ./deps.json;
    runtimeDeps = lib.subtractLists [ SDL2 ] args.runtimeDeps ++ [ sdl3 ];
  });
}).overrideAttrs (old: {
  pname = "ryubing-git";
  inherit src version;
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
})
