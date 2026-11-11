import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "managed_files", Path(__file__).resolve().parents[1] / "modules/lib/managed-files.py"
)
managed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(managed)


class ManagedFilesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.write_bytes(b"generated\0bytes")
        self.target = self.root / "config" / "settings.ini"
        self.state = self.root / "state" / "eden.json"
        self.backup = Path(str(self.target) + ".hm-backup")

    def run_activation(self, files=None, **kwargs):
        if files is None:
            files = {str(self.target): str(self.source)}
        managed.activate(files, self.state, **kwargs)

    def existing(self, contents="original"):
        self.target.parent.mkdir()
        self.target.write_text(contents)

    def test_first_adoption_preserves_bytes_and_metadata(self):
        self.existing()
        self.target.chmod(0o640)
        os.utime(self.target, (1000000, 1000000))
        self.run_activation()
        self.assertEqual(self.backup.read_text(), "original")
        self.assertEqual(self.backup.stat().st_mtime, 1000000)
        self.assertEqual(stat.S_IMODE(self.backup.stat().st_mode), 0o640)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        self.assertEqual(json.loads(self.state.read_text()), [str(self.target)])

    def test_same_generation_rewrites_runtime_edits_without_new_backup(self):
        self.run_activation()
        self.target.write_text("GUI edits")
        self.run_activation()
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertFalse(self.backup.exists())

    def test_updated_manifest_and_removed_profile_preserve_siblings(self):
        self.existing()
        sibling = self.target.parent / "unmanaged"
        sibling.write_text("keep")
        directory = self.target.parent / "unmanaged-dir"
        directory.mkdir()
        dangling = self.target.parent / "unmanaged-link"
        dangling.symlink_to("missing")
        self.run_activation()
        self.target.write_text("runtime")
        replacement = self.target.parent / "profile" / "new.ini"
        self.source.write_text("updated")
        self.run_activation({str(replacement): str(self.source)})
        self.assertFalse(self.target.exists())
        self.assertEqual(replacement.read_text(), "updated")
        self.assertEqual(sibling.read_text(), "keep")
        self.assertTrue(directory.is_dir())
        self.assertTrue(dangling.is_symlink())
        self.assertEqual(self.backup.read_text(), "original")
        self.run_activation({})
        self.assertFalse(replacement.exists())
        self.assertEqual(json.loads(self.state.read_text()), [])
        self.assertTrue(replacement.parent.is_dir())

    def test_new_source_at_same_target(self):
        self.run_activation()
        self.source.write_text("new generation")
        self.run_activation()
        self.assertEqual(self.target.read_text(), "new generation")

    def test_symlink_adoption_does_not_write_through(self):
        self.target.parent.mkdir()
        original = self.root / "original"
        original.write_text("original")
        self.target.symlink_to(original)
        self.run_activation()
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(original.read_text(), "original")
        self.assertEqual(self.backup.read_text(), "original")

    def test_conflicting_backup_refuses_takeover_before_any_writes(self):
        self.state.parent.mkdir()
        self.state.write_text("[]")
        other = self.root / "other"
        other.write_text("untouched")
        for kind in ("file", "symlink", "resolved-symlink", "directory", "fifo"):
            with self.subTest(kind=kind):
                self.existing()
                if kind == "file":
                    self.backup.write_text("keep backup")
                elif kind == "symlink":
                    self.backup.symlink_to("missing")
                elif kind == "resolved-symlink":
                    self.backup.symlink_to(self.target)
                elif kind == "directory":
                    self.backup.mkdir()
                else:
                    os.mkfifo(self.backup)
                files = {str(other): str(self.source), str(self.target): str(self.source)}
                for dry_run in (False, True):
                    with self.assertRaisesRegex(ValueError, "move existing backup"):
                        self.run_activation(files, dry_run=dry_run)
                    self.assertEqual(self.target.read_text(), "original")
                    self.assertEqual(other.read_text(), "untouched")
                    self.assertEqual(self.state.read_text(), "[]")
                if kind == "file":
                    self.assertEqual(self.backup.read_text(), "keep backup")
                elif kind in ("symlink", "resolved-symlink"):
                    self.assertTrue(self.backup.is_symlink())
                elif kind == "directory":
                    self.assertTrue(self.backup.is_dir())
                else:
                    self.assertTrue(stat.S_ISFIFO(self.backup.lstat().st_mode))
                if kind == "directory":
                    self.backup.rmdir()
                else:
                    self.backup.unlink()
                self.target.unlink()
                self.target.parent.rmdir()

    def test_identical_existing_backup_allows_takeover_without_changing_backup(self):
        self.existing()
        self.backup.write_bytes(self.target.read_bytes())
        self.backup.chmod(0o640)
        os.utime(self.backup, (1000000, 1000000))
        before = self.backup.stat()
        self.run_activation()
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertEqual(self.backup.read_text(), "original")
        after = self.backup.stat()
        self.assertEqual((after.st_ino, after.st_mode, after.st_mtime),
                         (before.st_ino, before.st_mode, before.st_mtime))

    def test_owned_target_ignores_differing_backup(self):
        self.existing()
        self.run_activation()
        self.target.write_text("runtime edits")
        self.backup.write_text("different backup")
        self.run_activation()
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertEqual(self.backup.read_text(), "different backup")

    def test_backup_creation_race_checks_existing_bytes(self):
        self.existing()
        for contents in ("different backup", "original"):
            with self.subTest(contents=contents):
                def collide(source, destination):
                    Path(destination).write_text(contents)
                    raise FileExistsError(destination)

                with mock.patch.object(managed.os, "link", side_effect=collide):
                    if contents == "original":
                        self.run_activation()
                        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
                    else:
                        with self.assertRaisesRegex(ValueError, "move existing backup"):
                            self.run_activation()
                        self.assertEqual(self.target.read_text(), "original")
                        self.assertFalse(self.state.exists())
                self.assertEqual(self.backup.read_text(), contents)
                self.backup.unlink()
                self.assertEqual(list(self.target.parent.iterdir()), [self.target])

    def test_dry_run_creates_nothing_and_preserves_existing_files(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.run_activation(dry_run=True)
            self.assertFalse(self.target.parent.exists())
            self.assertFalse(self.state.parent.exists())
            self.existing()
            self.run_activation(dry_run=True)
            self.assertEqual(self.target.read_text(), "original")
            self.assertFalse(self.backup.exists())
            self.run_activation()
            before = self.state.read_bytes()
            self.run_activation({}, dry_run=True)
            self.assertTrue(self.target.exists())
            self.assertEqual(self.state.read_bytes(), before)

    def test_unsafe_paths_fail_before_writes(self):
        for unsafe in ("relative", "/", str(self.state), str(self.root / "x/../y"),
                       str(self.target) + ".hm-backup", str(self.state / "child"),
                       str(self.target) + ".hm-backup/child"):
            with self.subTest(unsafe=unsafe):
                files = {str(self.target): str(self.source), unsafe: str(self.source)}
                with self.assertRaises(ValueError):
                    self.run_activation(files)
                self.assertFalse(self.target.parent.exists())
                self.assertFalse(self.state.parent.exists())

    def test_symlink_state_and_invalid_parent_fail_before_writes(self):
        self.state.parent.mkdir()
        other = self.root / "other-state"
        other.write_text("[]")
        self.state.symlink_to(other)
        with self.assertRaises(ValueError):
            self.run_activation()
        self.assertFalse(self.target.parent.exists())
        self.assertEqual(other.read_text(), "[]")
        self.state.unlink()
        self.target.parent.write_text("not a directory")
        with self.assertRaises(ValueError):
            self.run_activation()
        self.assertFalse(self.state.exists())

    def test_invalid_targets_and_sources_preflight_every_file(self):
        bad = self.root / "bad"
        for kind in ("directory", "dangling", "fifo", "missing-source"):
            with self.subTest(kind=kind):
                if kind == "directory":
                    bad.mkdir()
                elif kind == "dangling":
                    bad.symlink_to("missing")
                elif kind == "fifo":
                    os.mkfifo(bad)
                files = {str(self.target): str(self.source), str(bad): str(self.source)}
                if kind == "missing-source":
                    files[str(bad)] = str(self.root / "missing")
                with self.assertRaises(ValueError):
                    self.run_activation(files)
                self.assertFalse(self.target.parent.exists())
                self.assertFalse(self.state.parent.exists())
                if kind == "directory":
                    bad.rmdir()
                elif kind != "missing-source":
                    bad.unlink()

    def test_malformed_state_fails_without_modification(self):
        self.existing()
        self.state.parent.mkdir()
        for value in ("{", "{}", '["relative"]', '["/"]', '[42]',
                      json.dumps([str(self.target), str(self.target)])):
            with self.subTest(value=value):
                self.state.write_text(value)
                with self.assertRaises(ValueError):
                    self.run_activation()
                self.assertEqual(self.target.read_text(), "original")
                self.assertEqual(self.state.read_text(), value)
                self.assertFalse(self.backup.exists())

    def test_owned_directory_or_dangling_link_prevents_cleanup(self):
        self.run_activation()
        self.target.unlink()
        for kind in ("directory", "dangling"):
            with self.subTest(kind=kind):
                if kind == "directory":
                    self.target.mkdir()
                else:
                    self.target.symlink_to("missing")
                before = self.state.read_bytes()
                with self.assertRaises(ValueError):
                    self.run_activation({})
                self.assertEqual(self.state.read_bytes(), before)
                if kind == "directory":
                    self.target.rmdir()
                else:
                    self.target.unlink()


if __name__ == "__main__":
    unittest.main()
