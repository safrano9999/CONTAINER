#!/usr/bin/env python3
"""Configure OpenClaw before starting the gateway.

Adapted from fedora43-ai/services/openclaw-configure.py: same gateway / LiteLLM
/ Telegram-to-main logic, trimmed to this container and extended to register the
four bundled plugins (DAILYNEWS, CALENDAR, ZEROINBOX, KACHELMANN).
"""

import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
DEFAULT_MODEL = "deepseek-v4-flash"
DISCOVERY_TIMEOUT_SECONDS = 5
GATEWAY_INTERNAL_PORT = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "18789") or "18789")
GATEWAY_HOST_PORT = int(os.environ.get("OPENCLAW_GATEWAY_PUBLISH_PORT", "") or GATEWAY_INTERNAL_PORT)

PLUGINS_DIR = Path(os.environ.get("OPENCLAW_PLUGINS_DIR", "/opt/safrano9999-openclaw"))
# repo dir name -> plugin id (matches each repo's openclaw.plugin.json "id")
PLUGIN_IDS = {
    "DAILYNEWS": "dailynews",
    "CALENDAR": "calendar",
    "ZEROINBOX": "zeroinbox",
    "KACHELMANN": "kachelmann",
}


def _openclaw_cmd(*args: str) -> list[str]:
    raw = os.environ.get("OPENCLAW_BIN", "").strip()
    if raw:
        base = raw.split()
    elif shutil.which("openclaw"):
        base = ["openclaw"]
    else:
        base = ["node", "/app/openclaw.mjs"]
    return [*base, *args]


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
        _openclaw_cmd(
            "onboard", "--non-interactive", "--accept-risk", "--skip-health",
            "--auth-choice", "litellm-api-key",
            "--litellm-api-key", api_key,
            "--custom-base-url", base_url,
        ),
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
            check=True, capture_output=True, text=True, timeout=3,
        )
        payload = json.loads(result.stdout)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
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
    origins = [_origin(host, GATEWAY_INTERNAL_PORT), _origin(host, GATEWAY_HOST_PORT)]
    for ts_host in _tailscale_hosts():
        origins.extend([_origin(ts_host, GATEWAY_INTERNAL_PORT), _origin(ts_host, GATEWAY_HOST_PORT)])
    return list(dict.fromkeys(origins))


def _discover_litellm_models(fallback_model: str) -> tuple[list[str], bool]:
    base_url = _litellm_base_url()
    api_key = os.environ.get("LITELLM_API_KEY", "").strip()
    models = [fallback_model]
    if not base_url or not api_key:
        return models, False
    request = urllib.request.Request(f"{base_url}/models", headers={"Authorization": f"Bearer {api_key}"})
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
        model_id = model_id.strip().removeprefix("litellm/")
        if model_id and model_id not in discovered:
            discovered.append(model_id)
    for model_id in discovered:
        if model_id not in models:
            models.append(model_id)
    return models, bool(discovered)


def _ensure_main_agent(config: dict) -> None:
    agents = config.setdefault("agents", {})
    defaults = agents.setdefault("defaults", {})
    default_workspace = str(CONFIG_PATH.parent / "workspace")
    defaults.setdefault("workspace", default_workspace)
    agent_list = agents.setdefault("list", [])
    main_entry = next((i for i in agent_list if isinstance(i, dict) and i.get("id") == "main"), None)
    if main_entry is None:
        main_entry = {"id": "main", "name": "main"}
    else:
        agent_list.remove(main_entry)
    main_entry["name"] = main_entry.get("name") or "main"
    main_entry["workspace"] = main_entry.get("workspace") or default_workspace
    main_entry["agentDir"] = main_entry.get("agentDir") or str(CONFIG_PATH.parent / "agents" / "main" / "agent")
    main_entry["default"] = True
    main_entry.pop("models", None)
    agent_list.insert(0, main_entry)
    for entry in agent_list[1:]:
        if isinstance(entry, dict):
            entry.pop("default", None)
    Path(main_entry["workspace"]).mkdir(parents=True, exist_ok=True)
    Path(main_entry["agentDir"]).mkdir(parents=True, exist_ok=True)


def _openclaw_model_entry(model_id, primary_model, primary_name, context_window, max_tokens) -> dict:
    return {
        "id": model_id,
        "name": primary_name if model_id == primary_model else model_id,
        "reasoning": True,
        "input": ["text"],
        "contextWindow": context_window,
        "maxTokens": max_tokens,
    }


def _merge_litellm_models(provider, discovered_models, primary_model, primary_name, context_window, max_tokens) -> list[dict]:
    merged: dict[str, dict] = {}
    for item in provider.get("models", []):
        if isinstance(item, dict) and isinstance(item.get("id"), str) and item["id"]:
            merged[item["id"]] = item
    for model_id in discovered_models:
        entry = _openclaw_model_entry(model_id, primary_model, primary_name, context_window, max_tokens)
        entry.update(merged.get(model_id, {}))
        entry["id"] = model_id
        merged[model_id] = entry
    return list(merged.values())


