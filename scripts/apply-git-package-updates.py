#!/usr/bin/env python3
"""Validate generated JSON pins before applying them to a trusted checkout."""

import argparse
import json
from pathlib import Path
import stat


MAX_FILE_SIZE = 2 * 1024 * 1024
MANIFEST_KEYS = {"version", "rev", "hash", "lastModifiedDate"}
DEPENDENCY_KEYS = {"pname", "version", "hash"}


def string_fields(value, required, optional=frozenset()):
    return (
        isinstance(value, dict)
        and required <= value.keys() <= required | optional
        and all(isinstance(field, str) and field for field in value.values())
    )


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
        valid = (
            string_fields(value, MANIFEST_KEYS)
            if relative.name == "manifest.json"
            else isinstance(value, list) and all(
                string_fields(item, DEPENDENCY_KEYS, {"url"}) for item in value
            )
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
