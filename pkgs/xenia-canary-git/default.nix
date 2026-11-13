{
  xenia-canary,
  vulkan-loader,
  src,
  version,
}:
xenia-canary.overrideAttrs (old: {
  pname = "xenia-canary-git";
  inherit src version;

  postPatch = (old.postPatch or "") + ''
    substituteInPlace src/xenia/base/logging.cc \
      --replace-fail 'auto file_path = xe::filesystem::GetExecutableFolder() / file_name;' 'auto file_path = xe::filesystem::GetUserFolder() / "Xenia" / file_name;
        xe::filesystem::CreateParentFolder(file_path);'
    substituteInPlace src/xenia/app/emulator_window.cc \
      --replace-fail 'xe::filesystem::GetExecutableFolder() / "screenshots"' 'emulator()->storage_root() / "screenshots"'
  '';

  # Keep bundled SDL's SONAME links and avoid wrapping it as an executable.
  postInstall = ''
    mkdir -p "$out/lib"
    cp -a build/bin/Linux/Release/libSDL3.so* "$out/lib/"
    rm "$out/bin"/libSDL3.so*
    patchelf --set-rpath "$out/lib:$(patchelf --print-rpath "$out/bin/xenia_canary")" "$out/bin/xenia_canary"
    addAutoPatchelfSearchPath ${vulkan-loader}/lib
  '';

  # SDL optionally dlopens Steam and an alternative GLES1 library name.
  autoPatchelfIgnoreMissingDeps = [ "libsteam_api.so" "libGLES_CM.so.1" ];
})
