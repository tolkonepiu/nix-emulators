import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "git_updater", Path(__file__).resolve().parents[1] / "scripts/update-git-package.py"
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)
REV = "1234567890abcdef1234567890abcdef12345678"
HASH = "sha256-" + base64.b64encode(bytes(range(32))).decode()
URL = "https://github.com/example/emulator.git"


def metadata():
    return dict(rev=REV, hash=HASH, date="2026-11-10T01:02:03+02:30")


class GitUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "manifest.json"
        self.original = json.dumps({"rev": "a" * 40, "hash": HASH}) + "\n"
        self.path.write_text(self.original)

    def run_update(self, resolved=None, prefetched=None, **kwargs):
        if resolved is None:
            resolved = f"{REV}\trefs/heads/main\n"
        if prefetched is None:
            prefetched = json.dumps(metadata())
        with patch.object(updater, "run", side_effect=["", resolved, prefetched]) as run:
            changed = updater.update(self.path, "example", "emulator", **kwargs)
        return changed, run

    def assert_preserved(self):
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_real_change_uses_exact_revision_and_utc_full_timestamp(self):
        changed, run = self.run_update()
        self.assertTrue(changed)
        self.assertEqual(run.call_args_list[0].args[0], ["git", "check-ref-format", "refs/heads/main"])
        self.assertEqual(run.call_args_list[1].args[0], [
            "git", "ls-remote", "--exit-code", "--refs", URL, "refs/heads/main",
        ])
        self.assertEqual(run.call_args_list[2].args[0], [
            "nix-prefetch-git", "--url", URL, "--rev", REV,
        ])
        self.assertEqual(json.loads(self.path.read_text()), {
            "version": "unstable-20261109223203-1234567", "rev": REV,
            "hash": HASH, "lastModifiedDate": "20261109223203",
        })
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_custom_branch_and_submodules(self):
        changed, run = self.run_update(
            resolved=f"{REV}\trefs/heads/release/next\n", ref="release/next", fetch_submodules=True,
        )
        self.assertTrue(changed)
        self.assertEqual(run.call_args_list[1].args[0][-1], "refs/heads/release/next")
        self.assertEqual(run.call_args_list[2].args[0][-1], "--fetch-submodules")

    def test_bootstrap_missing_manifest(self):
        self.path.unlink()
        changed, run = self.run_update()
        self.assertTrue(changed)
        self.assertEqual(run.call_count, 3)
        self.assertEqual(json.loads(self.path.read_text())["rev"], REV)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_noop_skips_prefetch_and_preserves_bytes(self):
        self.original = json.dumps({"rev": REV}, indent=4)
        self.path.write_text(self.original)
        changed, run = self.run_update()
        self.assertFalse(changed)
        self.assertEqual(run.call_count, 2)
        self.assert_preserved()

    def test_rejects_invalid_branch_resolution(self):
        for resolved in ("", f"{REV}\trefs/tags/main\n", f"{'a' * 39}\trefs/heads/main\n",
                         f"{REV}\trefs/heads/main\n" * 2, f"{REV} refs/heads/main\n"):
            with self.subTest(resolved=resolved), self.assertRaises(ValueError):
                self.run_update(resolved=resolved)
            self.assert_preserved()

    def test_rejects_prefetch_mismatch_or_invalid_metadata(self):
        invalid = [None, [], {}, {**metadata(), "rev": "b" * 40}]
        invalid += [{**metadata(), "hash": value} for value in (
            None, "sha512-abc", "sha256-!", "sha256-YQ==", HASH + "=",
        )]
        invalid += [{**metadata(), "date": value} for value in (
            None, "2026-11-10", "2026-11-10T01:02:03", "2026-02-30T01:02:03Z",
            "2026-11-10T01:02:03+24:00", "2026-11-10T01:02:03+01:60",
            "2026-11-10T25:02:03Z",
        )]
        for data in invalid:
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.run_update(prefetched=json.dumps(data))
            self.assert_preserved()
        with self.assertRaises(json.JSONDecodeError):
            self.run_update(prefetched="not json")
        self.assert_preserved()

    def test_utc_date(self):
        result = updater.manifest_metadata({**metadata(), "date": "2026-01-02T03:04:05Z"}, REV)
        self.assertEqual(result["version"], "unstable-20260102030405-1234567")

    def test_rejects_untrusted_owner_repo_and_ref(self):
        for owner, repo, ref in (("--config", "emulator", "main"), ("bad/name", "emulator", "main"),
                                 ("example", "../evil", "main"), ("example", "..", "main"),
                                 ("example", "repo?query", "main"), ("example", "emulator", "-bad"),
                                 ("example", "emulator", "")):
            with self.subTest(owner=owner, repo=repo, ref=ref), patch.object(updater, "run") as run:
                with self.assertRaises(ValueError):
                    updater.update(self.path, owner, repo, ref)
                run.assert_not_called()
            self.assert_preserved()

    def test_git_rejects_invalid_ref_syntax(self):
        for ref in ("bad..branch", "bad branch", "bad:branch", "bad@{branch", "bad.lock"):
            with self.subTest(ref=ref), self.assertRaises(subprocess.CalledProcessError):
                updater.source_url("example", "emulator", ref)
        self.assert_preserved()

    def test_git_and_prefetch_failure_preserve_manifest(self):
        failure = subprocess.CalledProcessError(1, ["fetch"])
        for results in (["", failure], ["", f"{REV}\trefs/heads/main\n", failure]):
            with self.subTest(results=results), patch.object(updater, "run", side_effect=results):
                with self.assertRaises(subprocess.CalledProcessError):
                    updater.update(self.path, "example", "emulator")
            self.assert_preserved()

    def test_failed_replace_cleans_up_temporary_file(self):
        with patch.object(updater.os, "replace", side_effect=OSError("replace failed")):
            with self.assertRaises(OSError):
                self.run_update()
        self.assert_preserved()

    def test_failed_write_cleans_up_temporary_file(self):
        with patch.object(updater.json, "dump", side_effect=OSError("write failed")):
            with self.assertRaises(OSError):
                self.run_update()
        self.assert_preserved()

    def test_run_uses_argv_without_shell(self):
        with patch.object(updater.subprocess, "run") as run:
            run.return_value.stdout = "output"
            self.assertEqual(updater.run(["git", "--version"]), "output")
        run.assert_called_once_with(["git", "--version"], check=True, stdout=subprocess.PIPE, text=True)


if __name__ == "__main__":
    unittest.main()
