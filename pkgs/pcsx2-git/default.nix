{
  pcsx2,
  src,
  version,
}:
pcsx2.overrideAttrs {
  pname = "pcsx2-git";
  inherit src version;

  postPatch = ''
    substituteInPlace cmake/Pcsx2Utils.cmake \
      --replace-fail 'set(PCSX2_GIT_TAG "")' 'set(PCSX2_GIT_TAG "git-${src.shortRev}")' \
      --replace-fail 'set(PCSX2_GIT_REV "")' 'set(PCSX2_GIT_REV "git-${src.shortRev}")' \
      --replace-fail 'set(PCSX2_GIT_HASH "")' 'set(PCSX2_GIT_HASH "${src.rev}")'
  '';
}
