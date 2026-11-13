#!/usr/bin/env python3
"""Regenerate Edge's dependency pins without executing upstream Python."""

import argparse
import ast
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote
from urllib.request import Request, urlopen

MAX_SIZE = 2 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=600).stdout


def function(tree, name):
    matches = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name]
    require(len(matches) == 1, f"Expected one upstream {name} function")
    return matches[0]


def assignment(nodes, name):
    matches = [n.value for n in nodes if isinstance(n, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == name for t in n.targets)]
    require(len(matches) == 1, f"Expected one literal upstream {name} assignment")
    return ast.literal_eval(matches[0])


def github_repo(url):
    require(isinstance(url, str), "Repository URL must be a string")
    match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9_.-]+)\.git", url)
    require(match is not None and match[2] not in (".", ".."), "Unsupported GitHub repository URL")
    return f"{match[1]}/{match[2]}"


def requirements(source):
    tree = ast.parse(Path(source).read_text())
    fetch = function(tree, "fetch_data_repos")
    repos = assignment(fetch.body, "data_repos")
    require(isinstance(repos, list) and repos, "Expected nonempty upstream data_repos")
    names = set()
    for repo in repos:
        require(isinstance(repo, dict) and {"name", "url", "branch"} <= repo.keys()
                <= {"name", "url", "branch", "sparse_paths"}, "Unsupported data_repos schema")
        name = repo["name"]
        require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]+", name)
                and name not in names and name != "slang", "Unsafe or duplicate dependency name")
        names.add(name)
        github_repo(repo["url"])
        branch = repo["branch"]
        require(isinstance(branch, str) and branch and not branch.startswith("-"), "Unsafe Git ref")
        run(["git", "check-ref-format", "refs/heads/" + branch])
        if "sparse_paths" in repo:
            require(isinstance(repo["sparse_paths"], list) and all(
                isinstance(p, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", p)
                and p not in (".", "..") for p in repo["sparse_paths"]), "Unsupported sparse paths")
    require(names == {"game-patches", "x360db", "SDL_GameControllerDB"},
            "Upstream data dependencies changed; update the package recipe")

    version = assignment(tree.body, "SLANG_VERSION")
    base = assignment(tree.body, "SLANG_RELEASE_URL")
    require(isinstance(version, str) and re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", version),
            "Unsupported Slang version")
    require(base == "https://github.com/shader-slang/slang/releases/download", "Unsupported Slang URL")
    host = function(tree, "get_slang_host_asset")
    linux = [n for n in host.body if isinstance(n, ast.If)
             and ast.dump(n.test) == ast.dump(ast.parse("sys.platform == 'linux'", mode="eval").body)]
    require(len(linux) == 1 and len(linux[0].body) == 2, "Unsupported Slang Linux asset selection")
    arch, result = linux[0].body
    require(isinstance(arch, ast.Assign) and len(arch.targets) == 1
            and isinstance(arch.targets[0], ast.Name) and arch.targets[0].id == "arch"
            and ast.dump(arch.value) == ast.dump(ast.parse(
                "'aarch64' if is_arm64 else 'x86_64'", mode="eval").body), "Unsupported Slang architecture")
    require(isinstance(result, ast.Return) and isinstance(result.value, ast.Tuple)
            and len(result.value.elts) == 2, "Unsupported Slang asset return")
    template, executable = result.value.elts
    require(isinstance(template, ast.JoinedStr) and ast.literal_eval(executable) == "bin/slangc",
            "Unsupported Slang executable")
    parts = []
    values = {"SLANG_VERSION": version, "arch": "x86_64"}
    for part in template.values:
        if isinstance(part, ast.Constant) and isinstance(part.value, str):
            parts.append(part.value)
        else:
            require(isinstance(part, ast.FormattedValue) and isinstance(part.value, ast.Name)
                    and part.value.id in values and part.conversion == -1 and part.format_spec is None,
                    "Unsupported Slang asset expression")
            parts.append(values[part.value.id])
    asset = "".join(parts)
    require(asset == f"slang-{version}-linux-x86_64.tar.gz", "Unsupported Slang Linux asset name")

    calls = [n for n in ast.walk(fetch) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Name) and n.func.id == "download_github_release_asset"]
    require(len(calls) == 1 and len(calls[0].args) == 4 and not calls[0].keywords,
            "Unsupported compatibility download call")
    release = []
    for arg in calls[0].args[:3]:
        release.append(assignment(fetch.body, arg.id) if isinstance(arg, ast.Name) else ast.literal_eval(arg))
    repo, tag, name = release
    github_repo(f"https://github.com/{repo}.git")
    require(isinstance(tag, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", tag)
            and tag not in (".", "..") and name == "compatibility_data.json", "Unsupported compatibility release")
    return repos, f"{base}/v{version}/{asset}", release


def prefetch(url, refresh=False):
    metadata = json.loads(run(["nix"] + (["--refresh"] if refresh else [])
                              + ["store", "prefetch-file", "--json", url]))
    value = metadata["hash"]
    require(isinstance(value, str) and value.startswith("sha256-"), "Expected SRI SHA256")
    digest = base64.b64decode(value[7:], validate=True)
    require(len(digest) == 32 and base64.b64encode(digest).decode() == value[7:], "Invalid SRI hash")
    return {"url": url, "hash": value}


def download(url, accept="application/json"):
    request = Request(url, headers={"User-Agent": "nix-emulators-edge-updater", "Accept": accept})
    with urlopen(request, timeout=60) as response:
        require(response.url.startswith("https://"), "Download redirected away from HTTPS")
        data = response.read(MAX_SIZE + 1)
    require(len(data) <= MAX_SIZE, "Download exceeds 2 MiB limit")
    return data


def compatibility_pin(release):
    repo, tag, name = release
    metadata = json.loads(download(f"https://api.github.com/repos/{repo}/releases/tags/{quote(tag, safe='')}"))
    assets = [a for a in metadata["assets"] if a.get("name") == name]
    require(len(assets) == 1, "Expected one compatibility release asset")
    asset = assets[0]
    require(type(asset.get("size")) is int and 0 < asset["size"] <= MAX_SIZE, "Invalid compatibility asset size")
    url = asset.get("browser_download_url")
    require(url == f"https://github.com/{repo}/releases/download/{tag}/{name}", "Unexpected release asset URL")
    data = download(url, "application/octet-stream")
    require(len(data) == asset["size"], "Compatibility asset size changed during download")
    digest = asset.get("digest")
    if digest is not None:
        require(isinstance(digest, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
                and digest == "sha256:" + hashlib.sha256(data).hexdigest(), "Compatibility asset digest mismatch")
    records = json.loads(data)
    require(isinstance(records, list) and records, "Expected nonempty compatibility records")
    for item in records:
        require(isinstance(item, dict) and set(item) == {"issue", "id", "title", "updated", "state", "labels", "url"}
                and type(item["issue"]) is int and item["issue"] > 0
                and all(isinstance(item[k], str) and item[k] for k in ("id", "title", "updated", "state", "url"))
                and item["url"] == f"https://github.com/{repo}/issues/{item['issue']}"
                and isinstance(item["labels"], dict) and set(item["labels"]) == {"state", "others"}
                and all(isinstance(labels, list) and all(isinstance(v, str) for v in labels)
                        for labels in item["labels"].values()), "Unsupported compatibility record schema")
    pin = prefetch(url, refresh=True)
    expected = "sha256-" + base64.b64encode(hashlib.sha256(data).digest()).decode()
    require(pin["hash"] == expected, "Prefetched compatibility differs from validated current release")
    return pin


def update(source, output):
    repos, slang, release = requirements(source)
    pins = {}
    for repo in repos:
        ref = "refs/heads/" + repo["branch"]
        lines = run(["git", "ls-remote", "--exit-code", "--refs", repo["url"], ref]).splitlines()
        require(len(lines) == 1, "Expected exactly one Git branch revision")
        fields = lines[0].split("\t")
        require(len(fields) == 2 and fields[1] == ref and re.fullmatch(r"[0-9a-f]{40}", fields[0]),
                "Invalid Git branch resolution")
        pins[repo["name"]] = prefetch(f"https://github.com/{github_repo(repo['url'])}/archive/{fields[0]}.tar.gz")
    pins["slang"] = prefetch(slang)
    pins["compatibility"] = compatibility_pin(release)
    output = Path(output)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=output.parent, delete=False) as file:
            temporary = Path(file.name)
            json.dump(pins, file, indent=2)
            file.write("\n")
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)
    print(f"Updated {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("output", type=Path, nargs="?", default=Path("pkgs/xenia-edge-git/deps.json"))
    args = parser.parse_args()
    update(args.source, args.output)
