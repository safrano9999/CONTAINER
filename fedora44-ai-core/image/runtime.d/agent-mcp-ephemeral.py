#!/usr/bin/env python3
"""Project injected HTTP MCP servers into OpenClaw and Hermes configs."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml


MAX_MCP_SERVERS = 50
MCP_FIELDS = ("NAME", "URL", "BEARER")
MCP_SUFFIX = re.compile(r"^MCP_SERVER_(?:NAME|URL|BEARER)_(\d+)$")
SAFE_SERVER_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


class ConfigurationError(ValueError):
    """Raised when an injected MCP server group is invalid."""


@dataclass(frozen=True)
class McpServer:
    """One normalized HTTP MCP server without a resolved credential."""

    index: int
    name: str
    url: str
    bearer_env: str | None

    def _headers(self) -> dict[str, str]:
        if self.bearer_env is None:
            return {}
        return {"Authorization": f"Bearer ${{{self.bearer_env}}}"}

    def openclaw_config(self) -> dict[str, Any]:
        config: dict[str, Any] = {
            "enabled": True,
            "url": self.url,
            "transport": "streamable-http",
            "supportsParallelToolCalls": True,
            "codex": {"defaultToolsApprovalMode": "approve"},
        }
        headers = self._headers()
        if headers:
            config["headers"] = headers
        return config

    def hermes_config(self) -> dict[str, Any]:
        config: dict[str, Any] = {
            "enabled": True,
            "url": self.url,
            "supports_parallel_tool_calls": True,
        }
        headers = self._headers()
        if headers:
            config["headers"] = headers
        return config


def clean(value: str | None) -> str:
    return (value or "").strip()


def _field_env_name(environ: Mapping[str, str], field: str, index: int) -> str:
    base = f"MCP_SERVER_{field}"
    if index == 1:
        return base
    padded = f"{base}_{index:02d}"
    unpadded = f"{base}_{index}"
    for candidate in (padded, unpadded):
        if candidate in environ:
            return candidate
    return padded


def _configured_indexes(environ: Mapping[str, str]) -> tuple[int, ...]:
    indexes = {1}
    for key in environ:
        match = MCP_SUFFIX.fullmatch(key)
        if match is None:
            continue
        index = int(match.group(1), 10)
        if not 2 <= index <= MAX_MCP_SERVERS:
            raise ConfigurationError(
                f"{key} index must be between 02 and {MAX_MCP_SERVERS:02d}"
            )
        indexes.add(index)
    return tuple(sorted(indexes))


def _server_name(raw_name: str, url: str, index: int) -> str:
    candidate = clean(raw_name)
    if not candidate:
        host = clean(urlsplit(url).hostname)
        if host.endswith(".dns.podman"):
            host = host[: -len(".dns.podman")]
        candidate = host or f"mcp-{index:02d}"
    if SAFE_SERVER_NAME.fullmatch(candidate) is None:
        raise ConfigurationError(
            f"MCP server {index:02d} name must match {SAFE_SERVER_NAME.pattern}"
        )
    return candidate


def _server_url(raw_url: str, index: int) -> str:
    url = clean(raw_url)
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError(
            f"MCP_SERVER_URL for server {index:02d} must be an http(s) URL"
        )
    if parsed.username is not None or parsed.password is not None:
        raise ConfigurationError(
            f"MCP_SERVER_URL for server {index:02d} must not contain credentials"
        )
    return url


def discover_mcp_servers(
    environ: Mapping[str, str],
) -> tuple[McpServer, ...]:
    """Read suffixless, then suffix02-style MCP groups from the environment."""

    servers: list[McpServer] = []
    seen_names: set[str] = set()
    for index in _configured_indexes(environ):
        names = {
            field: _field_env_name(environ, field, index)
            for field in MCP_FIELDS
        }
        raw_url = clean(environ.get(names["URL"]))
        if not raw_url:
            # The complete repeat group is optional. Stray optional values do
            # not turn an otherwise empty slot into a configured MCP server.
            continue
        url = _server_url(raw_url, index)
        name = _server_name(environ.get(names["NAME"], ""), url, index)
        dedupe_name = name.casefold()
        if dedupe_name in seen_names:
            raise ConfigurationError(f"duplicate MCP server name: {name}")
        seen_names.add(dedupe_name)

        bearer = clean(environ.get(names["BEARER"]))
        if bearer.lower().startswith("bearer "):
            raise ConfigurationError(
                f"{names['BEARER']} must contain only the token, without 'Bearer '"
            )
        servers.append(
            McpServer(
                index=index,
                name=name,
                url=url,
                bearer_env=names["BEARER"] if bearer else None,
            )
        )
    return tuple(servers)


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def _load_mapping(path: Path, *, kind: str) -> dict[str, Any]:
    if not path.is_file():
        raise ConfigurationError(f"{kind} config does not exist: {path}")
    try:
        if kind == "OpenClaw":
            payload = json.loads(path.read_text(encoding="utf-8"))
        else:
            payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (json.JSONDecodeError, yaml.YAMLError) as exc:
        raise ConfigurationError(f"invalid {kind} config: {path}") from exc
    if not isinstance(payload, dict):
        raise ConfigurationError(f"{kind} config must contain a mapping: {path}")
    return payload


def configure_openclaw(path: Path, servers: Sequence[McpServer]) -> None:
    config = _load_mapping(path, kind="OpenClaw")
    mcp = config.get("mcp")
    if mcp is not None and not isinstance(mcp, dict):
        raise ConfigurationError("OpenClaw mcp config must be a mapping")
    mcp = dict(mcp or {})
    if servers:
        mcp["servers"] = {
            server.name: server.openclaw_config()
            for server in servers
        }
        config["mcp"] = mcp
    else:
        mcp.pop("servers", None)
        if mcp:
            config["mcp"] = mcp
        else:
            config.pop("mcp", None)
    _atomic_write(path, json.dumps(config, ensure_ascii=False, indent=2) + "\n")


def configure_hermes(path: Path, servers: Sequence[McpServer]) -> None:
    config = _load_mapping(path, kind="Hermes")
    if servers:
        config["mcp_servers"] = {
            server.name: server.hermes_config()
            for server in servers
        }
    else:
        config.pop("mcp_servers", None)
    _atomic_write(path, yaml.safe_dump(config, sort_keys=False))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Rebuild shared OpenClaw/Hermes MCP configuration from the environment."
    )
    parser.add_argument("target", choices=("openclaw", "hermes", "all"))
    parser.add_argument(
        "--openclaw-config",
        type=Path,
        default=Path(
            os.environ.get(
                "OPENCLAW_CONFIG_PATH",
                "/root/.openclaw/openclaw.json",
            )
        ),
    )
    parser.add_argument(
        "--hermes-config",
        type=Path,
        default=Path("/root/.hermes/config.yaml"),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        servers = discover_mcp_servers(os.environ)
        if args.target in {"openclaw", "all"}:
            configure_openclaw(args.openclaw_config, servers)
            print(
                "OpenClaw MCP config rebuilt atomically: "
                f"{len(servers)} server(s)"
            )
        if args.target in {"hermes", "all"}:
            configure_hermes(args.hermes_config, servers)
            print(
                "Hermes MCP config rebuilt atomically: "
                f"{len(servers)} server(s)"
            )
        return 0
    except ConfigurationError as exc:
        raise SystemExit(f"MCP configuration error: {exc}") from exc


if __name__ == "__main__":
    raise SystemExit(main())