def _configure_telegram(config: dict) -> bool:
    token = os.environ.get("TELEGRAMTOKEN_OPENCLAW", "").strip()
    if not token:
        return False
    telegram = config.setdefault("channels", {}).setdefault("telegram", {})
    telegram["enabled"] = True
    telegram["botToken"] = {"source": "env", "provider": "default", "id": "TELEGRAMTOKEN_OPENCLAW"}
    telegram["dmPolicy"] = "open"
    telegram["allowFrom"] = ["*"]
    telegram["groupPolicy"] = "open"
    telegram["groupAllowFrom"] = ["*"]
    telegram["groups"] = {"*": {"requireMention": False}}

    binding = {
        "type": "route",
        "match": {"channel": "telegram", "accountId": "default"},
        "agentId": "main",
        "session": {"dmScope": "main"},
    }
    bindings = config.setdefault("bindings", [])
    bindings[:] = [b for b in bindings if not (isinstance(b, dict) and b.get("match") == binding["match"])]
    bindings.append(binding)
    config.setdefault("commands", {})["ownerAllowFrom"] = ["*"]
    return True


def _register_plugins(config: dict) -> list[str]:
    plugins = config.setdefault("plugins", {})
    paths = plugins.setdefault("load", {}).setdefault("paths", [])
    entries = plugins.setdefault("entries", {})
    target = os.environ.get("OPENCLAW_TELEGRAM_TARGET", "").strip()
    registered: list[str] = []
    for repo, pid in PLUGIN_IDS.items():
        repo_path = str(PLUGINS_DIR / repo)
        if repo_path not in paths:
            paths.append(repo_path)
        entry = entries.setdefault(pid, {})
        entry["enabled"] = True
        cfg = entry.setdefault("config", {})
        if pid == "calendar" and target:
            cfg["delivery"] = {"channel": "telegram", "target": target}
        if pid == "kachelmann" and target:
            cfg["statusDelivery"] = {"channel": "telegram", "target": target}
        registered.append(pid)
    return registered


def main() -> None:
    _ensure_openclaw_config()

    model = os.environ.get("OPENCLAW_LITELLM_MODEL", DEFAULT_MODEL).strip().removeprefix("litellm/")
    if not model:
        raise SystemExit("OPENCLAW_LITELLM_MODEL must not be empty")
    full_model = f"litellm/{model}"
    discovered_models, discovery_ok = _discover_litellm_models(model)
    model_name = os.environ.get("OPENCLAW_LITELLM_MODEL_NAME", model).strip() or model
    context_window = int(os.environ.get("OPENCLAW_LITELLM_CONTEXT_WINDOW", "") or 128000)
    max_tokens = int(os.environ.get("OPENCLAW_LITELLM_MAX_TOKENS", "") or 8192)

    config = json.loads(CONFIG_PATH.read_text())
    _ensure_main_agent(config)

    gateway = config.setdefault("gateway", {})
    gateway["mode"] = "local"
    gateway["bind"] = "lan"
    gateway["port"] = GATEWAY_INTERNAL_PORT
    control_ui = gateway.setdefault("controlUi", {})
    control_ui["allowedOrigins"] = _control_ui_allowed_origins()
    control_ui["dangerouslyDisableDeviceAuth"] = True

    if _litellm_base_url():
        models_config = config.setdefault("models", {})
        models_config["mode"] = "merge"
        provider = models_config.setdefault("providers", {}).setdefault("litellm", {})
        provider["baseUrl"] = _litellm_base_url()
        provider["api"] = "openai-completions"
        provider["apiKey"] = {"source": "env", "provider": "default", "id": "LITELLM_API_KEY"}
        provider["request"] = {"allowPrivateNetwork": True}
        provider["models"] = _merge_litellm_models(
            provider, discovered_models, model, model_name, context_window, max_tokens
        )
        config.setdefault("agents", {}).setdefault("defaults", {}).setdefault("model", {})["primary"] = full_model

    telegram_ok = _configure_telegram(config)
    registered = _register_plugins(config)

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")

    print(f"OpenClaw model configured: {full_model}")
    if discovery_ok:
        print(f"OpenClaw LiteLLM models discovered: {len(discovered_models)}")
    if telegram_ok:
        print("OpenClaw Telegram configured: default account -> main agent")
    print(f"OpenClaw plugins registered: {', '.join(registered)}")
    print("OpenClaw Control UI origins: " + ", ".join(control_ui["allowedOrigins"]))


if __name__ == "__main__":
    main()
