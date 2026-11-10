import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "updater", Path(__file__).resolve().parents[1] / "scripts/update-eden-nightly.py"
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)
TAG = "v1794272405.6a767ac43a"
BASE = f"https://nightly.eden-emu.dev/{TAG}/"


def release():
    filenames = [
        f"Eden-Linux-6a767ac43a-{target}-{compiler}.AppImage"
        for target in ("amd64", "steamdeck", "rog-ally", "aarch64")
        for compiler in ("gcc-standard", "clang-pgo")
    ] + ["Eden-macOS-6a767ac43a.dmg"]
    return {
        "tag_name": TAG, "draft": False, "prerelease": False, "assets": [],
        "body": "\n".join(f"[download]({BASE}{name})" for name in filenames),
    }


class UpdaterTests(unittest.TestCase):
    def test_mapping(self):
        links = updater.release_links(release())
        self.assertEqual({system: set(variants) for system, variants in links.items()}, {
            "x86_64-linux": {"standard", "pgo", "zen2", "zen2-pgo", "zen4", "zen4-pgo"},
            "aarch64-linux": {"standard", "pgo"}, "aarch64-darwin": {"standard"},
        })
        self.assertTrue(links["x86_64-linux"]["zen2-pgo"].endswith("steamdeck-clang-pgo.AppImage"))
        self.assertTrue(links["x86_64-linux"]["zen4"].endswith("rog-ally-gcc-standard.AppImage"))

    def test_invalid_links(self):
        body = release()["body"]
        for invalid in (
            "\n".join(body.splitlines()[:-1]),
            body + "\n" + body.splitlines()[0],
            body.replace("https://nightly.eden-emu.dev", "https://evil.example", 1),
            body.replace("https://", "http://", 1),
            body.replace(TAG, "v123.6a767ac43a", 1),
            body.replace("gcc-standard.AppImage)", "gcc-standard.AppImage?x=1)", 1),
            body.replace("6a767ac43a-amd64", "0000000000-amd64", 1),
        ):
            with self.subTest(body=invalid), self.assertRaises(ValueError):
                updater.release_links(dict(release(), body=invalid))

    def test_unpublished_release(self):
        for changes in ({"draft": True}, {"prerelease": True}, {"tag_name": "bad"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                updater.release_links(dict(release(), **changes))

    def test_streamed_hash(self):
        response = io.BytesIO(b"artifact bytes")
        response.geturl = lambda: BASE + "artifact"
        response.headers = {"Content-Length": "14"}
        with patch.object(updater.urllib.request, "build_opener") as opener:
            opener.return_value.open.return_value = response
            self.assertEqual(updater.download_hash(BASE + "artifact"), "sha256-" + base64.b64encode(
                hashlib.sha256(b"artifact bytes").digest()).decode())

    def test_incomplete_download(self):
        for content in (b"", b"partial"):
            response = io.BytesIO(content)
            response.geturl = lambda: BASE + "artifact"
            response.headers = {"Content-Length": "100"}
            with patch.object(updater.urllib.request, "build_opener") as opener:
                opener.return_value.open.return_value = response
                with self.assertRaises(ValueError):
                    updater.download_hash(BASE + "artifact")

    def test_redirect_rejects_untrusted_host(self):
        with self.assertRaises(ValueError):
            updater.TrustedRedirects().redirect_request(None, None, 302, "", {}, "https://evil.example/a")

    def run_update(self, path, **kwargs):
        with patch.object(updater.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps([release()]).encode())):
            return updater.update(path, **kwargs)

    def test_noop_and_force(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sources.json"
            original = json.dumps({"tag": TAG})
            path.write_text(original)
            with patch.object(updater, "download_hash", return_value="sha256-test") as hash_download:
                self.assertFalse(self.run_update(path))
                hash_download.assert_not_called()
                self.assertEqual(path.read_text(), original)
                self.assertTrue(self.run_update(path, force=True))
                self.assertEqual(hash_download.call_count, 9)
            manifest = json.loads(path.read_text())
            self.assertEqual(manifest["version"], TAG[1:])
            self.assertEqual(manifest["sources"]["aarch64-darwin"]["standard"], {
                "url": BASE + "Eden-macOS-6a767ac43a.dmg", "hash": "sha256-test",
            })

    def test_failure_preserves_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sources.json"
            original = '{"tag": "old"}\n'
            path.write_text(original)
            with patch.object(updater, "download_hash", side_effect=["sha256-first", OSError("offline")]):
                with self.assertRaises(OSError):
                    self.run_update(path)
            self.assertEqual(path.read_text(), original)
            self.assertEqual(list(path.parent.iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
