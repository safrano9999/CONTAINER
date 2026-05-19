#!/usr/bin/env python3
"""Configure Hermes for the in-container LiteLLM gateway without storing secrets."""

import os
import shutil
import json
import urllib.error
import urllib.request
from pathlib import Path

import yaml


DEFAULT_MODEL = "deepseek-v4-flash"
DEFAULT_HOME = "/root/hermes-home"
DEFAULT_INSTALL_DIR = "/usr/local/lib/hermes-agent"
DISCOVERY_TIMEOUT_SECONDS = 5


def _litellm_base_url() -> str:
    raw_url = os.environ.get("LITELLM_URL", "").strip()
    port = os.environ.get("LITELLM_PORT", "").strip()
    if not raw_url:
        raise SystemExit("LITELLM_URL must not be empty")
    if not port:
        raise SystemExit("LITELLM_PORT must not be empty")

    base = raw_url.rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3].rstrip("/")
    return f"{base}:{port}/v1"


def _model_name() -> str:
    model = (
        os.environ.get("HERMES_LITELLM_MODEL", "").strip()
        or os.environ.get("OPENCLAW_LITELLM_MODEL", "").strip()
        or DEFAULT_MODEL
    )
    if model.startswith("litellm/"):
        model = model.removeprefix("litellm/")
    if model.startswith("custom/"):
        model = model.removeprefix("custom/")
    if not model:
        raise SystemExit("HERMES_LITELLM_MODEL must not be empty")
    return model


def _discover_litellm_models(base_url: str) -> list[str]:
    api_key = os.environ.get("LITELLM_API_KEY", "").strip()
    if not api_key:
        return []

    request = urllib.request.Request(
        f"{base_url}/models",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=DISCOVERY_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        print(f"Hermes LiteLLM model discovery skipped: {exc}")
        return []

    discovered: list[str] = []
    for item in payload.get("data", []) if isinstance(payload, dict) else []:
        model_id = item.get("id") if isinstance(item, dict) else item
        if not isinstance(model_id, str):
            continue
        model_id = model_id.strip()
        if model_id.startswith("litellm/"):
            model_id = model_id.removeprefix("litellm/")
        if model_id and model_id not in discovered:
            discovered.append(model_id)
    return discovered


def _ensure_config(config_path: Path) -> None:
    if config_path.exists():
        return

    install_dir = Path(os.environ.get("HERMES_INSTALL_DIR", DEFAULT_INSTALL_DIR))
    example_path = install_dir / "cli-config.yaml.example"
    if example_path.exists():
        shutil.copyfile(example_path, config_path)
        return

    config_path.write_text("model:\n  provider: custom\n", encoding="utf-8")


def main() -> None:
    hermes_home = Path(os.environ.get("HERMES_HOME", DEFAULT_HOME)).expanduser()
    hermes_home.mkdir(parents=True, exist_ok=True)
    config_path = hermes_home / "config.yaml"
    _ensure_config(config_path)

    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if not isinstance(config, dict):
        config = {}

    model = _model_name()
    base_url = _litellm_base_url()
    discovered_models = _discover_litellm_models(base_url)

    model_config = config.setdefault("model", {})
    if not isinstance(model_config, dict):
        model_config = {}
        config["model"] = model_config

    model_config["provider"] = "custom"
    model_config["default"] = f"custom/{model}"
    model_config["base_url"] = base_url
    model_config["ssl_verify"] = False
    if discovered_models:
        model_config["available"] = discovered_models
    model_config.pop("api_key", None)

    config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    os.chmod(config_path, 0o600)
    print(f"Hermes LiteLLM model configured: custom/{model}")
    print(f"Hermes LiteLLM base URL configured: {base_url}")
    if discovered_models:
        print(f"Hermes LiteLLM models discovered: {len(discovered_models)}")


if __name__ == "__main__":
    main()
