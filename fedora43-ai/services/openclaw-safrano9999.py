#!/usr/bin/env python3
"""Install and register the safrano9999 OpenClaw plugins inside fedora43-ai."""

from __future__ import annotations

import json
import os
from pathlib import Path

from openclaw_common import openclaw_cmd, refresh_plugin_registry
from safrano9999_plugins import (
    DEFAULT_CRONTAB_SPEC,
    disable_plugin_command_auth,
    install_openclaw_plugins,
    install_openclaw_crontab,
    register_openclaw_plugins,
)


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
PLUGINS_DIR = Path(os.environ.get("OPENCLAW_SAFRANO9999_DIR", "/opt/safrano9999"))
RUNTIME_ENV_PATH = Path(os.environ.get("SAFRANO9999_RUNTIME_ENV", "/run/safrano9999-openclaw.env"))
RUNTIME_CONF_PATH = Path(os.environ.get("SAFRANO9999_RUNTIME_CONF", "/run/safrano9999-openclaw.conf"))

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


def _crontab_spec(env: dict[str, str]) -> str:
    if env.get("OPENCLAW_CRONTAB") or env.get("SAFRANO9999_ROUTINES_CRONTAB"):
        return env.get("OPENCLAW_CRONTAB") or env.get("SAFRANO9999_ROUTINES_CRONTAB", "")
    image_default = PLUGINS_DIR / ".openclaw-crontab"
    if image_default.exists():
        return image_default.read_text(encoding="utf-8").strip()
    return DEFAULT_CRONTAB_SPEC


def main() -> None:
    env = _pid1_env()
    runtime_values = _wanted_env(env)
    _write_key_value_file(RUNTIME_ENV_PATH, runtime_values)
    _write_key_value_file(RUNTIME_CONF_PATH, runtime_values)

    installed = install_openclaw_plugins(PLUGINS_DIR, openclaw_cmd, links=True)
    disable_plugin_command_auth(PLUGINS_DIR, log_prefix="OpenClaw safrano9999 command auth disabled")

    if not CONFIG_PATH.exists():
        raise SystemExit(f"OpenClaw config missing after openclaw-config.service: {CONFIG_PATH}")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    registered = register_openclaw_plugins(
        config,
        PLUGINS_DIR,
        runtime_env_path=RUNTIME_ENV_PATH,
        runtime_conf_path=RUNTIME_CONF_PATH,
        telegram_target=env.get("OPENCLAW_TELEGRAM_TARGET", ""),
    )
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    crons = install_openclaw_crontab(
        CONFIG_PATH.parent,
        _crontab_spec(env),
        default_tz=env.get("SAFRANO9999_ROUTINES_TZ", "Europe/Vienna"),
    )
    refresh_plugin_registry()

    print(f"OpenClaw safrano9999 plugins installed: {', '.join(installed)}")
    print(f"OpenClaw safrano9999 plugins registered: {', '.join(registered)}")
    print(f"OpenClaw safrano9999 cronjobs written: {', '.join(crons)}")
    print(f"OpenClaw safrano9999 runtime env: {RUNTIME_ENV_PATH}")


if __name__ == "__main__":
    main()
