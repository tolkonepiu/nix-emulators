#!/usr/bin/env python3
"""Validate package-local artifact paths before applying additions and updates."""

import argparse
from pathlib import Path
import re
import stat


MAX_FILE_SIZE = 2 * 1024 * 1024
MAX_TOTAL_SIZE = 64 * 1024 * 1024


def validate_destination(root, relative, directory):
    current = root
    for index, part in enumerate(relative.parts):
        current /= part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            break
        want_directory = directory or index < len(relative.parts) - 1
        if want_directory:
            valid = stat.S_ISDIR(metadata.st_mode)
        else:
            valid = stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1
        if not valid:
            raise ValueError(f"Unsafe checkout destination: {relative}")


def apply_updates(artifact, package, root="."):
    artifact, root = Path(artifact), Path(root).resolve()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", package) or package == "default":
        raise ValueError("Invalid selected package")
    selected = Path("pkgs") / package
    validate_destination(root, selected, directory=True)
    if not (root / selected).is_dir():
        raise ValueError(f"No checkout directory for selected package: {package}")
    if not stat.S_ISDIR(artifact.lstat().st_mode):
        raise ValueError("Artifact must be a real directory")
    updates, directories = {}, []
    total_size = 0
    for path in artifact.rglob("*"):
        relative = path.relative_to(artifact)
        metadata = path.lstat()
        directory = stat.S_ISDIR(metadata.st_mode)
        if relative != Path("pkgs") and not relative.is_relative_to(selected):
            raise ValueError(f"Unexpected artifact entry: {relative}")
        if not directory and (not stat.S_ISREG(metadata.st_mode) or relative in (Path("pkgs"), selected)):
            raise ValueError(f"Artifact entry must be a regular file or directory: {relative}")
        validate_destination(root, relative, directory)
        if directory:
            directories.append(relative)
            continue
        if metadata.st_size > MAX_FILE_SIZE:
            raise ValueError(f"Artifact file too large: {relative}")
        with path.open("rb") as file:
            content = file.read(MAX_FILE_SIZE + 1)
        total_size += len(content)
        if len(content) > MAX_FILE_SIZE or total_size > MAX_TOTAL_SIZE:
            raise ValueError("Artifact exceeds size limits")
        updates[relative] = content
    if not updates:
        raise ValueError("Artifact contains no package files")
    # Validate the entire artifact before creating directories or writing files.
    for relative in directories:
        (root / relative).mkdir(parents=True, exist_ok=True)
    for relative, content in updates.items():
        (root / relative).parent.mkdir(parents=True, exist_ok=True)
        (root / relative).write_bytes(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("package", help="Only allow updates within this package")
    args = parser.parse_args()
    apply_updates(args.artifact, args.package)
