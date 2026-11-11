import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "update_git_package", Path(__file__).resolve().parents[1] / "scripts/update-git-package.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UpdateGitPackageTests(unittest.TestCase):
    def test_source_urls(self):
        self.assertEqual(
            updater.source_url("cemu-project", "Cemu", "main"),
            "https://github.com/cemu-project/Cemu.git",
        )
        self.assertEqual(
            updater.source_url("projects", "Ryubing", "master", "git.ryujinx.app"),
            "https://git.ryujinx.app/projects/Ryubing.git",
        )

    def test_invalid_domains(self):
        for domain in (
            "", "-host", "host-", "user@host", "https://host", "host/path",
            "host?query", "host#fragment", "host:443", "host..com", ".host",
            "host.", "host_name", "host\n", "a" * 64 + ".com",
            ".".join(["a" * 63] * 4),
        ):
            with self.subTest(domain=domain), patch.object(updater, "run") as run:
                with self.assertRaises(ValueError):
                    updater.source_url("projects", "Ryubing", "master", domain)
                run.assert_not_called()

    def test_owner_repo_and_branch_safety(self):
        for owner, repo, ref in (
            ("-owner", "repo", "main"), ("owner/path", "repo", "main"),
            ("owner", "..", "main"), ("owner", "repo/path", "main"),
            ("owner", "repo", ""), ("owner", "repo", "--help"),
            ("owner", "repo", "bad..branch"), ("owner", "repo", "main:other"),
            ("owner", "repo", "main\n"),
        ):
            with self.subTest(owner=owner, repo=repo, ref=ref):
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    updater.source_url(owner, repo, ref)

    def test_update_and_noop(self):
        rev = "4d5a19d3311b0980fe91ba17dcce9033f57fd280"
        metadata = {
            "rev": rev,
            "hash": "sha256-" + "A" * 43 + "=",
            "date": "2026-11-11T10:00:00+02:00",
        }
        for domain in ("github.com", "git.ryujinx.app"):
            with self.subTest(domain=domain), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "manifest.json"
                url = f"https://{domain}/projects/Ryubing.git"
                resolved = f"{rev}\trefs/heads/master\n"
                with patch.object(updater, "run", side_effect=["", resolved, json.dumps(metadata)]) as run:
                    self.assertTrue(updater.update(path, "projects", "Ryubing", "master", True, domain))
                self.assertEqual(run.call_args_list, [
                    unittest.mock.call(["git", "check-ref-format", "refs/heads/master"]),
                    unittest.mock.call(["git", "ls-remote", "--exit-code", "--refs", url, "refs/heads/master"]),
                    unittest.mock.call(["nix-prefetch-git", "--url", url, "--rev", rev, "--fetch-submodules"]),
                ])
                manifest = json.loads(path.read_text())
                self.assertEqual(manifest, {
                    "version": f"unstable-20261111080000-{rev[:7]}",
                    "rev": rev,
                    "hash": metadata["hash"],
                    "lastModifiedDate": "20261111080000",
                })
                original = path.read_bytes()
                with patch.object(updater, "run", side_effect=["", resolved]) as run:
                    self.assertFalse(updater.update(path, "projects", "Ryubing", "master", True, domain))
                self.assertEqual(run.call_count, 2)
                self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
