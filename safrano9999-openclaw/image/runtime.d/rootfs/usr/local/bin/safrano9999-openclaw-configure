#!/usr/bin/env python3
"""Register only the additional safcontainer plugins and command aliases."""

import json
import os
from pathlib import Path

from openclaw_common import (
    refresh_plugin_registry,
)
from safrano9999_plugins import (
    disable_plugin_command_auth,
    register_openclaw_plugins,
)


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
PLUGINS_DIR = Path(os.environ.get("OPENCLAW_PLUGINS_DIR", str(CONFIG_PATH.parent / "extensions")))

CONTAINER_ONLY_COMMAND_ALIASES = {
    "ZEROINBOX": ("zeroinbox", "mails"),
    "KACHELMANN": ("kachelmann", "routines"),
}

CONTAINER_ONLY_ALIAS_BLOCKS = {
    "ZEROINBOX": """    api.registerCommand({
      name: "mails",
      description: "Alias for /zeroinbox in this container.",
      acceptsArgs: true,
      requireAuth: false,
      handler: async (ctx) => {
        const raw = readString(ctx?.args) ?? "";
        return runZeroinboxCommand(api, raw);
      },
    });
""",
    "KACHELMANN": """    api.registerCommand({
      name: "routines",
      description: "Alias for /kachelmann in this container.",
      acceptsArgs: true,
      requireAuth: false,
      handler: async (ctx) => {
        const raw = ctx.args ?? "";
        if (["status", "reminder"].includes(raw.trim().toLowerCase())) {
          return { text: await runKachelmannStatus(api) };
        }
        return createKachelmannReply(await runKachelmann(api, { raw }));
      },
    });
""",
}

def _apply_container_only_command_aliases() -> None:
    for repo, (command_name, alias) in CONTAINER_ONLY_COMMAND_ALIASES.items():
        plugin_id = command_name
        candidates = (
            PLUGINS_DIR / repo / "index.js",
            CONFIG_PATH.parent / "extensions" / plugin_id / "index.js",
        )
        for plugin_file in candidates:
            if not plugin_file.exists():
                continue
            source = plugin_file.read_text(encoding="utf-8")
            source = source.replace(f'      nativeNames: {{ telegram: "{alias}" }},\n', "")
            if f'name: "{alias}"' not in source:
                needle = f'      name: "{command_name}",\n'
                command_start = source.find(needle)
                command_end = source.find("    });\n", command_start)
                alias_block = CONTAINER_ONLY_ALIAS_BLOCKS.get(repo)
                if command_start == -1 or command_end == -1 or not alias_block:
                    print(f"OpenClaw container alias skipped: /{alias} ({plugin_file})")
                    continue
                insert_at = command_end + len("    });\n")
                source = source[:insert_at] + alias_block + source[insert_at:]
            plugin_file.write_text(source, encoding="utf-8")
        print(f"OpenClaw container alias enabled: /{alias} -> /{command_name}")


def main() -> None:
    if not CONFIG_PATH.is_file() or not CONFIG_PATH.stat().st_size:
        raise SystemExit(
            "OpenClaw config is missing after openclaw-ephemeral.py configure"
        )
    _apply_container_only_command_aliases()
    disable_plugin_command_auth(PLUGINS_DIR, log_prefix="OpenClaw container command auth disabled")

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    registered = register_openclaw_plugins(
        config,
        PLUGINS_DIR,
        telegram_target=os.environ.get("OPENCLAW_TELEGRAM_CHAT_ID", ""),
    )
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    refresh_plugin_registry()

    print(f"OpenClaw plugins registered: {', '.join(registered)}")


if __name__ == "__main__":
    main()
