#!/usr/bin/env python3
"""Configure OpenClaw before starting the gateway."""

import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
DEFAULT_MODEL = "deepseek-v4-flash"
DISCOVERY_TIMEOUT_SECONDS = 5
OPENCLAW_GATEWAY_INTERNAL_PORT = 18789
OPENCLAW_GATEWAY_HOST_PORT = 20789
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


def _ensure_openclaw_config() -> None:
    if CONFIG_PATH.exists() and CONFIG_PATH.stat().st_size > 0:
        return

    api_key = os.environ.get("LITELLM_API_KEY", "").strip()
    base_url = _litellm_base_url()
    if not api_key or not base_url:
        raise SystemExit("OpenClaw onboarding needs LITELLM_API_KEY, LITELLM_URL, and LITELLM_PORT")

    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "openclaw",
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-health",
            "--auth-choice",
            "litellm-api-key",
            "--litellm-api-key",
            api_key,
            "--custom-base-url",
            base_url,
        ],
        check=True,
    )


def _origin(host: str, port: int) -> str:
    if ":" in host and not host.startswith("["):
        host = f"[{host}]"
    return f"http://{host}:{port}"


def _tailscale_hosts() -> list[str]:
    hosts: list[str] = []
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        payload = json.loads(result.stdout)
    except (
        FileNotFoundError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        json.JSONDecodeError,
    ):
        payload = {}

    self_info = payload.get("Self") if isinstance(payload, dict) else {}
    if isinstance(self_info, dict):
        dns_name = str(self_info.get("DNSName") or "").strip().rstrip(".")
        if dns_name:
            hosts.append(dns_name)
        for ip_addr in self_info.get("TailscaleIPs") or []:
            ip_addr = str(ip_addr).strip()
            if ip_addr:
                hosts.append(ip_addr)

    ts_hostname = os.environ.get("TS_HOSTNAME", "").strip().rstrip(".")
    if "." in ts_hostname:
        hosts.append(ts_hostname)

    return list(dict.fromkeys(hosts))


def _control_ui_allowed_origins() -> list[str]:
    host = os.environ.get("HOST", "127.0.0.1").strip() or "127.0.0.1"
    origins = [
        _origin(host, OPENCLAW_GATEWAY_INTERNAL_PORT),
        _origin(host, OPENCLAW_GATEWAY_HOST_PORT),
    ]
    for tailscale_host in _tailscale_hosts():
        origins.extend(
            [
                _origin(tailscale_host, OPENCLAW_GATEWAY_INTERNAL_PORT),
                _origin(tailscale_host, OPENCLAW_GATEWAY_HOST_PORT),
            ]
        )
    return list(dict.fromkeys(origins))


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


def _openclaw_model_entry(
    model_id: str,
    primary_model: str,
    primary_name: str,
    context_window: int,
    max_tokens: int,
) -> dict:
    return {
        "id": model_id,
        "name": primary_name if model_id == primary_model else model_id,
        "reasoning": True,
        "input": ["text"],
        "contextWindow": context_window,
        "maxTokens": max_tokens,
    }


def _ensure_main_agent(config: dict) -> None:
    agents = config.setdefault("agents", {})
    defaults = agents.setdefault("defaults", {})
    default_workspace = str(CONFIG_PATH.parent / "workspace")
    defaults.setdefault("workspace", default_workspace)

    agent_list = agents.setdefault("list", [])
    main_entry = next(
        (item for item in agent_list if isinstance(item, dict) and item.get("id") == "main"),
        None,
    )
    if main_entry is None:
        main_entry = {"id": "main", "name": "main"}
    else:
        agent_list.remove(main_entry)

    main_entry["name"] = main_entry.get("name") or "main"
    main_entry["workspace"] = main_entry.get("workspace") or default_workspace
    main_entry["agentDir"] = main_entry.get("agentDir") or str(
        CONFIG_PATH.parent / "agents" / "main" / "agent"
    )
    main_entry["default"] = True
    main_entry.pop("models", None)
    agent_list.insert(0, main_entry)

    for entry in agent_list[1:]:
        if isinstance(entry, dict):
            entry.pop("default", None)

    Path(main_entry["workspace"]).mkdir(parents=True, exist_ok=True)
    Path(main_entry["agentDir"]).mkdir(parents=True, exist_ok=True)


def _remove_model_allowlists(config: dict) -> None:
    agents = config.setdefault("agents", {})
    defaults = agents.setdefault("defaults", {})
    defaults.pop("models", None)


def _merge_litellm_models(
    provider: dict,
    discovered_models: list[str],
    primary_model: str,
    primary_name: str,
    context_window: int,
    max_tokens: int,
) -> list[dict]:
    merged: dict[str, dict] = {}
    for item in provider.get("models", []):
        if not isinstance(item, dict):
            continue
        model_id = item.get("id")
        if isinstance(model_id, str) and model_id:
            merged[model_id] = item

    for model_id in discovered_models:
        existing = merged.get(model_id, {})
        entry = _openclaw_model_entry(
            model_id,
            primary_model,
            primary_name,
            context_window,
            max_tokens,
        )
        entry.update(existing)
        entry["id"] = model_id
        merged[model_id] = entry

    return list(merged.values())


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
    _ensure_openclaw_config()

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
    _ensure_main_agent(config)

    gateway = config.setdefault("gateway", {})
    gateway["mode"] = "local"
    gateway["bind"] = "lan"
    gateway["port"] = OPENCLAW_GATEWAY_INTERNAL_PORT
    control_ui = gateway.setdefault("controlUi", {})
    control_ui["allowedOrigins"] = _control_ui_allowed_origins()
    control_ui["dangerouslyDisableDeviceAuth"] = True
    control_ui.pop("dangerouslyAllowHostHeaderOriginFallback", None)

    models_config = config.setdefault("models", {})
    models_config["mode"] = "merge"
    provider = (
        models_config
        .setdefault("providers", {})
        .setdefault("litellm", {})
    )
    provider["baseUrl"] = _litellm_base_url()
    provider["api"] = "openai-completions"
    provider["apiKey"] = {
        "source": "env",
        "provider": "default",
        "id": "LITELLM_API_KEY",
    }
    provider["request"] = {"allowPrivateNetwork": True}

    provider["models"] = _merge_litellm_models(
        provider,
        discovered_models,
        model,
        model_name,
        context_window,
        max_tokens,
    )

    defaults = config.setdefault("agents", {}).setdefault("defaults", {})
    defaults.setdefault("model", {})["primary"] = full_model
    _remove_model_allowlists(config)

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
        bindings[:] = [
            item
            for item in bindings
            if not (
                isinstance(item, dict)
                and item.get("match") == telegram_main_binding["match"]
            )
        ]
        bindings.append(telegram_main_binding)

    if telegram_token:
        commands = config.setdefault("commands", {})
        commands["ownerAllowFrom"] = ["*"]

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
        print(
            "OpenClaw LiteLLM models discovered: "
            f"{len(discovered_models)}; models written: {len(provider['models'])}"
        )
    if telegram_token:
        print("OpenClaw Telegram configured for default account -> main agent")
    if telegram_token:
        print("OpenClaw Telegram command owners allowed for all Telegram senders")
    if brave_api_key:
        print("OpenClaw Brave web search configured from BRAVE_API_KEY")
    print(
        "OpenClaw Control UI origins configured: "
        + ", ".join(control_ui["allowedOrigins"])
    )
    if vikai_bootstrapped:
        print("OpenClaw VikAI agents configured from TOKEN_WORKER/TOKEN_ARCHITECT/TOKEN_QC")


if __name__ == "__main__":
    main()
