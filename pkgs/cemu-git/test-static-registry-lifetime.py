"""Check the actual registry declarations after cross-TU-style static teardown."""

import pathlib
import subprocess
import sys
import tempfile


def check(source, fixed, directory):
    declarations = source[source.index("namespace\n"):source.index("CafeStaticVarBase::")]
    heap = "GetStaticDataRegistry().heap" if fixed else "s_iosuStaticDataHeap"
    blocks = "GetStaticDataRegistry().blocks" if fixed else "s_iosuStaticDataBlocks"
    mutex = "GetStaticDataRegistry().mutex" if fixed else "s_cafeStaticDataMutex"
    harness = f"""
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <set>
using uint32 = uint32_t;
using uint64 = uint64_t;
#define cemu_assert_debug assert
class CafeStaticData;
struct VHeap {{ int marker = 42; }};
void checkAtExit();
// Register first, as a different TU's static destructor can precede the registry.
const int registered = (std::atexit(checkAtExit), 0);
{declarations}
void checkAtExit() {{
    assert({heap} && {heap}->marker == 42);
    std::unique_lock lock({mutex});
    assert({blocks}.erase(nullptr) == 1);
}}
int main() {{
    {heap} = std::make_unique<VHeap>();
    {blocks}.insert(nullptr);
}}
"""
    cpp = directory / ("fixed.cpp" if fixed else "original.cpp")
    binary = cpp.with_suffix("")
    cpp.write_text(harness)
    subprocess.run(["c++", "-std=c++20", str(cpp), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True)
    assert (result.returncode == 0) == fixed, result.stderr.decode()
    print(f"{'fixed' if fixed else 'original'} teardown exit={result.returncode}")


original = pathlib.Path(sys.argv[1]).read_text()
with tempfile.TemporaryDirectory() as temp:
    directory = pathlib.Path(temp)
    source = directory / "src/Common/CafeStaticVar.cpp"
    source.parent.mkdir(parents=True)
    source.write_text(original)
    patch = pathlib.Path(__file__).with_name("static-registry-lifetime.patch")
    subprocess.run(["patch", "--fuzz=0", "-p1", "-d", temp, "-i", str(patch.resolve())], check=True)
    check(original, False, directory)
    check(source.read_text(), True, directory)
