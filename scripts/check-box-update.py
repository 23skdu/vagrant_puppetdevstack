#!/usr/bin/env python3
"""Check the pinned Vagrant box for a newer VirtualBox-capable release.

Dependabot does not understand Vagrant Cloud, so this script fills that gap.
The scheduled GitHub Actions workflow uses --update to open a PR; locally,
`make box-check` uses --check for a read-only result.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("ERROR: PyYAML is required. Install with: pip install -r requirements-dev.txt", file=sys.stderr)
    raise SystemExit(2) from None

CONFIG = Path(__file__).resolve().parents[1] / "vagrant" / "config" / "default.yaml"
API_ROOT = "https://app.vagrantup.com/api/v1/box"
REQUEST_TIMEOUT = 20


def version_key(version: str) -> tuple[tuple[int, object], ...]:
    """Natural sort key so 12.20260519.1 sorts after 12.20250126.1."""
    return tuple((0, int(part)) if part.isdigit() else (1, part) for part in version.split("."))


def available_versions(box: str) -> list[str]:
    if box.count("/") != 1:
        raise ValueError(f"box.name must be 'owner/name', got {box!r}")

    request = urllib.request.Request(
        f"{API_ROOT}/{box}",
        headers={"User-Agent": "vagrant_puppetdevstack-box-check/1.0", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        payload: dict = json.load(response)

    versions = []
    for release in payload.get("versions", []):
        if release.get("status") != "active":
            continue
        providers = {provider.get("name") for provider in release.get("providers", [])}
        if "virtualbox" in providers and release.get("version"):
            versions.append(str(release["version"]))
    return versions


def current_version(text: str) -> str:
    match = re.search(r"(?ms)^box:\s*$(.*?)(?=^\S|\Z)", text)
    if not match:
        raise ValueError("Could not find a top-level 'box:' section")
    version = re.search(r'^  version:\s*"?([^"\s]+)"?\s*$', match.group(1), re.MULTILINE)
    if not version:
        raise ValueError("Could not find box.version")
    return version.group(1)


def replace_version(text: str, new_version: str) -> str:
    lines = text.splitlines(keepends=True)
    in_box = False
    replaced = False
    for index, line in enumerate(lines):
        if re.match(r"^box:\s*$", line.rstrip("\r\n")):
            in_box = True
            continue
        if in_box and line and not line[0].isspace() and not line.lstrip().startswith("#"):
            in_box = False
        if in_box and re.match(r"^  version:\s*", line):
            comment = ""
            if "#" in line:
                comment = "  " + line[line.index("#"):].rstrip("\r\n")
            indent_end = line.index("version:")
            lines[index] = f'{line[:indent_end]}version: "{new_version}"{comment}\n'
            replaced = True
            break
    if not replaced:
        raise ValueError("Could not update box.version")
    return "".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true", help="exit 1 when a newer box exists")
    group.add_argument("--update", action="store_true", help="rewrite config/default.yaml in place")
    args = parser.parse_args()

    text = CONFIG.read_text(encoding="utf-8")
    data = yaml.safe_load(text)
    box = str(data["box"]["name"])
    pinned = current_version(text)

    try:
        versions = available_versions(box)
    except Exception as exc:  # network/API failures should be visible, not silent
        print(f"ERROR: could not query Vagrant Cloud: {exc}", file=sys.stderr)
        return 2

    if not versions:
        print(f"ERROR: no active VirtualBox releases found for {box}", file=sys.stderr)
        return 2

    latest = max(versions, key=version_key)
    print(f"box={box} pinned={pinned} latest_virtualbox={latest}")

    if version_key(latest) <= version_key(pinned):
        print("Box version is current.")
        return 0

    if args.check:
        print(f"Update available: {pinned} -> {latest}", file=sys.stderr)
        return 1

    CONFIG.write_text(replace_version(text, latest), encoding="utf-8")
    print(f"Updated {CONFIG} to {latest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
