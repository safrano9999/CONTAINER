#!/usr/bin/env python3
"""Rebuild Hermes configuration exclusively from the current environment."""

from __future__ import annotations

import os
import re
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml

from openclaw_ephemeral.environment import (
    ConfigurationError,
    clean,
    expand_api_key_aliases,
    without_secret_values,
)
from openclaw_ephemeral.providers import (
    OpenAIV1Provider,
    discover_openai_v1_providers,
    select_openai_v1_default,
)


HERMES_HOME = Path("/root/.hermes")
CONFIG_PATH = HERMES_HOME / "config.yaml"
EXAMPLE_PATH = Path("/usr/local/lib/hermes-agent/cli-config.yaml.example")
MAX_MCP_SERVERS = 50
MCP_FIELDS = ("NAME", "URL", "BEARER")
MCP_SUFFIX = re.compile(r"^MCP_SERVER_(?:NAME|URL|BEARER)_(\d+)$")
SAFE_MCP_SERVER_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


@dataclass(frozen=True)
class HermesMcpServer:
    """One normalized HTTP MCP server without a resolved credential."""

    index: int
    name: str
    url: str
    bearer_env: str | None

    def config(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "enabled": True,
            "url": self.url,
            "supports_parallel_tool_calls": True,
        }
        if self.bearer_env is not None:
            result["headers"] = {
                "Authorization": f"Bearer ${{{self.bearer_env}}}"
            }
        return result


def _mcp_field_env_name(
    environ: Mapping[str, str],
    field: str,
    index: int,
) -> str:
    base = f"MCP_SERVER_{field}"
    if index == 1:
        return base
    padded = f"{base}_{index:02d}"
    unpadded = f"{base}_{index}"
    for candidate in (padded, unpadded):
        if candidate in environ:
            return candidate
    return padded


def _configured_mcp_indexes(environ: Mapping[str, str]) -> tuple[int, ...]:
    indexes = {1}
    for key in environ:
        match = MCP_SUFFIX.fullmatch(key)
        if match is None:
            continue
        suffix = match.group(1)
        index = int(suffix, 10)
        if not 2 <= index <= MAX_MCP_SERVERS:
            raise ConfigurationError(
                f"{key} index must be between 02 and {MAX_MCP_SERVERS:02d}"
            )
        if suffix not in {str(index), f"{index:02d}"}:
            raise ConfigurationError(f"{key} has an unsupported numeric suffix")
        indexes.add(index)
    return tuple(sorted(indexes))


def _mcp_server_url(raw_url: str, index: int) -> str:
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


def _mcp_server_name(raw_name: str, url: str, index: int) -> str:
    name = clean(raw_name)
    if not name:
        name = clean(urlsplit(url).hostname)
        if name.endswith(".dns.podman"):
            name = name[: -len(".dns.podman")]
        name = name or f"mcp-{index:02d}"
    if SAFE_MCP_SERVER_NAME.fullmatch(name) is None:
        raise ConfigurationError(
            f"MCP server {index:02d} name must match "
            f"{SAFE_MCP_SERVER_NAME.pattern}"
        )
    return name


def discover_mcp_servers(
    environ: Mapping[str, str],
) -> tuple[HermesMcpServer, ...]:
    """Read the optional suffixless, then suffix02-style MCP groups."""

    servers: list[HermesMcpServer] = []
    seen_names: set[str] = set()
    for index in _configured_mcp_indexes(environ):
        fields = {
            field: _mcp_field_env_name(environ, field, index)
            for field in MCP_FIELDS
        }
        raw_url = clean(environ.get(fields["URL"]))
        if not raw_url:
            continue
        url = _mcp_server_url(raw_url, index)
        name = _mcp_server_name(environ.get(fields["NAME"], ""), url, index)
        folded_name = name.casefold()
        if folded_name in seen_names:
            raise ConfigurationError(f"duplicate MCP server name: {name}")
        seen_names.add(folded_name)

        bearer = clean(environ.get(fields["BEARER"]))
        if bearer.lower().startswith("bearer "):
            raise ConfigurationError(
                f"{fields['BEARER']} must contain only the token, without 'Bearer '"
            )
        servers.append(
            HermesMcpServer(
                index=index,
                name=name,
                url=url,
                bearer_env=fields["BEARER"] if bearer else None,
            )
        )
    return tuple(servers)


