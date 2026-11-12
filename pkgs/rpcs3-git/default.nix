{
  lib,
  stdenv,
  darwinMinVersionHook,
  moltenvk,
  vulkan-loader,
  rpcs3,
  src,
  version,
}:
let
  base =
    if stdenv.hostPlatform.isDarwin then
      rpcs3.override {
        waylandSupport = false;
        libevdev = null;
        libsm = null;
        wrapGAppsHook3 = null;
      }
    else
      rpcs3;
in
base.overrideAttrs (old: {
  pname = "rpcs3-git";
  inherit src version;
} // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
  nativeBuildInputs = builtins.filter (input: input != null) old.nativeBuildInputs;
  buildInputs = builtins.filter (input: input != null) old.buildInputs ++ [
    moltenvk
    (darwinMinVersionHook "14.4")
  ];
  cmakeFlags = old.cmakeFlags ++ [
    (lib.cmakeBool "USE_SYSTEM_MVK" true)
    (lib.cmakeBool "USE_LIBEVDEV" false)
    (lib.cmakeFeature "CMAKE_OSX_ARCHITECTURES" "arm64")
    (lib.cmakeFeature "Vulkan_LIBRARY" "${lib.getLib vulkan-loader}/lib/libvulkan.dylib")
  ];

  # Nix supplies Qt plugins and libraries; do not copy them with macdeployqt.
  postPatch = (old.postPatch or "") + ''
    substituteInPlace rpcs3/CMakeLists.txt \
      --replace-fail 'COMMAND "''${MACDEPLOYQT_EXECUTABLE}" "''${PROJECT_BINARY_DIR}/bin/rpcs3.app" "$<$<CONFIG:Debug,RelWithDebInfo>:-no-strip>"' ""
    substituteInPlace 3rdparty/hidapi/CMakeLists.txt \
      --replace-fail 'hidapi-hidraw' 'hidapi'
    substituteInPlace CMakeLists.txt \
      --replace-fail 'list(APPEND CMAKE_PREFIX_PATH "/opt/homebrew")' "" \
      --replace-fail 'list(APPEND CMAKE_SYSTEM_PREFIX_PATH "/opt/homebrew")' ""
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R bin/rpcs3.app "$out/Applications/"
    makeWrapper "$out/Applications/rpcs3.app/Contents/MacOS/rpcs3" "$out/bin/rpcs3"
    runHook postInstall
  '';
  postInstall = "";
  preFixup = ''
    qtWrapperArgs+=(--set-default VK_DRIVER_FILES "${moltenvk}/share/vulkan/icd.d/MoltenVK_icd.json")
  '';
  meta = old.meta // {
    platforms = old.meta.platforms ++ [ "aarch64-darwin" ];
  };
})
