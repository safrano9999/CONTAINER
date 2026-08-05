#!/usr/bin/env python3
"""Unit checks for the Hermes-owned ephemeral MCP projection."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


CORE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CORE.parent / "openclaw-ephemeral"))
SOURCE = CORE / "image/runtime.d/hermes-ephemeral.py"
SPEC = importlib.util.spec_from_file_location("hermes_ephemeral", SOURCE)
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
        "MCP_SERVER_NAME_03": "ignored-without-url",
    }
    config = MODULE.mcp_servers_config(environ)
    assert list(config) == ["kachelmann-mcp", "paperless-mcp"]

    kachelmann = config["kachelmann-mcp"]
    assert kachelmann["enabled"] is True
    assert kachelmann["supports_parallel_tool_calls"] is True
    assert "tools" not in kachelmann
    assert kachelmann["headers"]["Authorization"] == (
        "Bearer ${MCP_SERVER_BEARER}"
    )
    assert "headers" not in config["paperless-mcp"]
    assert "first-secret" not in json.dumps(config)
    assert MODULE.mcp_servers_config({"MCP_SERVER_NAME": "ignored"}) == {}

    expect_configuration_error(
        {"MCP_SERVER_URL": "ftp://invalid.example/mcp"},
        "http(s) URL",
    )
    expect_configuration_error(
        {"MCP_SERVER_URL": "http://user:pass@invalid.example/mcp"},
        "must not contain credentials",
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
    expect_configuration_error(
        {"MCP_SERVER_URL_01": "http://one.example/mcp"},
        "between 02 and 50",
    )
    print("Hermes MCP ephemeral tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
