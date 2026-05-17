#!/usr/bin/env python3
"""Configure OpenClaw's LiteLLM model after `openclaw onboard` rewrites config."""

import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
DEFAULT_MODEL = "deepseek-v4-flash"
DISCOVERY_TIMEOUT_SECONDS = 5
VIKAI_BOOTSTRAP_SCRIPT = Path("/usr/local/bin/vikai-bootstrap-openclaw-agents")
VIKAI_TOKEN_ENV = ("TOKEN_WORKER", "TOKEN_ARCHITECT", "TOKEN_QC")


def _int_env(name: str, default: int) -> int:
    value = os.environ.get(name, "").strip()
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _litellm_base_url() -> str:
    raw_url = os.environ.get("LITELLM_URL", "").strip()
    port = os.environ.get("LITELLM_PORT", "").strip()
    if not raw_url or not port:
        return ""

    base = raw_url.rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3].rstrip("/")
    return f"{base}:{port}/v1"


def _discover_litellm_models(fallback_model: str) -> tuple[list[str], bool]:
    base_url = _litellm_base_url()
    api_key = os.environ.get("LITELLM_API_KEY", "").strip()
    models = [fallback_model]
    if not base_url or not api_key:
        return models, False

    request = urllib.request.Request(
        f"{base_url}/models",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=DISCOVERY_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        print(f"OpenClaw LiteLLM model discovery skipped: {exc}")
        return models, False

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

    for model_id in discovered:
        if model_id not in models:
            models.append(model_id)
    return models, bool(discovered)


def _maybe_bootstrap_vikai_agents() -> bool:
    present = [name for name in VIKAI_TOKEN_ENV if os.environ.get(name, "").strip()]
    if not present:
        return False
    missing = [name for name in VIKAI_TOKEN_ENV if name not in present]
    if missing:
        raise SystemExit(
            "VikAI agent bootstrap requires TOKEN_WORKER, TOKEN_ARCHITECT, "
            f"and TOKEN_QC; missing: {', '.join(missing)}"
        )
    subprocess.run([str(VIKAI_BOOTSTRAP_SCRIPT)], check=True)
    return True


def main() -> None:
    model = os.environ.get("OPENCLAW_LITELLM_MODEL", DEFAULT_MODEL).strip()
    if model.startswith("litellm/"):
        model = model.removeprefix("litellm/")
    if not model:
        raise SystemExit("OPENCLAW_LITELLM_MODEL must not be empty")

    full_model = f"litellm/{model}"
    discovered_models, discovery_ok = _discover_litellm_models(model)
    model_name = os.environ.get("OPENCLAW_LITELLM_MODEL_NAME", model).strip() or model
    context_window = _int_env("OPENCLAW_LITELLM_CONTEXT_WINDOW", 128000)
    max_tokens = _int_env("OPENCLAW_LITELLM_MAX_TOKENS", 8192)

    config = json.loads(CONFIG_PATH.read_text())

    provider = (
        config.setdefault("models", {})
        .setdefault("providers", {})
        .setdefault("litellm", {})
    )
    provider["request"] = {"allowPrivateNetwork": True}

    models = provider.setdefault("models", [])
    existing_model_ids = {
        item.get("id")
        for item in models
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    for discovered_model in discovered_models:
        if discovered_model in existing_model_ids:
            continue
        models.append(
            {
                "id": discovered_model,
                "name": model_name if discovered_model == model else discovered_model,
                "reasoning": True,
                "input": ["text"],
                "contextWindow": context_window,
                "maxTokens": max_tokens,
            }
        )
        existing_model_ids.add(discovered_model)

    defaults = config.setdefault("agents", {}).setdefault("defaults", {})
    defaults.setdefault("model", {})["primary"] = full_model
    default_models = defaults.setdefault("models", {})
    for discovered_model in discovered_models:
        default_models.setdefault(
            f"litellm/{discovered_model}",
            {"alias": model_name if discovered_model == model else discovered_model},
        )

    telegram_token = os.environ.get("TELEGRAMTOKEN_OPENCLAW", "").strip()
    if telegram_token:
        telegram = config.setdefault("channels", {}).setdefault("telegram", {})
        telegram["enabled"] = True
        telegram["botToken"] = {
            "source": "env",
            "provider": "default",
            "id": "TELEGRAMTOKEN_OPENCLAW",
        }
        telegram["dmPolicy"] = "open"
        telegram["allowFrom"] = ["*"]
        telegram["groupPolicy"] = "open"
        telegram["groupAllowFrom"] = ["*"]
        telegram["groups"] = {"*": {"requireMention": False}}

        bindings = config.setdefault("bindings", [])
        telegram_main_binding = {
            "type": "route",
            "match": {"channel": "telegram", "accountId": "default"},
            "agentId": "main",
            "session": {"dmScope": "main"},
        }
        existing_binding = next(
            (
                item
                for item in bindings
                if isinstance(item, dict)
                and item.get("match") == telegram_main_binding["match"]
                and item.get("agentId") == "main"
            ),
            None,
        )
        if existing_binding is None:
            bindings.append(telegram_main_binding)
        else:
            existing_binding["type"] = "route"
            existing_binding.setdefault("session", {})["dmScope"] = "main"

    brave_api_key = os.environ.get("BRAVE_API_KEY", "").strip()
    if brave_api_key:
        web_search = (
            config.setdefault("tools", {})
            .setdefault("web", {})
            .setdefault("search", {})
        )
        web_search["enabled"] = True
        web_search["provider"] = "brave"

        brave_web_search = (
            config.setdefault("plugins", {})
            .setdefault("entries", {})
            .setdefault("brave", {})
            .setdefault("config", {})
            .setdefault("webSearch", {})
        )
        brave_web_search["apiKey"] = {
            "source": "env",
            "provider": "default",
            "id": "BRAVE_API_KEY",
        }

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    vikai_bootstrapped = _maybe_bootstrap_vikai_agents()
    print(f"OpenClaw LiteLLM model configured: {full_model}")
    if discovery_ok:
        print(f"OpenClaw LiteLLM models discovered: {len(discovered_models)}")
    if telegram_token:
        print("OpenClaw Telegram configured for default account -> main agent")
    if brave_api_key:
        print("OpenClaw Brave web search configured from BRAVE_API_KEY")
    if vikai_bootstrapped:
        print("OpenClaw VikAI agents configured from TOKEN_WORKER/TOKEN_ARCHITECT/TOKEN_QC")


if __name__ == "__main__":
    main()
