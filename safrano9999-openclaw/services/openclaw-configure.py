#!/usr/bin/env python3
"""Configure OpenClaw for the safcontainer plugin gateway.

This stays intentionally small:
- no OpenClaw LLM provider by default
- normal OpenClaw commands/channels stay available
- install the four plugin paths and the two container-only aliases
"""

import json
import os
import shutil
import subprocess
from pathlib import Path


CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json"))
GATEWAY_PORT = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "18789") or "18789")
PLUGINS_DIR = Path(os.environ.get("OPENCLAW_PLUGINS_DIR", "/opt/safrano9999-openclaw"))

PLUGIN_IDS = {
    "DAILYNEWS": "dailynews",
    "CALENDAR": "calendar",
    "ZEROINBOX": "zeroinbox",
    "KACHELMANN": "kachelmann",
}

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
        const payload = await runZeroinbox(api, { raw });
        return { text: payload.text ?? "ZEROINBOX done." };
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

CONTAINER_ONLY_EXTRA_COMMANDS = {
    "KACHELMANN": [
        (
            "start",
            """    api.registerCommand({
      name: "start",
      description: "Show the safcontainer OpenClaw commands.",
      acceptsArgs: false,
      requireAuth: false,
      channels: ["telegram"],
      handler: async () => ({
        text: [
          "OpenClaw Gateway ready.",
          "",
          "/dailynews",
          "/calendar",
          "/zeroinbox",
          "/mails",
          "/kachelmann",
          "/routines",
          "",
          "OpenClaw:",
          "/status",
          "/help",
          "/commands",
          "/tools",
        ].join("\\n"),
      }),
    });
""",
        ),
    ],
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


def _env_ref(name: str) -> dict:
    return {
        "source": "env",
        "provider": "default",
        "id": name,
    }


def _ensure_openclaw_config() -> None:
    if CONFIG_PATH.exists() and CONFIG_PATH.stat().st_size > 0:
        return
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        _openclaw_cmd(
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-health",
            "--auth-choice",
            "skip",
            "--skip-daemon",
            "--skip-search",
            "--gateway-auth",
            "token",
            "--gateway-token-ref-env",
            "OPENCLAW_GATEWAY_TOKEN",
            "--gateway-bind",
            "lan",
            "--gateway-port",
            str(GATEWAY_PORT),
            "--suppress-gateway-token-output",
        ),
        check=True,
    )


def _configure_gateway(config: dict) -> None:
    gateway = config.setdefault("gateway", {})
    gateway["mode"] = "local"
    gateway["bind"] = "lan"
    gateway["port"] = GATEWAY_PORT
    control_ui = gateway.setdefault("controlUi", {})
    control_ui["allowInsecureAuth"] = True
    control_ui["dangerouslyDisableDeviceAuth"] = True
    origins = control_ui.setdefault("allowedOrigins", [])
    for origin in (
        f"http://127.0.0.1:{GATEWAY_PORT}",
        f"http://localhost:{GATEWAY_PORT}",
        f"http://127.0.0.1:{os.environ.get('OPENCLAW_GATEWAY_PUBLISH_PORT', GATEWAY_PORT)}",
        f"http://localhost:{os.environ.get('OPENCLAW_GATEWAY_PUBLISH_PORT', GATEWAY_PORT)}",
    ):
        if origin not in origins:
            origins.append(origin)
    if os.environ.get("OPENCLAW_GATEWAY_TOKEN", "").strip():
        gateway["auth"] = {
            "mode": "token",
            "token": _env_ref("OPENCLAW_GATEWAY_TOKEN"),
        }


def _configure_telegram(config: dict) -> bool:
    if not os.environ.get("TELEGRAMTOKEN_OPENCLAW", "").strip():
        return False
    token_ref = _env_ref("TELEGRAMTOKEN_OPENCLAW")
    telegram = config.setdefault("channels", {}).setdefault("telegram", {})
    telegram["enabled"] = True
    telegram["botToken"] = token_ref
    telegram["capabilities"] = {"inlineButtons": "dm"}
    telegram["commands"] = {
        "native": False,
        "nativeSkills": False,
    }
    telegram["dmPolicy"] = "open"
    telegram["allowFrom"] = ["*"]
    telegram["groupPolicy"] = "open"
    telegram["groupAllowFrom"] = ["*"]
    telegram["streaming"] = {"mode": "off"}
    telegram["network"] = {
        "autoSelectFamily": False,
        "dnsResultOrder": "ipv4first",
    }
    telegram["execApprovals"] = {
        "enabled": False,
        "approvers": [],
        "agentFilter": ["main"],
        "target": "dm",
    }
    telegram["accounts"] = {
        "default": {
            "name": "main",
            "enabled": True,
            "dmPolicy": "open",
            "allowFrom": ["*"],
            "botToken": token_ref,
            "groupPolicy": "open",
            "groupAllowFrom": ["*"],
            "streaming": {"mode": "partial"},
        }
    }
    telegram["defaultAccount"] = "default"
    return True


