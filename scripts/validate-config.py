#!/usr/bin/env python3
"""Validate the Vagrant stack configuration without requiring Vagrant/Ruby.

This mirrors the invariants enforced by vagrant/Vagrantfile so validation can
fail fast on malformed configuration. Uses only PyYAML from requirements-dev.txt.
"""

from __future__ import annotations

import ipaddress
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover - depends on developer environment
    print("ERROR: PyYAML is required. Install it with: pip install -r requirements-dev.txt", file=sys.stderr)
    raise SystemExit(2) from None

DEFAULT_CONFIG = Path(__file__).resolve().parents[1] / "vagrant" / "config" / "default.yaml"

HOSTNAME_RE = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$"
)
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
URL_RE = re.compile(
    r"^(?:https://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+|git@[A-Za-z0-9._-]+:[A-Za-z0-9._~:/?-]+)$"
)
NODE_NAMES = ("puppetserver", "puppetagent")
SUPPORTED_PUPPET = {"7", "8"}


class Validator:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def fail(self, message: str) -> None:
        self.errors.append(message)

    def section(self, data: Any, key: str, context: str) -> dict[str, Any]:
        if not isinstance(data, dict):
            self.fail(f"{context} must be a mapping")
            return {}
        if key not in data:
            self.fail(f"Missing required key: {context}.{key}")
            return {}
        value = data[key]
        if not isinstance(value, dict):
            self.fail(f"{context}.{key} must be a mapping")
            return {}
        return value

    def value(self, data: dict[str, Any], key: str, context: str) -> Any:
        if key not in data:
            self.fail(f"Missing required key: {context}.{key}")
            return None
        result = data[key]
        if result is None or (isinstance(result, str) and not result.strip()):
            self.fail(f"Empty key: {context}.{key}")
            return None
        return result

    def string(self, data: dict[str, Any], key: str, context: str) -> str:
        result = self.value(data, key, context)
        return "" if result is None else str(result)

    def number(self, data: dict[str, Any], key: str, context: str) -> int | None:
        result = self.value(data, key, context)
        if isinstance(result, bool):
            self.fail(f"{context}.{key} must be an integer")
            return None
        try:
            return int(result)
        except (TypeError, ValueError):
            self.fail(f"{context}.{key} must be an integer")
            return None

    def match(self, value: str, pattern: re.Pattern[str], label: str) -> None:
        if value and not pattern.fullmatch(value):
            self.fail(f"Invalid {label}: {value!r}")

    def check(self, config_path: Path) -> bool:
        try:
            raw = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        except OSError as exc:
            self.fail(f"Cannot read {config_path}: {exc}")
            return False
        except yaml.YAMLError as exc:
            self.fail(f"Invalid YAML in {config_path}: {exc}")
            return False

        if not isinstance(raw, dict):
            self.fail("Configuration root must be a mapping")
            return False

        box = self.section(raw, "box", "root")
        puppet = self.section(raw, "puppet", "root")
        network_cfg = self.section(raw, "network", "root")
        nodes = self.section(raw, "nodes", "root")
        control = self.section(puppet, "control_repo", "puppet")

        self.string(box, "name", "box")
        version = self.string(box, "version", "box")
        if version and not re.fullmatch(r"[0-9][0-9A-Za-z.\-]*", version):
            self.fail(f"box.version must be an immutable version string: {version!r}")

        checksum = str(box.get("checksum") or "").strip()
        checksum_type = str(box.get("checksum_type") or "sha256")
        if checksum:
            if checksum_type not in {"sha256", "sha512"}:
                self.fail("box.checksum_type must be sha256 or sha512")
            digits = 64 if checksum_type == "sha256" else 128
            if not re.fullmatch(rf"[0-9a-fA-F]{{{digits}}}", checksum):
                self.fail(f"box.checksum must contain {digits} hex characters")

        puppet_version = self.string(puppet, "version", "puppet")
        if puppet_version not in SUPPORTED_PUPPET:
            self.fail(f"puppet.version must be one of {sorted(SUPPORTED_PUPPET)}")

        self.match(self.string(puppet, "server_hostname", "puppet"), HOSTNAME_RE, "puppet.server_hostname")
        self.match(self.string(puppet, "environment", "puppet"), NAME_RE, "puppet.environment")
        autosign = self.string(puppet, "autosign", "puppet")
        if autosign and re.search(r"\s", autosign):
            self.fail("puppet.autosign must not contain whitespace")

        self.match(self.string(control, "https", "puppet.control_repo"), URL_RE, "puppet.control_repo.https")
        self.match(self.string(control, "ssh", "puppet.control_repo"), URL_RE, "puppet.control_repo.ssh")
        self.match(self.string(control, "branch", "puppet.control_repo"), NAME_RE, "puppet.control_repo.branch")

        subnet_text = self.string(network_cfg, "subnet", "network")
        network: ipaddress.IPv4Network | None = None
        try:
            network = ipaddress.ip_network(subnet_text, strict=True)
            if network.version != 4:
                self.fail("network.subnet must be IPv4")
                network = None
        except ValueError as exc:
            self.fail(f"Invalid network.subnet: {exc}")

        self.match(self.string(network_cfg, "internal_network", "network"), NAME_RE, "network.internal_network")

        if "gui" in raw and not isinstance(raw["gui"], bool):
            self.fail("gui must be a boolean")

        timeout = raw.get("boot_timeout", 300)
        if isinstance(timeout, bool) or not isinstance(timeout, int) or timeout <= 0:
            self.fail("boot_timeout must be a positive integer")

        seen_octets: set[int] = set()
        for name in NODE_NAMES:
            node = self.section(nodes, name, "nodes")
            context = f"nodes.{name}"
            self.match(self.string(node, "hostname", context), HOSTNAME_RE, f"{context}.hostname")
            octet = self.number(node, "ip_octet", context)
            if octet is not None:
                if not 2 <= octet <= 254:
                    self.fail(f"{context}.ip_octet must be between 2 and 254")
                elif octet in seen_octets:
                    self.fail(f"{context}.ip_octet {octet} is duplicated")
                else:
                    seen_octets.add(octet)
                if network is not None and network.network_address + octet not in network:
                    self.fail(f"{context}.ip_octet {octet} is outside {network}")

            memory = self.number(node, "memory_mb", context)
            if memory is not None and memory < 512:
                self.fail(f"{context}.memory_mb must be at least 512")
            cpus = self.number(node, "cpus", context)
            if cpus is not None and cpus < 1:
                self.fail(f"{context}.cpus must be at least 1")

        return not self.errors


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CONFIG
    validator = Validator()
    if validator.check(path):
        print(f"OK: {path} is valid")
        return 0

    print(f"INVALID: {path}", file=sys.stderr)
    for error in validator.errors:
        print(f"  - {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
