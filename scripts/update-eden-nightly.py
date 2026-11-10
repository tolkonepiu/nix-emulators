#!/usr/bin/env python3
"""Pin the latest complete Eden nightly release without executing its artifacts."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.parse
import urllib.request

API = "https://git.eden-emu.dev/api/v1/repos/eden-ci/nightly/releases?limit=1"
MANIFEST = Path(__file__).resolve().parents[1] / "pkgs/eden-nightly-bin/sources.json"
HOST = "nightly.eden-emu.dev"


def trusted_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.netloc != HOST or parsed.query or parsed.fragment:
        raise ValueError(f"Untrusted download URL: {url}")


class TrustedRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        trusted_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def release_links(release):
    tag = release["tag_name"]
    match = re.fullmatch(r"v[0-9]+\.([0-9a-f]{10})", tag)
    if not match or release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("Expected a published, non-prerelease nightly tag")
    commit = match[1]
    expected = {}
    for system, target, variant in (
        ("x86_64-linux", "amd64", "standard"),
        ("x86_64-linux", "amd64", "pgo"),
        ("x86_64-linux", "steamdeck", "zen2"),
        ("x86_64-linux", "steamdeck", "zen2-pgo"),
        ("x86_64-linux", "rog-ally", "zen4"),
        ("x86_64-linux", "rog-ally", "zen4-pgo"),
        ("aarch64-linux", "aarch64", "standard"),
        ("aarch64-linux", "aarch64", "pgo"),
    ):
        compiler = "clang-pgo" if variant.endswith("pgo") else "gcc-standard"
        expected[f"Eden-Linux-{commit}-{target}-{compiler}.AppImage"] = (system, variant)
    expected[f"Eden-macOS-{commit}.dmg"] = ("aarch64-darwin", "standard")

    sources = {}
    seen = set()
    for url in re.findall(r"\[[^\]\n]*\]\(([^\s)]+)\)", release["body"]):
        filename = urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1]
        if filename not in expected:
            continue
        trusted_url(url)
        if urllib.parse.urlsplit(url).path != f"/{tag}/{filename}":
            raise ValueError(f"Wrong release path: {url}")
        if filename in seen:
            raise ValueError(f"Ambiguous duplicate link: {filename}")
        seen.add(filename)
        system, variant = expected[filename]
        sources.setdefault(system, {})[variant] = url
    if seen != expected.keys():
        raise ValueError(f"Missing release links: {sorted(expected.keys() - seen)}")
    return sources


def download_hash(url):
    trusted_url(url)
    digest = hashlib.sha256()
    with urllib.request.build_opener(TrustedRedirects()).open(url, timeout=120) as response:
        trusted_url(response.geturl())
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            digest.update(chunk)
        expected_size = response.headers.get("Content-Length")
        if size == 0 or (expected_size is not None and size != int(expected_size)):
            raise ValueError(f"Empty or incomplete download: {url}")
    return "sha256-" + base64.b64encode(digest.digest()).decode("ascii")


def update(path=MANIFEST, force=False):
    with urllib.request.urlopen(API, timeout=60) as response:
        releases = json.load(response)
    if not isinstance(releases, list) or not releases:
        raise ValueError("Release API returned no releases")
    release = releases[0]
    links = release_links(release)
    if path.exists() and not force and json.loads(path.read_text())["tag"] == release["tag_name"]:
        print(f"Already pinned {release['tag_name']}")
        return False
    sources = {}
    for system, variants in links.items():
        sources[system] = {}
        for variant, url in variants.items():
            print(f"Hashing {system}/{variant}: {url}", flush=True)
            sources[system][variant] = {"url": url, "hash": download_hash(url)}
    manifest = {"version": release["tag_name"][1:], "tag": release["tag_name"], "sources": sources}
    path.parent.mkdir(parents=True, exist_ok=True)
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
    print(f"Pinned {manifest['tag']}")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="Rehash even if the tag is unchanged")
    args = parser.parse_args()
    update(force=args.force)
