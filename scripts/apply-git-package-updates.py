#!/usr/bin/env python3
"""Validate generated source and dependency data before applying it to a trusted checkout."""

import argparse
import base64
import binascii
import json
from pathlib import Path
import stat
from urllib.parse import urlsplit


MAX_FILE_SIZE = 2 * 1024 * 1024
MANIFEST_KEYS = {"version", "rev", "hash", "lastModifiedDate"}
DEPENDENCY_KEYS = {"pname", "version", "hash"}


def string_fields(value, required, optional=frozenset()):
    return (
        isinstance(value, dict)
        and required <= value.keys() <= required | optional
        and all(isinstance(field, str) and field for field in value.values())
    )


def dependency_source(value):
    if not string_fields(value, {"url", "hash"}):
        return False
    url = value["url"]
    try:
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https" or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.port == 0
            or any(character.isspace() or ord(character) < 32 or character == "\\" for character in url)
        ):
            return False
        if not value["hash"].startswith("sha256-"):
            return False
        digest = base64.b64decode(value["hash"][7:], validate=True)
        return len(digest) == 32 and value["hash"] == "sha256-" + base64.b64encode(digest).decode("ascii")
    except (ValueError, binascii.Error):
        return False


def apply_updates(artifact, root="."):
    artifact, root = Path(artifact), Path(root)
    allowed = {
        path.relative_to(root)
        for pattern in ("pkgs/*/manifest.json", "pkgs/*/deps.json")
        for path in root.glob(pattern)
    }
    directories = {parent for path in allowed for parent in path.parents if parent != Path(".")}
    if not stat.S_ISDIR(artifact.lstat().st_mode):
        raise ValueError("Artifact must be a real directory")
    updates = {}
    for path in artifact.rglob("*"):
        relative = path.relative_to(artifact)
        metadata = path.lstat()
        if stat.S_ISDIR(metadata.st_mode) and relative in directories:
            continue
        if relative not in allowed or not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"Unexpected artifact entry: {relative}")
        if metadata.st_size > MAX_FILE_SIZE:
            raise ValueError(f"Artifact file too large: {relative}")
        content = path.read_bytes()
        value = json.loads(content)
        if relative.name == "manifest.json":
            valid = string_fields(value, MANIFEST_KEYS)
        elif type(value) is not type(json.loads((root / relative).read_bytes())):
            valid = False
        elif isinstance(value, list):
            valid = all(
                string_fields(item, DEPENDENCY_KEYS, {"url"}) for item in value
            )
        else:
            valid = isinstance(value, dict) and bool(value) and all(
                dependency_source(source) for source in value.values()
            )
        if not valid:
            raise ValueError(f"Invalid JSON schema: {relative}")
        updates[relative] = content
    if updates.keys() != allowed:
        raise ValueError("Artifact does not contain the exact expected files")
    # Validate the entire artifact before changing any checkout files.
    for relative, content in updates.items():
        (root / relative).write_bytes(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    apply_updates(args.artifact)
