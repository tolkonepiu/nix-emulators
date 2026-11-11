{
  lib,
  stdenv,
  cemu,
  src,
  version,
  fmt_12,
  libusb1,
  openssl,
  sdl3,
  spirv-tools,
  testers,
  wxwidgets_3_3,
  zlib,
  zstd,
  gamemode,
  libglvnd,
  libx11,
  wayland-protocols,
  moltenvk,
}:
let
  # Cemu does not use wxWebView; avoid pulling in WebKitGTK on Linux.
  wxwidgets = if stdenv.hostPlatform.isLinux
    then wxwidgets_3_3.override { withWebKit = false; }
    else wxwidgets_3_3;
in
(cemu.override {
  SDL2 = sdl3;
  fmt_9 = fmt_12;
  wxwidgets_3_2 = wxwidgets;
}).overrideAttrs (finalAttrs: old: {
  pname = "cemu-git";
  inherit src version;

  nativeBuildInputs = lib.filter (input: !(builtins.elem (lib.getName input) (
    lib.optional (!stdenv.hostPlatform.isx86_64) "nasm"
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      "add-driver-runpath-hook" "wrap-gapps-hook" "wayland-scanner"
    ]
  ))) old.nativeBuildInputs;
  buildInputs = lib.filter (input: !(builtins.elem (lib.getName input) (
    [ "imgui" ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      "gtk+3" "libxrender" "wayland" "bluez"
    ]
  ))) old.buildInputs ++ [ openssl spirv-tools zlib zstd ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ gamemode libglvnd libx11 wayland-protocols ]
    ++ lib.optional stdenv.hostPlatform.isDarwin moltenvk;

  patches = lib.optionals stdenv.hostPlatform.isDarwin [ ./static-registry-lifetime.patch ]
    ++ lib.optionals (stdenv.hostPlatform.system == "aarch64-linux") [ ./neon-index-types.patch ];

  postPatch = ''
    # glslang's exported targets reference this target without importing it.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'find_package(glslang REQUIRED)' 'find_package(SPIRV-Tools-opt REQUIRED)
    find_package(glslang REQUIRED)' \
      --replace-fail 'add_definitions(-DEMULATOR_HASH=''${GIT_HASH})' 'add_definitions(-DEMULATOR_HASH=${src.shortRev})'
  '' + lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace src/gui/wxgui/CemuApp.cpp \
      --replace-fail 'data_path = standardPaths.GetDataDir().ToStdString();' 'data_path = "'"$out"'/share/Cemu";'
    substituteInPlace dependencies/gamemode/lib/gamemode_client.h \
      --replace-fail 'libgamemode.so.0' '${lib.getLib gamemode}/lib/libgamemode.so.0'
  '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace src/CMakeLists.txt \
      --replace-fail '/usr/local/lib/libMoltenVK.dylib' '${moltenvk}/lib/libMoltenVK.dylib' \
      --replace-fail '/opt/homebrew/lib/libMoltenVK.dylib' '${moltenvk}/lib/libMoltenVK.dylib' \
      --replace-fail ${lib.escapeShellArg "\${CMAKE_BINARY_DIR}/vcpkg_installed/\${VCPKG_TARGET_TRIPLET}/lib/libusb-1.0.0.dylib"} '${lib.getLib libusb1}/lib/libusb-1.0.0.dylib'
    substituteInPlace src/Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.cpp \
      --replace-fail 'dlopen("libMoltenVK.dylib"' 'dlopen("${moltenvk}/lib/libMoltenVK.dylib"'
  '';

  # Release setup parses a tag version and replaces the bundled imgui; neither fits git.
  preConfigure = "";

  cmakeFlags = lib.subtractLists [
    (lib.cmakeBool "PORTABLE" false)
    (lib.cmakeBool "ENABLE_FERAL_GAMEMODE" true)
  ] old.cmakeFlags ++ [
    (lib.cmakeBool "ENABLE_FERAL_GAMEMODE" stdenv.hostPlatform.isLinux)
    (lib.cmakeBool "ALLOW_PORTABLE" false)
    (lib.cmakeBool "MACOS_BUNDLE" stdenv.hostPlatform.isDarwin)
    (lib.cmakeFeature "EMULATOR_VERSION_PATCH" (builtins.substring 0 8 src.lastModifiedDate))
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin (lib.concatMap (language: [
    # Clang IPO searches for llvm-ar/ranlib, but Darwin stdenv provides LTO-capable ar/ranlib.
    (lib.cmakeFeature "CMAKE_${language}_COMPILER_AR" "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}ar")
    (lib.cmakeFeature "CMAKE_${language}_COMPILER_RANLIB" "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}ranlib")
  ]) [ "C" "CXX" "OBJC" "OBJCXX" ]);

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    mkdir -p "$out/share/Cemu"
    cp -R ../bin/gameProfiles ../bin/resources "$out/share/Cemu/"
  '';

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    ${old.preFixup}
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}")
  '';

  passthru = old.passthru // {
    tests = old.passthru.tests // {
      version = testers.testVersion {
        package = finalAttrs.finalPackage;
        version = src.shortRev;
      };
    };
  };

  meta = old.meta // {
    description = "Wii U emulator built from upstream main";
    homepage = "https://github.com/cemu-project/Cemu";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  };
} // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R ../bin/Cemu_release.app "$out/Applications/Cemu.app"
    ln -s "$out/Applications/Cemu.app/Contents/MacOS/Cemu_release" "$out/bin/cemu"
    runHook postInstall
  '';
})
