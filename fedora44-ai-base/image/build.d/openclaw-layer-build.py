#!/usr/bin/env python3
"""Install and register one image layer's OpenClaw plugin contributions."""

import argparse
import json
import os
from pathlib import Path

from openclaw_common import openclaw_cmd, refresh_plugin_registry
from safrano9999_plugins import (
    disable_plugin_command_auth,
    install_openclaw_plugins,
    register_openclaw_plugins,
)


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
PLUGINS_DIR = Path(os.environ.get("OPENCLAW_SAFRANO9999_DIR", "/opt/safrano9999"))


def _plugin_repositories(repositories: list[str]) -> list[str]:
    return [
        repository
        for repository in repositories
        if (PLUGINS_DIR / repository / "openclaw.plugin.json").is_file()
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repos", nargs="+", required=True)
    args = parser.parse_args()
    plugins = _plugin_repositories(args.repos)

    installed = install_openclaw_plugins(
        PLUGINS_DIR,
        openclaw_cmd,
        links=True,
        plugin_names=plugins,
    )
    disable_plugin_command_auth(
        PLUGINS_DIR,
        log_prefix="OpenClaw safrano9999 command auth disabled",
        plugin_names=plugins,
    )

    if not CONFIG_PATH.exists():
        raise SystemExit(f"OpenClaw config missing during image build: {CONFIG_PATH}")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    registered = register_openclaw_plugins(
        config,
        PLUGINS_DIR,
        plugin_names=plugins,
    )
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    refresh_plugin_registry()

    print(f"OpenClaw safrano9999 plugins installed: {', '.join(installed)}")
    print(f"OpenClaw safrano9999 plugins registered: {', '.join(registered)}")


if __name__ == "__main__":
    main()
