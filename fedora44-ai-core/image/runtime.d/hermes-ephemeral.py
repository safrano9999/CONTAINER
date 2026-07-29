#!/usr/bin/env python3
"""Rebuild Hermes configuration exclusively from the current environment."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Any

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

    secret_values = {
        clean(value)
        for name, value in environ.items()
        if clean(value)
        and (
            name.endswith("_API_KEY")
            or name.startswith("OPENAI_V1_KEY")
            or name in {"HERMES_API_SERVER_KEY", "HERMES_TELEGRAMTOKEN"}
        )
    }
    if not without_secret_values(config, secret_values):
        raise RuntimeError("Refusing to persist a resolved secret value")

    _atomic_write(config)
    print(f"Hermes config rebuilt atomically: {CONFIG_PATH}")
    print(f"Hermes model: {full_model}")
    print(f"Hermes OpenAI-v1 providers configured: {len(providers)}")
    for warning in warnings:
        print(f"Warning: {warning}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConfigurationError as error:
        raise SystemExit(f"Hermes configuration error: {error}") from error
