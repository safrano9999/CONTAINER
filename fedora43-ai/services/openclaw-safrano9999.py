#!/usr/bin/env python3
"""Install and register the safrano9999 OpenClaw plugins inside fedora43-ai."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

from openclaw_common import openclaw_cmd, refresh_plugin_registry


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
PLUGINS_DIR = Path(os.environ.get("OPENCLAW_SAFRANO9999_DIR", "/opt/safrano9999"))
RUNTIME_ENV_PATH = Path(os.environ.get("SAFRANO9999_RUNTIME_ENV", "/run/safrano9999-openclaw.env"))
RUNTIME_CONF_PATH = Path(os.environ.get("SAFRANO9999_RUNTIME_CONF", "/run/safrano9999-openclaw.conf"))

PLUGIN_IDS = {
    "DAILYNEWS": "dailynews",
    "CALENDAR": "calendar",
    "ZEROINBOX": "zeroinbox",
    "KACHELMANN": "kachelmann",
}

ENV_PREFIXES = (
    "CALENDAR",
    "DAILYNEWS",
    "DB_",
    "GEMINI_",
    "GOOGLE_",
    "KACHELMANN",
    "LITELLM_",
    "OPENAI_",
    "ZEROINBOX",
)


def _pid1_env() -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        raw = Path("/proc/1/environ").read_bytes()
    except OSError:
        raw = b""
    for item in raw.split(b"\0"):
        if not item or b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        values[key.decode("utf-8", "ignore")] = value.decode("utf-8", "ignore")
    values.update(os.environ)
    return values


def _wanted_env(values: dict[str, str]) -> dict[str, str]:
    wanted: dict[str, str] = {}
    for key, value in values.items():
        if not key or value == "":
            continue
        if key == "DATABASE_URL" or key.startswith(ENV_PREFIXES):
            wanted[key] = value
    return dict(sorted(wanted.items()))


def _write_key_value_file(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(f"{key}={value}\n" for key, value in values.items())
    path.write_text(content, encoding="utf-8")
    path.chmod(0o600)


def _install_plugins() -> list[str]:
    installed: list[str] = []
    for repo, plugin_id in PLUGIN_IDS.items():
        repo_path = PLUGINS_DIR / repo
        if not (repo_path / "openclaw.plugin.json").exists():
            raise SystemExit(f"Missing OpenClaw plugin repo: {repo_path}")
        subprocess.run(
            openclaw_cmd(
                "plugins",
                "install",
                "--link",
                "--dangerously-force-unsafe-install",
                str(repo_path),
            ),
            check=True,
        )
        installed.append(plugin_id)
    return installed


def _disable_command_auth() -> None:
    for repo in PLUGIN_IDS:
        plugin_file = PLUGINS_DIR / repo / "index.js"
        if not plugin_file.exists():
            continue
        source = plugin_file.read_text(encoding="utf-8")
        patched = source.replace("      requireAuth: true,", "      requireAuth: false,")
        if patched != source:
            plugin_file.write_text(patched, encoding="utf-8")
            print(f"OpenClaw safrano9999 command auth disabled: {repo}")


def _merge_plugin_config(entry: dict[str, Any], values: dict[str, Any]) -> None:
    config = entry.setdefault("config", {})
    for key, value in values.items():
        if isinstance(value, dict) and isinstance(config.get(key), dict):
            config[key].update(value)
        else:
            config[key] = value


def _register_plugins(config: dict[str, Any], env: dict[str, str]) -> list[str]:
    plugins = config.setdefault("plugins", {})
    paths = plugins.setdefault("load", {}).setdefault("paths", [])
    entries = plugins.setdefault("entries", {})
    registered: list[str] = []

    for repo, plugin_id in PLUGIN_IDS.items():
        repo_path = str(PLUGINS_DIR / repo)
        if repo_path not in paths:
            paths.append(repo_path)
        entry = entries.setdefault(plugin_id, {})
        entry["enabled"] = True
        registered.append(plugin_id)

    _merge_plugin_config(entries.setdefault("calendar", {}), {
        "calenvPath": str(RUNTIME_ENV_PATH),
        "envFile": str(RUNTIME_ENV_PATH),
        "logDir": "/var/log/safrano9999/calendar",
    })
    _merge_plugin_config(entries.setdefault("zeroinbox", {}), {
        "configPath": str(RUNTIME_CONF_PATH),
        "envFile": str(RUNTIME_ENV_PATH),
    })
    _merge_plugin_config(entries.setdefault("kachelmann", {}), {
        "envFile": str(RUNTIME_ENV_PATH),
    })

    telegram_target = env.get("OPENCLAW_TELEGRAM_TARGET", "").strip()
    if telegram_target:
        _merge_plugin_config(entries.setdefault("calendar", {}), {
            "delivery": {"channel": "telegram", "target": telegram_target},
        })
        _merge_plugin_config(entries.setdefault("kachelmann", {}), {
            "statusDelivery": {"channel": "telegram", "target": telegram_target},
        })
    return registered


def main() -> None:
    env = _pid1_env()
    runtime_values = _wanted_env(env)
    _write_key_value_file(RUNTIME_ENV_PATH, runtime_values)
    _write_key_value_file(RUNTIME_CONF_PATH, runtime_values)

    installed = _install_plugins()
    _disable_command_auth()

    if not CONFIG_PATH.exists():
        raise SystemExit(f"OpenClaw config missing after openclaw-config.service: {CONFIG_PATH}")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    registered = _register_plugins(config, env)
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    refresh_plugin_registry()

    print(f"OpenClaw safrano9999 plugins installed: {', '.join(installed)}")
    print(f"OpenClaw safrano9999 plugins registered: {', '.join(registered)}")
    print(f"OpenClaw safrano9999 runtime env: {RUNTIME_ENV_PATH}")


if __name__ == "__main__":
    main()
