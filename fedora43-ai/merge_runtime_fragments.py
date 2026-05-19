#!/usr/bin/env python3
"""Merge repo runtime fragments into the generated Fedora compose/quadlet files."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml


REPOS = ("CODEANALYST", "JUGO", "CITADEL", "VikAI")
COMPOSE_FRAGMENT = "fedora43-ai.compose.yml"
CONTAINER_FRAGMENT = "fedora43-ai.container.fragment"


class IndentDumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def as_list(value) -> list:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def add_unique(target: list, values: list) -> None:
    for value in values:
        if value not in target:
            target.append(value)


def normalize_port(value, host: str) -> str | None:
    if isinstance(value, dict):
        target = value.get("target")
        published = value.get("published", target)
        protocol = value.get("protocol")
        if not target or not published:
            return None
        target = str(target)
        published = str(published)
        if protocol and "/" not in target:
            target = f"{target}/{protocol}"
        return f"{host}:{published}:{target}"

    raw = str(value).strip().strip('"').strip("'")
    if not raw:
        return None

    parts = raw.split(":")
    if len(parts) == 1:
        published = target = parts[0]
    elif len(parts) == 2:
        published, target = parts
    else:
        published, target = parts[-2], parts[-1]
    return f"{host}:{published}:{target}"


def volume_target(value) -> str:
    if isinstance(value, dict):
        return str(value.get("target", value))
    parts = str(value).split(":")
    return parts[1] if len(parts) > 1 else parts[0]


def named_volume_source(value) -> str | None:
    if isinstance(value, dict):
        source = value.get("source")
    else:
        parts = str(value).split(":")
        source = parts[0] if len(parts) > 1 else None
    if not source:
        return None
    source = str(source)
    if source.startswith(("/", ".", "$", "~")) or "/" in source:
        return None
    return source


def merge_compose_fragment(compose: dict, fragment_path: Path, host: str) -> dict[str, int]:
    fragment = yaml.safe_load(fragment_path.read_text()) or {}
    services = fragment.get("services") if isinstance(fragment, dict) else None
    if not isinstance(services, dict) or not services:
        return {"ports": 0, "cap_add": 0, "devices": 0, "volumes": 0}

    service_fragment = next(iter(services.values())) or {}
    service = compose.setdefault("services", {}).setdefault("fedora43-ai", {})
    counts = {"ports": 0, "cap_add": 0, "devices": 0, "volumes": 0}

    ports = service.setdefault("ports", [])
    for port in as_list(service_fragment.get("ports")):
        normalized = normalize_port(port, host)
        if normalized and normalized not in ports:
            ports.append(normalized)
            counts["ports"] += 1

    for key in ("cap_add", "devices"):
        target = service.setdefault(key, [])
        before = len(target)
        add_unique(target, as_list(service_fragment.get(key)))
        counts[key] += len(target) - before

    volumes = service.setdefault("volumes", [])
    existing_targets = {volume_target(item) for item in volumes}
    for volume in as_list(service_fragment.get("volumes")):
        target = volume_target(volume)
        if target in existing_targets:
            continue
        volumes.append(volume)
        existing_targets.add(target)
        counts["volumes"] += 1
        source = named_volume_source(volume)
        if source:
            compose.setdefault("volumes", {}).setdefault(source, {})

    return counts


def parse_container_fragment(path: Path, host: str) -> list[str]:
    lines: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("PublishPort="):
            normalized = normalize_port(line.split("=", 1)[1], host)
            if normalized:
                lines.append(f"PublishPort={normalized}")
        elif line.startswith(("AddCapability=", "AddDevice=", "Volume=")):
            lines.append(line)
    return lines


def merge_container_fragment(container_path: Path, fragment_lines: list[str]) -> None:
    if not fragment_lines:
        return

    lines = container_path.read_text().splitlines()
    try:
        insert_at = lines.index("[Service]")
    except ValueError:
        insert_at = len(lines)

    existing = set(lines)
    to_insert = [line for line in fragment_lines if line not in existing]
    if not to_insert:
        return

    lines[insert_at:insert_at] = to_insert + [""]
    container_path.write_text("\n".join(lines) + "\n")


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: merge_runtime_fragments.py SCRIPT_DIR COMPOSE_PATH CONTAINER_PATH HOST"
        )

    script_dir = Path(sys.argv[1])
    compose_path = Path(sys.argv[2])
    container_path = Path(sys.argv[3])
    host = sys.argv[4]
    safrano_dir = script_dir / "safrano9999"

    compose = yaml.safe_load(compose_path.read_text()) or {}
    container_lines: list[str] = []
    total_counts = {"ports": 0, "cap_add": 0, "devices": 0, "volumes": 0}

    for repo in REPOS:
        repo_dir = safrano_dir / repo
        compose_fragment = repo_dir / COMPOSE_FRAGMENT
        container_fragment = repo_dir / CONTAINER_FRAGMENT

        if compose_fragment.exists():
            counts = merge_compose_fragment(compose, compose_fragment, host)
            for key, value in counts.items():
                total_counts[key] += value
        if container_fragment.exists():
            add_unique(container_lines, parse_container_fragment(container_fragment, host))

    for volume_name, volume_value in list((compose.get("volumes") or {}).items()):
        if volume_value is None:
            compose["volumes"][volume_name] = {}

    compose_path.write_text(
        yaml.dump(compose, Dumper=IndentDumper, sort_keys=False),
        encoding="utf-8",
    )
    merge_container_fragment(container_path, container_lines)

    print(
        "  Merged runtime fragments: "
        f"ports={total_counts['ports']}, "
        f"cap_add={total_counts['cap_add']}, "
        f"devices={total_counts['devices']}, "
        f"volumes={total_counts['volumes']}"
    )


if __name__ == "__main__":
    main()
