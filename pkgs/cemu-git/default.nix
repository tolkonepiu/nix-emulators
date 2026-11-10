{
  lib,
  stdenv,
  src,
  version,
  cmake,
  ninja,
  pkg-config,
  nasm,
  boost,
  cubeb,
  curl,
  fmt_12,
  glm,
  glslang,
  hidapi,
  libpng,
  libusb1,
  libzip,
  openssl,
  pugixml,
  rapidjson,
  sdl3,
  spirv-tools,
  wxwidgets_3_3,
  zarchive,
  zlib,
  zstd,
  bluez,
  gamemode,
  gtk3,
  libglvnd,
  libx11,
  libxrender,
  vulkan-loader,
  wayland,
  wayland-protocols,
  wayland-scanner,
  wrapGAppsHook3,
  moltenvk,
}:

stdenv.mkDerivation {
  pname = "cemu-git";
  inherit src version;

  nativeBuildInputs = [ cmake ninja pkg-config wxwidgets_3_3 ]
    ++ lib.optional stdenv.hostPlatform.isx86_64 nasm
    ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapGAppsHook3 wayland-scanner ];
  buildInputs = [
    boost cubeb curl fmt_12 glm glslang hidapi libpng libusb1 libzip openssl
    pugixml rapidjson sdl3 spirv-tools wxwidgets_3_3 zarchive zlib zstd
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    bluez gamemode gtk3 libglvnd libx11 libxrender vulkan-loader wayland wayland-protocols
  ] ++ lib.optional stdenv.hostPlatform.isDarwin moltenvk;

  strictDeps = true;

  patches = lib.optionals stdenv.hostPlatform.isDarwin [ ./static-registry-lifetime.patch ];

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

  cmakeFlags = [
    (lib.cmakeBool "ENABLE_VCPKG" false)
    (lib.cmakeBool "ALLOW_PORTABLE" false)
    (lib.cmakeBool "MACOS_BUNDLE" stdenv.hostPlatform.isDarwin)
    (lib.cmakeFeature "EMULATOR_VERSION_PATCH" (builtins.substring 0 8 src.lastModifiedDate))
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin (lib.concatMap (language: [
    # Clang IPO searches for llvm-ar/ranlib, but Darwin stdenv provides LTO-capable ar/ranlib.
    (lib.cmakeFeature "CMAKE_${language}_COMPILER_AR" "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}ar")
    (lib.cmakeFeature "CMAKE_${language}_COMPILER_RANLIB" "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}ranlib")
  ]) [ "C" "CXX" "OBJC" "OBJCXX" ]);

  installPhase = ''
    runHook preInstall
  '' + (if stdenv.hostPlatform.isDarwin then ''
    mkdir -p "$out/Applications" "$out/bin"
    cp -R ../bin/Cemu_release.app "$out/Applications/Cemu.app"
    ln -s "$out/Applications/Cemu.app/Contents/MacOS/Cemu_release" "$out/bin/cemu"
  '' else ''
    install -Dm755 ../bin/Cemu_release "$out/bin/Cemu"
    ln -s Cemu "$out/bin/cemu"
    mkdir -p "$out/share/Cemu" "$out/share/applications"
    cp -R ../bin/gameProfiles ../bin/resources "$out/share/Cemu/"
    substitute ../dist/linux/info.cemu.Cemu.desktop "$out/share/applications/info.cemu.Cemu.desktop" \
      --replace-fail 'Exec=Cemu' "Exec=$out/bin/cemu"
    install -Dm644 ../dist/linux/info.cemu.Cemu.metainfo.xml -t "$out/share/metainfo"
    install -Dm644 ../src/resource/logo_icon.png "$out/share/icons/hicolor/128x128/apps/info.cemu.Cemu.png"
  '') + ''
    runHook postInstall
  '';

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ vulkan-loader libglvnd ]}")
  '';

  meta = {
    description = "Wii U emulator built from upstream main";
    homepage = "https://github.com/cemu-project/Cemu";
    license = lib.licenses.mpl20;
    mainProgram = "cemu";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  };
}
