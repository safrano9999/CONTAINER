#!/usr/bin/env python3
"""Unit checks for the shared ephemeral MCP projection."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

import yaml


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "image/runtime.d/agent-mcp-ephemeral.py"
)
SPEC = importlib.util.spec_from_file_location("agent_mcp_ephemeral", SOURCE)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def expect_configuration_error(environ: dict[str, str], fragment: str) -> None:
    try:
        MODULE.discover_mcp_servers(environ)
    except MODULE.ConfigurationError as error:
        assert fragment in str(error), str(error)
    else:
        raise AssertionError(f"expected ConfigurationError containing {fragment!r}")


def main() -> int:
    environ = {
        "MCP_SERVER_NAME": "",
        "MCP_SERVER_URL": "http://kachelmann-mcp.dns.podman:11041/mcp",
        "MCP_SERVER_BEARER": "first-secret",
        "MCP_SERVER_NAME_02": "paperless-mcp",
        "MCP_SERVER_URL_02": "http://paperless-mcp:5000/mcp",
        "MCP_SERVER_BEARER_02": "",
        # A stray optional value without a URL does not configure a server.
        "MCP_SERVER_NAME_03": "ignored-without-url",
    }
    servers = MODULE.discover_mcp_servers(environ)
    assert [server.name for server in servers] == [
        "kachelmann-mcp",
        "paperless-mcp",
    ]
    assert servers[0].bearer_env == "MCP_SERVER_BEARER"
    assert servers[1].bearer_env is None

    with tempfile.TemporaryDirectory(prefix="agent-mcp-ephemeral-test.") as raw:
        root = Path(raw)
        openclaw = root / "openclaw.json"
        hermes = root / "config.yaml"
        openclaw.write_text(
            json.dumps(
                {
                    "agents": {"list": [{"id": "main"}]},
                    "mcp": {"sessionIdleTtlMs": 1234},
                }
            ),
            encoding="utf-8",
        )
        hermes.write_text("model:\n  provider: test\n", encoding="utf-8")

        MODULE.configure_openclaw(openclaw, servers)
        MODULE.configure_hermes(hermes, servers)

        openclaw_text = openclaw.read_text(encoding="utf-8")
        hermes_text = hermes.read_text(encoding="utf-8")
        assert "first-secret" not in openclaw_text
        assert "first-secret" not in hermes_text
        assert "Bearer ${MCP_SERVER_BEARER}" in openclaw_text
        assert "Bearer ${MCP_SERVER_BEARER}" in hermes_text
        assert (openclaw.stat().st_mode & 0o777) == 0o600
        assert (hermes.stat().st_mode & 0o777) == 0o600

        openclaw_config = json.loads(openclaw_text)
        assert openclaw_config["mcp"]["sessionIdleTtlMs"] == 1234
        openclaw_servers = openclaw_config["mcp"]["servers"]
        assert set(openclaw_servers) == {"kachelmann-mcp", "paperless-mcp"}
        assert "toolFilter" not in openclaw_servers["kachelmann-mcp"]
        assert openclaw_servers["kachelmann-mcp"][
            "supportsParallelToolCalls"
        ] is True
        assert openclaw_servers["kachelmann-mcp"]["codex"][
            "defaultToolsApprovalMode"
        ] == "approve"
        assert "headers" not in openclaw_servers["paperless-mcp"]

        hermes_config = yaml.safe_load(hermes_text)
        hermes_servers = hermes_config["mcp_servers"]
        assert set(hermes_servers) == {"kachelmann-mcp", "paperless-mcp"}
        assert "tools" not in hermes_servers["kachelmann-mcp"]
        assert hermes_servers["kachelmann-mcp"][
            "supports_parallel_tool_calls"
        ] is True
        assert "headers" not in hermes_servers["paperless-mcp"]

        MODULE.configure_openclaw(openclaw, ())
        MODULE.configure_hermes(hermes, ())
        openclaw_config = json.loads(openclaw.read_text(encoding="utf-8"))
        hermes_config = yaml.safe_load(hermes.read_text(encoding="utf-8"))
        assert "servers" not in openclaw_config["mcp"]
        assert "mcp_servers" not in hermes_config

    expect_configuration_error(
        {"MCP_SERVER_URL": "ftp://invalid.example/mcp"},
        "http(s) URL",
    )
    expect_configuration_error(
        {
            "MCP_SERVER_NAME": "duplicate",
            "MCP_SERVER_URL": "http://one.example/mcp",
            "MCP_SERVER_NAME_02": "DUPLICATE",
            "MCP_SERVER_URL_02": "http://two.example/mcp",
        },
        "duplicate MCP server name",
    )
    expect_configuration_error(
        {
            "MCP_SERVER_URL": "http://one.example/mcp",
            "MCP_SERVER_BEARER": "Bearer already-prefixed",
        },
        "without 'Bearer '",
    )
    print("agent MCP ephemeral tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