def mcp_servers_config(
    environ: Mapping[str, str],
) -> dict[str, dict[str, Any]]:
    """Build the global Hermes MCP mapping from injected groups."""

    return {
        server.name: server.config()
        for server in discover_mcp_servers(environ)
    }


def _fresh_template() -> dict[str, Any]:
    if not EXAMPLE_PATH.is_file():
        return {}
    payload = yaml.safe_load(EXAMPLE_PATH.read_text(encoding="utf-8")) or {}
    return payload if isinstance(payload, dict) else {}


def _requested_model(
    environ: dict[str, str],
    providers: tuple[OpenAIV1Provider, ...],
) -> str:
    explicit = clean(environ.get("HERMES_MODEL"))
    if explicit:
        return explicit
    shared = clean(environ.get("OPENCLAW_OPENAI_V1_DEFAULT_LLM"))
    if shared:
        return shared
    for provider in providers:
        if provider.models:
            return provider.models[0]
    raise ConfigurationError(
        "HERMES_MODEL is required when provider model discovery returns no models"
    )


def _atomic_write(config: dict[str, Any]) -> None:
    HERMES_HOME.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".config.yaml.",
        dir=HERMES_HOME,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            yaml.safe_dump(config, handle, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, CONFIG_PATH)
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    environ = expand_api_key_aliases(os.environ)
    mcp_servers = mcp_servers_config(environ)
    providers, warnings = discover_openai_v1_providers(environ)
    if not providers:
        raise ConfigurationError(
            "Hermes requires at least one injected OPENAI_V1_URL/KEY provider"
        )

    requested = _requested_model(environ, providers)
    selected = select_openai_v1_default(providers, requested)
    if selected is None:
        raise ConfigurationError("Hermes could not select an OpenAI-v1 model")
    full_model, providers = selected
    selected_provider_id, selected_model = full_model.split("/", 1)
    selected_provider = next(
        provider for provider in providers
        if provider.provider_id == selected_provider_id
    )

    config = _fresh_template()
    available = list(selected_provider.models)
    if selected_model not in available:
        available.insert(0, selected_model)
    config["model"] = {
        "provider": selected_provider.provider_id,
        "default": selected_model,
        "base_url": selected_provider.base_url,
        "ssl_verify": True,
        "available": available,
    }
    config["providers"] = {}
    for provider in providers:
        models = list(provider.models)
        config["providers"][provider.provider_id] = {
            "name": provider.configured_name or provider.provider_id,
            "base_url": provider.base_url,
            "key_env": provider.key_env,
            "api_mode": "chat_completions",
            "models": {model: {} for model in models},
            **({"default_model": models[0]} if models else {}),
        }
    config["providers"][selected_provider.provider_id]["default_model"] = selected_model
    if mcp_servers:
        config["mcp_servers"] = mcp_servers
    else:
        config.pop("mcp_servers", None)

    secret_values = {
        clean(value)
        for name, value in environ.items()
        if clean(value)
        and (
            name.endswith("_API_KEY")
            or name.startswith("OPENAI_V1_KEY")
            or name.startswith("MCP_SERVER_BEARER")
            or name in {"HERMES_API_SERVER_KEY", "HERMES_TELEGRAMTOKEN"}
        )
    }
    if not without_secret_values(config, secret_values):
        raise RuntimeError("Refusing to persist a resolved secret value")

    _atomic_write(config)
    print(f"Hermes config rebuilt atomically: {CONFIG_PATH}")
    print(f"Hermes model: {full_model}")
    print(f"Hermes OpenAI-v1 providers configured: {len(providers)}")
    print(f"Hermes MCP servers configured: {len(mcp_servers)}")
    for warning in warnings:
        print(f"Warning: {warning}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConfigurationError as error:
        raise SystemExit(f"Hermes configuration error: {error}") from error
