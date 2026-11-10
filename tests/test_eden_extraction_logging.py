import os
from pathlib import Path
import subprocess
import unittest


class EdenExtractionLoggingTests(unittest.TestCase):
    def test_filter_preserves_diagnostics_and_extractor_status(self):
        source = (Path(__file__).resolve().parents[1] / "pkgs/eden-nightly-bin/default.nix").read_text()
        start = source.index("      set -o pipefail\n")
        script = source[start:source.index('      test -x "$out/AppRun"', start)]
        ownership = "W 12:34:56.123456 Can't set user=0/group=0 for /image/file"
        retained = [
            "ordinary stdout",
            "W 12:34:56.123456 Can't set user=1000/group=0 for /image/file",
            "W 12:34:56.123456 Can't set user=0/group=1000 for /image/file",
            "W 12:34:56.123456 Different warning",
            "E 12:34:56.123456 Can't set user=0/group=0 for /image/file",
            "E 12:34:56.123456 Integrity check failed",
            "prefix " + ownership,
            "W not-a-timestamp Can't set user=0/group=0 for /image/file",
        ]
        emitter = '''dwarfsextract() {
          printf '%s\\n' "$FAKE_STDOUT"
          printf '%s\\n' "$FAKE_STDERR" >&2
          return "$FAKE_STATUS"
        }
        '''
        for status in (0, 37):
            with self.subTest(status=status):
                result = subprocess.run(
                    ["bash"], input=emitter + script, text=True, capture_output=True,
                    env={**os.environ, "src": "fake", "out": "unused", "FAKE_STATUS": str(status),
                         "FAKE_STDOUT": retained[0],
                         "FAKE_STDERR": "\n".join([ownership, *retained[1:], ownership])},
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout.splitlines(), retained)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
