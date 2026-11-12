{
  shadps4,
  src,
  version,
}:
shadps4.overrideAttrs (old: {
  pname = "shadps4-git";
  inherit src version;

  prePatch = ''
    printf '%s' '${builtins.substring 0 8 src.rev}' > COMMIT
    date -u -d '${builtins.substring 0 8 src.lastModifiedDate} ${builtins.substring 8 2 src.lastModifiedDate}:${builtins.substring 10 2 src.lastModifiedDate}:${builtins.substring 12 2 src.lastModifiedDate}Z' \
      '+%Y-%m-%dT%H:%M:%SZ' > SOURCE_DATE_EPOCH
  '';

  postPatch = (old.postPatch or "") + ''
    substituteInPlace src/emulator.cpp \
      --replace-fail '#include <fmt/core.h>' '#include <fmt/format.h>'
    sed -i '3i #include <cmath>' src/emulator.cpp

    # glibc 2.42 no longer supplies these declarations transitively.
    find src -type f \( -name '*.cpp' -o -name '*.h' \) \
      -exec grep -qE 'std::mem(cpy|set|cmp|move)|std::str(cat|cmp|cpy|len|ncpy|str|chr|rchr|spn|cspn|pbrk|tok|coll|xfrm|error)' {} \; \
      -exec sh -c 'grep -q "^#include <cstring>" "$1" || sed -i "1i#include <cstring>" "$1"' _ {} \;
  '';
})
