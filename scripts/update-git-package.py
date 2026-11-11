#!/usr/bin/env python3
"""Pin a GitHub branch without executing upstream code."""

import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def run(arguments):
    return subprocess.run(arguments, check=True, stdout=subprocess.PIPE, text=True).stdout


def source_url(owner, repo, ref):
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", owner):
        raise ValueError("Invalid GitHub owner")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", repo) or repo in (".", ".."):
        raise ValueError("Invalid GitHub repository")
    # Let Git validate its own branch syntax, but reject option-like branch names.
    if not ref or ref.startswith("-"):
        raise ValueError("Invalid branch")
    run(["git", "check-ref-format", "refs/heads/" + ref])
    return f"https://github.com/{owner}/{repo}.git"


def manifest_metadata(metadata, rev):
    if not isinstance(metadata, dict) or metadata.get("rev") != rev:
        raise ValueError("Prefetched revision does not match the resolved branch")
    source_hash = metadata.get("hash")
    if not isinstance(source_hash, str) or not source_hash.startswith("sha256-"):
        raise ValueError("Expected an SRI SHA-256 hash")
    digest = base64.b64decode(source_hash[7:], validate=True)
    if len(digest) != 32 or base64.b64encode(digest).decode() != source_hash[7:]:
        raise ValueError("Invalid SRI SHA-256 hash")
    date = metadata.get("date")
    if not isinstance(date, str) or not re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})", date
    ):
        raise ValueError("Expected a timezone-aware commit date")
    # datetime accepts overflowing timezone minutes; strict ISO-8601 does not.
    if date[-1] != "Z" and (int(date[-5:-3]) > 23 or int(date[-2:]) > 59):
        raise ValueError("Invalid commit timezone")
    timestamp = datetime.fromisoformat(date).astimezone(timezone.utc)
    canonical_date = f"{timestamp.year:04d}{timestamp:%m%d%H%M%S}"
    return {
        "version": f"unstable-{canonical_date}-{rev[:7]}",
        "rev": rev,
        "hash": source_hash,
        "lastModifiedDate": canonical_date,
    }


def update(path, owner, repo, ref="main", fetch_submodules=False):
    path = Path(path)
    url = source_url(owner, repo, ref)
    branch = "refs/heads/" + ref
    resolved = run(["git", "ls-remote", "--exit-code", "--refs", url, branch]).splitlines()
    if len(resolved) != 1:
        raise ValueError("Expected exactly one branch revision")
    fields = resolved[0].split("\t")
    if len(fields) != 2 or fields[1] != branch or not re.fullmatch(r"[0-9a-f]{40}", fields[0]):
        raise ValueError("Invalid branch resolution")
    rev = fields[0]
    if path.exists() and json.loads(path.read_text())["rev"] == rev:
        print(f"Already pinned {rev}")
        return False
    command = ["nix-prefetch-git", "--url", url, "--rev", rev]
    if fetch_submodules:
        command.append("--fetch-submodules")
    manifest = manifest_metadata(json.loads(run(command)), rev)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
            temporary = output.name
            json.dump(manifest, output, indent=2)
            output.write("\n")
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Pinned {manifest['version']}")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--ref", default="main")
    parser.add_argument("--fetch-submodules", action="store_true")
    args = parser.parse_args()
    update(args.manifest, args.owner, args.repo, args.ref, args.fetch_submodules)
