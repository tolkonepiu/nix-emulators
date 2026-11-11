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
            "pkgs/source-only/manifest.json": self.manifest,
            "pkgs/dotnet-one/manifest.json": self.manifest,
            "pkgs/dotnet-one/deps.json": [{
                "pname": "Avalonia", "version": "12.1.1", "hash": "sha256-example",
                "url": "https://example.org/avalonia.nupkg",
            }],
        }
        self.write_fixtures(self.files)

    def write_fixtures(self, files):
        for relative, value in files.items():
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

    def test_second_nuget_package_is_discovered(self):
        additional = {
            "pkgs/independent-two/manifest.json": self.manifest,
            "pkgs/independent-two/deps.json": [{
                "pname": "Another.Dependency", "version": "2.0", "hash": "sha256-other",
            }],
        }
        self.write_fixtures(additional)
        updater.apply_updates(self.artifact, self.root)
        for relative, value in (self.files | additional).items():
            self.assertEqual(json.loads((self.root / relative).read_text()), value)

    def test_no_nuget_dependencies(self):
        relative = "pkgs/dotnet-one/deps.json"
        for base in (self.root, self.artifact):
            (base / relative).unlink()
        updater.apply_updates(self.artifact, self.root)
        for relative, value in self.files.items():
            if relative.endswith("manifest.json"):
                self.assertEqual(json.loads((self.root / relative).read_text()), value)
        self.assertFalse((self.root / "pkgs/dotnet-one/deps.json").exists())

    def test_unexpected_paths(self):
        for relative in ("script.py", "pkgs/other/manifest.json", ".git/config"):
            with self.subTest(relative=relative):
                path = self.artifact / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("{}")
                self.assert_rejected()
                path.unlink()

    def test_symlink_file(self):
        path = self.artifact / "pkgs/dotnet-one/deps.json"
        path.unlink()
        path.symlink_to(self.root / "pkgs/dotnet-one/deps.json")
        self.assert_rejected()

    def test_symlink_directory(self):
        (self.artifact / "escape").symlink_to(self.root, target_is_directory=True)
        self.assert_rejected()

    def test_nonregular_file(self):
        import os
        path = self.artifact / "pkgs/dotnet-one/deps.json"
        path.unlink()
        os.mkfifo(path)
        self.assert_rejected()

    def test_invalid_json_and_shapes(self):
        for relative, contents in (
            ("pkgs/dotnet-one/deps.json", "{"),
            ("pkgs/dotnet-one/deps.json", "{}"),
            ("pkgs/dotnet-one/deps.json", '[{"pname":"x"}]'),
            ("pkgs/dotnet-one/deps.json", '[{"pname":"x","version":1,"hash":"x"}]'),
            ("pkgs/dotnet-one/deps.json", '[{"pname":"x","version":"1","hash":"x","url":false}]'),
            ("pkgs/dotnet-one/manifest.json", "[]"),
            ("pkgs/dotnet-one/manifest.json", '{"version":"1"}'),
        ):
            with self.subTest(relative=relative, contents=contents):
                path = self.artifact / relative
                path.write_text(contents)
                self.assert_rejected()
                path.write_text(json.dumps(self.files[relative]))

    def test_missing_expected_dependencies(self):
        (self.artifact / "pkgs/dotnet-one/deps.json").unlink()
        self.assert_rejected()

    def test_size_limit(self):
        (self.artifact / "pkgs/dotnet-one/deps.json").write_bytes(b" " * (updater.MAX_FILE_SIZE + 1))
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
