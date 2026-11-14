"""Select native CI packages from evaluated flake metadata and the event diff."""

import json
import os
from pathlib import Path
import subprocess
import sys


RUNNERS = {
    "x86_64-linux": "ubuntu-26.04",
    "aarch64-linux": "ubuntu-26.04-arm",
    "aarch64-darwin": "macos-26",
}


def changed_paths(event_name, event):
    if event_name == "workflow_dispatch":
        return None
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
    elif event_name == "push":
        base = event["before"]
        if not base.strip("0"):
            return None
    else:
        raise ValueError(f"Unsupported event: {event_name}")
    # No rename detection: both the old and new package directories must count.
    return subprocess.check_output(
        ["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD"],
    ).decode().split("\0")[:-1]


def is_binary(attribute, metadata):
    return any(
        "bin" in name.split("-")
        for name in (attribute, metadata.get("pname", ""), metadata.get("name", ""))
    )


def select_matrix(packages, paths):
    full = paths is None or any(
        path in {"flake.nix", "flake.lock", ".github/workflows/ci.yml", "scripts/ci-packages.py"}
        or path.startswith("shared/")
        for path in paths
    )
    directories = {
        path.split("/")[1]
        for path in paths or []
        if path.startswith("pkgs/") and len(path.split("/")) >= 3
    }
    include = []
    for system, native in sorted(packages.items()):
        selected = sorted(
            name for name in native
            if name != "default" and (
                full or any(name == directory or name.startswith(directory + "-") for directory in directories)
            )
        )
        if selected:
            include.append({
                "system": system,
                "os": RUNNERS[system],
                "packages": selected,
                "cache_packages": [name for name in selected if not is_binary(name, native[name])],
            })
    return {"include": include}


if __name__ == "__main__":
    packages = json.loads(Path(sys.argv[1]).read_text())
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    print(json.dumps(select_matrix(packages, changed_paths(os.environ["GITHUB_EVENT_NAME"], event))))
