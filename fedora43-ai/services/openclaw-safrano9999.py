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


def _crontab_spec(env: dict[str, str]) -> str:
    if env.get("OPENCLAW_CRONTAB") or env.get("SAFRANO9999_ROUTINES_CRONTAB"):
        return env.get("OPENCLAW_CRONTAB") or env.get("SAFRANO9999_ROUTINES_CRONTAB", "")
    image_default = PLUGINS_DIR / ".openclaw-crontab"
    if image_default.exists():
        return image_default.read_text(encoding="utf-8").strip()
    return DEFAULT_CRONTAB_SPEC


def main() -> None:
    env = dict(os.environ)

    installed = install_openclaw_plugins(PLUGINS_DIR, openclaw_cmd, links=True)
    disable_plugin_command_auth(PLUGINS_DIR, log_prefix="OpenClaw safrano9999 command auth disabled")

    if not CONFIG_PATH.exists():
        raise SystemExit(f"OpenClaw config missing after openclaw-config.service: {CONFIG_PATH}")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    registered = register_openclaw_plugins(
        config,
        PLUGINS_DIR,
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


if __name__ == "__main__":
    main()
