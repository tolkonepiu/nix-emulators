{
  lib,
  stdenv,
  llvmPackages_21,
  fetchurl,
  src,
  version,
  cmake,
  ninja,
  pkg-config,
  python3,
  autoPatchelfHook,
  wrapGAppsHook3,
  zlib,
  expat,
  lz4,
  curl,
  gtk3,
  libglvnd,
  libx11,
  libxcb,
  libxext,
  libxrandr,
  libxtst,
  libxkbcommon,
  alsa-lib,
  libpulseaudio,
  systemd,
  dbus,
  vulkan-loader,
  wayland,
}:
let
  pins = builtins.fromJSON (builtins.readFile ./auxiliary.json);
  slang = stdenv.mkDerivation {
    pname = "xenia-edge-slang";
    version = "2026.8";
    src = fetchurl pins.slang;
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib zlib libx11 ];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R bin lib "$out/"
      runHook postInstall
    '';
    meta.license = [ lib.licenses.asl20 lib.licenses.llvm-exception ];
    # slangc dlopens Slang's adjacent SPIR-V compiler plugin.
    appendRunpaths = [ "${placeholder "out"}/lib" ];
  };
  linuxLibraries = [
    gtk3 libglvnd libx11 libxcb libxext libxrandr libxtst libxkbcommon
    alsa-lib libpulseaudio systemd dbus vulkan-loader wayland
  ];
in
llvmPackages_21.stdenv.mkDerivation {
  pname = "xenia-edge-git";
  inherit src version;
  __structuredAttrs = true;

  nativeBuildInputs = [ cmake ninja pkg-config python3 wrapGAppsHook3 ];
  buildInputs = [ zlib expat lz4 curl ] ++ linuxLibraries;
  patches = [ ./writable-paths.patch ];

  postPatch = ''
    # Xenia calls Wayland directly, rather than only through GTK.
    echo 'target_link_libraries(xenia-app PRIVATE ${lib.getLib wayland}/lib/libwayland-client.so)' >> src/xenia/app/CMakeLists.txt
    mkdir -p build/data_repos/game-compatibility
    cp assets/game-compatibility/master.json build/data_repos/game-compatibility/
    cp ${fetchurl pins.compatibility} build/data_repos/game-compatibility/compatibility_data.json
  '' + lib.concatMapStrings (name: ''
    mkdir -p build/data_repos/${name}
    tar xf ${fetchurl pins.${name}} --strip-components=1 -C build/data_repos/${name}
  '') [ "game-patches" "x360db" "SDL_GameControllerDB" ];

  preConfigure = ''
    export SLANGC_PATH=${slang}/bin/slangc
    cat > build/version.h <<'EOF'
    #define XE_BUILD_BRANCH "edge"
    #define XE_BUILD_COMMIT "${src.rev}"
    #define XE_BUILD_COMMIT_SHORT "${src.shortRev}"
    #define XE_BUILD_DATE "${src.lastModifiedDate}"
    EOF
  '';

  cmakeFlags = [
    "-GNinja Multi-Config"
    # Bound linker memory as well as compile parallelism on small builders.
    "-DXENIA_ENABLE_LTO=OFF"
    # glibc fortify annotates fread; upstream ignores its result under -Werror.
    "-DCMAKE_CXX_FLAGS=-Wno-error=unused-result"
  ];
  ninjaFlags = [ "-f" "build-Release.ninja" "xenia-app" ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m755 bin/Linux/Release/xenia_edge "$out/bin/xenia-edge"
    mkdir -p "$out/lib"
    cp -P bin/Linux/Release/libSDL3.so* "$out/lib/"
    patchelf --set-rpath "$out/lib:$(patchelf --print-rpath "$out/bin/xenia-edge")" "$out/bin/xenia-edge"
    install -Dm644 ../assets/xenia_edge.desktop "$out/share/applications/xenia-edge.desktop"
    substituteInPlace "$out/share/applications/xenia-edge.desktop" \
      --replace-fail 'Exec=xenia_edge' 'Exec=xenia-edge'
    for size in 16 32 48 64 128 256 512 1024; do
      install -Dm644 ../assets/icon/$size.png "$out/share/icons/hicolor/''${size}x$size/apps/xenia_edge.png"
    done
    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "$out/lib:${lib.makeLibraryPath linuxLibraries}")
  '';

  meta = {
    description = "Xbox 360 emulator built from Xenia Edge";
    homepage = "https://github.com/has207/xenia-edge";
    license = lib.licenses.bsd3;
    mainProgram = "xenia-edge";
    platforms = [ "x86_64-linux" ];
  };
}
