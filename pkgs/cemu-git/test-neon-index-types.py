"""Compile actual patched NEON converters and check every lane plus scalar tails."""

import os
import pathlib
import shlex
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]).read_text()
with tempfile.TemporaryDirectory() as temp:
    directory = pathlib.Path(temp)
    path = directory / "src/Cafe/HW/Latte/Core/LatteIndices.cpp"
    path.parent.mkdir(parents=True)
    path.write_text(source)
    patch = pathlib.Path(__file__).with_name("neon-index-types.patch")
    subprocess.run(["patch", "--fuzz=0", "-p1", "-d", temp, "-i", str(patch.resolve())], check=True)
    patched = path.read_text()
    start = patched.index("void LatteIndices_fastConvertU16_NEON(")
    functions = patched[start:patched.index("#endif", start)]
    harness = r"""
#include <arm_neon.h>
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <limits>
using uint16 = uint16_t;
using uint32 = uint32_t;
using sint32 = int32_t;
uint16 _swapEndianU16(uint16 x) { return __builtin_bswap16(x); }
uint32 _swapEndianU32(uint32 x) { return __builtin_bswap32(x); }
""" + functions + r"""
template<class T, class Convert, class Swap>
void check(Convert convert, Swap swap) {
    for (uint32 count = 0; count <= 65; ++count) {
        for (uint32 initial : {0u, 0xffffffffu}) {
            std::array<T, 68> input{}, output{}, expected{};
            output.fill(T(0x5a));
            expected = output;
            for (uint32 i = 0; i < input.size(); ++i)
                input[i] = T((i * 0x12345679u) ^ 0x80ff017fu);
            input[2] = 0;
            input[3] = std::numeric_limits<T>::max();
            uint32 actualMax = initial, expectedMax = initial;
            for (uint32 i = 0; i < count; ++i) {
                expected[i + 1] = swap(input[i + 1]);
                expectedMax = std::max(expectedMax, uint32(expected[i + 1]));
            }
            convert(input.data() + 1, output.data() + 1, count, actualMax);
            assert(std::memcmp(output.data(), expected.data(), sizeof(output)) == 0);
            assert(actualMax == expectedMax);
        }
    }
}
int main() {
    check<uint16>(LatteIndices_fastConvertU16_NEON, _swapEndianU16);
    check<uint32>(LatteIndices_fastConvertU32_NEON, _swapEndianU32);
}
"""
    cpp = directory / "test.cpp"
    cpp.write_text(harness)
    binary = directory / "test"
    compiler = shlex.split(os.environ.get("CXX", "c++"))
    subprocess.run(compiler + ["-std=c++20", "-O2", str(cpp), "-o", str(binary)], check=True)
    subprocess.run(shlex.split(os.environ.get("RUNNER", "")) + [str(binary)], check=True)
    print("NEON U16/U32: counts 0..65, unaligned vectors, lane bytes, tails, guards and indexMax passed")
