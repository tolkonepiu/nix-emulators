import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "apply_git_package_updates",
    Path(__file__).resolve().parents[1] / "scripts/apply-git-package-updates.py",
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class ApplyGitPackageUpdatesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.artifact = Path(self.temporary.name) / "artifact"
        self.manifest = {
            "version": "unstable-20261111004018-4d5a19d",
            "rev": "4d5a19d3311b0980fe91ba17dcce9033f57fd280",
            "hash": "sha256-zn9sbKMJftgZJrbKUHaZhDfEKi/lhURxsoUKXQuhhIA=",
            "lastModifiedDate": "20261111004018",
        }
        self.files = {
            "pkgs/cemu-git/manifest.json": self.manifest,
            "pkgs/ryubing-git/manifest.json": self.manifest,
            "pkgs/ryubing-git/deps.json": [{
                "pname": "Avalonia", "version": "12.1.1", "hash": "sha256-example",
                "url": "https://example.org/avalonia.nupkg",
            }],
        }
        for relative, value in self.files.items():
            for base in (self.root, self.artifact):
                path = base / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(value) if base == self.artifact else "original\n")

    def assert_rejected(self):
        with self.assertRaises((ValueError, UnicodeDecodeError)):
            updater.apply_updates(self.artifact, self.root)
        for relative in self.files:
            self.assertEqual((self.root / relative).read_text(), "original\n")

    def test_allowed_updates_preserve_optional_url(self):
        updater.apply_updates(self.artifact, self.root)
        for relative, value in self.files.items():
            self.assertEqual(json.loads((self.root / relative).read_text()), value)

    def test_unexpected_paths(self):
        for relative in ("script.py", "pkgs/other/manifest.json", ".git/config"):
            with self.subTest(relative=relative):
                path = self.artifact / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("{}")
                self.assert_rejected()
                path.unlink()

    def test_symlink_file(self):
        path = self.artifact / "pkgs/ryubing-git/deps.json"
        path.unlink()
        path.symlink_to(self.root / "pkgs/ryubing-git/deps.json")
        self.assert_rejected()

    def test_symlink_directory(self):
        (self.artifact / "escape").symlink_to(self.root, target_is_directory=True)
        self.assert_rejected()

    def test_nonregular_file(self):
        import os
        path = self.artifact / "pkgs/ryubing-git/deps.json"
        path.unlink()
        os.mkfifo(path)
        self.assert_rejected()

    def test_invalid_json_and_shapes(self):
        for relative, contents in (
            ("pkgs/ryubing-git/deps.json", "{"),
            ("pkgs/ryubing-git/deps.json", "{}"),
            ("pkgs/ryubing-git/deps.json", '[{"pname":"x"}]'),
            ("pkgs/ryubing-git/deps.json", '[{"pname":"x","version":1,"hash":"x"}]'),
            ("pkgs/ryubing-git/deps.json", '[{"pname":"x","version":"1","hash":"x","url":false}]'),
            ("pkgs/ryubing-git/manifest.json", "[]"),
            ("pkgs/ryubing-git/manifest.json", '{"version":"1"}'),
        ):
            with self.subTest(relative=relative, contents=contents):
                path = self.artifact / relative
                path.write_text(contents)
                self.assert_rejected()
                path.write_text(json.dumps(self.files[relative]))

    def test_missing_file(self):
        (self.artifact / "pkgs/ryubing-git/deps.json").unlink()
        self.assert_rejected()

    def test_size_limit(self):
        (self.artifact / "pkgs/ryubing-git/deps.json").write_bytes(b" " * (updater.MAX_FILE_SIZE + 1))
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
