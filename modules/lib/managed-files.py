"""Install writable generated files, retaining one backup on first adoption."""

import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def absolute_path(value):
    if (not isinstance(value, str) or "\0" in value
            or not os.path.isabs(value) or os.path.normpath(value) != value
            or value == "/" or value.startswith("//")):
        raise ValueError(f"unsafe absolute path: {value!r}")
    return Path(value)


def check_file(path):
    """Missing is fine; existing leaves must resolve to regular files."""
    if path.is_symlink() and not path.exists():
        raise ValueError(f"dangling symlink: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"not a regular file: {path}")
    for parent in path.parents:
        if os.path.lexists(parent) and not parent.is_dir():
            raise ValueError(f"not a directory: {parent}")


def check_backup(path, data):
    try:
        matches = not path.is_symlink() and path.is_file() and path.read_bytes() == data
    except OSError:
        matches = False
    if not matches:
        raise ValueError(f"move existing backup {path} aside before adopting this config; "
                         "backup must be a regular file matching the current target")


def atomic_write(path, data, backup_from=None):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        if backup_from is None:
            os.replace(temporary, path)
        else:
            shutil.copystat(backup_from, temporary)
            try:
                # link publishes the complete backup without clobbering any leaf.
                os.link(temporary, path)
            except FileExistsError:
                check_backup(path, data)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def activate(manifest, state, dry_run=False, verbose=False):
    state = absolute_path(str(state))
    check_file(state)
    if state.is_symlink():
        raise ValueError(f"state must not be a symlink: {state}")
    previous = json.loads(state.read_text()) if state.exists() else []
    if not isinstance(previous, list) or any(not isinstance(p, str) for p in previous):
        raise ValueError("malformed ownership state: expected a list of absolute paths")
    owned = {absolute_path(p) for p in previous}
    if len(owned) != len(previous):
        raise ValueError("malformed ownership state: duplicate paths")
    if not isinstance(manifest, dict):
        raise ValueError("manifest must map absolute targets to source files")
    files = {absolute_path(target): absolute_path(source) for target, source in manifest.items()}
    targets = owned | files.keys()
    # Resolve parent aliases too, so a manifest cannot overwrite state or a backup.
    reserved = {state.resolve()}
    resolved = {target: target.parent.resolve() / target.name for target in targets}
    leaves = list(resolved.values()) + [state.resolve()]
    if len(set(leaves)) != len(leaves):
        raise ValueError("unsafe target: aliases another target or state file")
    for target, leaf in resolved.items():
        if target.resolve() in reserved or leaf == Path("/"):
            raise ValueError(f"unsafe target: {target}")
        if any(leaf in other.parents or other in leaf.parents
               for other in leaves if other != leaf):
            raise ValueError(f"unsafe overlapping target: {target}")
        backup = Path(str(leaf) + ".hm-backup")
        if any(backup == other or backup in other.parents or other in backup.parents
               for other in leaves):
            raise ValueError(f"target conflicts with backup: {target}")
        check_file(target)
    data = {}
    backups = {}
    for target, source in files.items():
        check_file(source)
        if not source.is_file():
            raise ValueError(f"source is missing: {source}")
        data[target] = source.read_bytes()
        backup = Path(str(target) + ".hm-backup")
        if target not in owned and target.exists():
            backups[target] = target.read_bytes()
            if os.path.lexists(backup):
                check_backup(backup, backups[target])
    if verbose or dry_run:
        print(f"managed-files: install {len(files)}, remove {len(owned - files.keys())}"
              + (" (dry run)" if dry_run else ""))
    if dry_run:
        return
    for target, content in data.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        if target in backups:
            atomic_write(Path(str(target) + ".hm-backup"), backups[target], target)
        atomic_write(target, content)
    for target in owned - files.keys():
        target.unlink(missing_ok=True)
    state.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(state, (json.dumps(sorted(map(str, files))) + "\n").encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("state", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    try:
        activate(json.loads(args.manifest.read_text()), args.state, args.dry_run, args.verbose)
    except (OSError, ValueError) as error:
        parser.exit(1, f"managed-files: {error}\n")


if __name__ == "__main__":
    main()