def _configure_main_agent(config: dict) -> None:
    agents = config.setdefault("agents", {})
    agent_list = agents.setdefault("list", [])
    main = next((entry for entry in agent_list if entry.get("id") == "main"), None)
    if main is None:
        main = {"id": "main"}
        agent_list.insert(0, main)
    main["heartbeat"] = {
        "every": "360m",
        "target": "last",
        "directPolicy": "allow",
    }
    main["tools"] = {"allow": ["*"], "deny": []}


def _register_plugins(config: dict) -> list[str]:
    plugins = config.setdefault("plugins", {})
    paths = plugins.setdefault("load", {}).setdefault("paths", [])
    entries = plugins.setdefault("entries", {})
    registered: list[str] = []

    for repo, plugin_id in PLUGIN_IDS.items():
        repo_path = str(PLUGINS_DIR / repo)
        if repo_path not in paths:
            paths.append(repo_path)
        entries.setdefault(plugin_id, {})["enabled"] = True
        registered.append(plugin_id)
    return registered


def _refresh_plugin_registry() -> None:
    subprocess.run(_openclaw_cmd("plugins", "registry", "--refresh"), check=True)


def _apply_container_only_command_aliases() -> None:
    for repo, (command_name, alias) in CONTAINER_ONLY_COMMAND_ALIASES.items():
        plugin_file = PLUGINS_DIR / repo / "index.js"
        if not plugin_file.exists():
            continue

        source = plugin_file.read_text(encoding="utf-8")
        source = source.replace(f'      nativeNames: {{ telegram: "{alias}" }},\n', "")
        if f'name: "{alias}"' in source:
            plugin_file.write_text(source, encoding="utf-8")
            continue

        needle = f'      name: "{command_name}",\n'
        command_start = source.find(needle)
        command_end = source.find("    });\n", command_start)
        alias_block = CONTAINER_ONLY_ALIAS_BLOCKS.get(repo)
        if command_start == -1 or command_end == -1 or not alias_block:
            print(f"OpenClaw container alias skipped: /{alias}")
            continue

        insert_at = command_end + len("    });\n")
        plugin_file.write_text(source[:insert_at] + alias_block + source[insert_at:], encoding="utf-8")
        print(f"OpenClaw container alias enabled: /{alias} -> /{command_name}")


def _apply_container_only_extra_commands() -> None:
    for repo, commands in CONTAINER_ONLY_EXTRA_COMMANDS.items():
        plugin_file = PLUGINS_DIR / repo / "index.js"
        if not plugin_file.exists():
            continue

        source = plugin_file.read_text(encoding="utf-8")
        changed = False
        for command_name, command_block in commands:
            if f'name: "{command_name}"' in source:
                continue

            register_marker = "    api.registerCommand({\n"
            insert_at = source.find(register_marker)
            if insert_at == -1:
                print(f"OpenClaw container command skipped: /{command_name}")
                continue

            source = source[:insert_at] + command_block + source[insert_at:]
            changed = True
            print(f"OpenClaw container command enabled: /{command_name}")

        if changed:
            plugin_file.write_text(source, encoding="utf-8")


def _disable_plugin_command_auth() -> None:
    for repo in PLUGIN_IDS:
        plugin_file = PLUGINS_DIR / repo / "index.js"
        if not plugin_file.exists():
            continue
        source = plugin_file.read_text(encoding="utf-8")
        patched = source.replace("      requireAuth: true,", "      requireAuth: false,")
        if patched != source:
            plugin_file.write_text(patched, encoding="utf-8")
            print(f"OpenClaw container command auth disabled: {repo}")


def main() -> None:
    _ensure_openclaw_config()
    _apply_container_only_command_aliases()
    _apply_container_only_extra_commands()
    _disable_plugin_command_auth()

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    _configure_gateway(config)
    telegram_configured = _configure_telegram(config)
    _configure_main_agent(config)
    registered = _register_plugins(config)
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    _refresh_plugin_registry()

    print("OpenClaw model provider intentionally not configured")
    if telegram_configured:
        print("OpenClaw Telegram configured")
    print(f"OpenClaw plugins registered: {', '.join(registered)}")


# OpenClaw LiteLLM provider stays disabled here. If you want to enable it later,
# add the same provider/baseUrl/apiKey mapping used by fedora43-ai, but keep it
# commented by default in this container.


if __name__ == "__main__":
    main()
