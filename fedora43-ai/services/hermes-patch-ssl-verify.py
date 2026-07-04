#!/usr/bin/env python3
"""Patch Hermes 0.14 keepalive HTTP client to honor ssl_verify: false."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


DEFAULT_INSTALL_DIR = "/usr/local/lib/hermes-agent"
MARKER = "# fedora43-ai ssl_verify patch for Hermes v0.14"

OLD = """            return _httpx.Client(
                transport=_httpx.HTTPTransport(socket_options=_sock_opts),
                proxy=_proxy,
            )
"""

NEW = f"""            _verify = True
            try:
                _raw_verify = os.environ.get("HERMES_SSL_VERIFY", "").strip().lower()
                if not _raw_verify:
                    _cfg_path = get_hermes_home() / "config.yaml"
                    if _cfg_path.is_file():
                        _match = re.search(
                            r"(?m)^\\s*ssl_verify\\s*:\\s*(false|true|0|1|no|yes|off|on)\\s*$",
                            _cfg_path.read_text(encoding="utf-8", errors="ignore"),
                        )
                        if _match:
                            _raw_verify = _match.group(1).lower()
                if _raw_verify:
                    _verify = _raw_verify not in {{"0", "false", "no", "off"}}
            except Exception:
                _verify = True
            {MARKER}
            return _httpx.Client(
                transport=_httpx.HTTPTransport(socket_options=_sock_opts, verify=_verify),
                proxy=_proxy,
                verify=_verify,
            )
"""


def hermes_version() -> str | None:
    override = os.environ.get("HERMES_VERSION_OVERRIDE", "").strip()
    if override:
        return override

    for cmd in (["hermes", "--version"], ["hermes", "version"]):
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20, check=False)
        except (OSError, subprocess.TimeoutExpired):
            continue
        text = f"{proc.stdout}\n{proc.stderr}"
        match = re.search(r"\bv?(\d+\.\d+(?:\.\d+)?)\b", text)
        if match:
            return match.group(1)
    return None


def is_hermes_014(version: str | None) -> bool:
    return bool(version and re.match(r"^0\.14(?:\.|$)", version))


def main() -> None:
    version = hermes_version()
    if not is_hermes_014(version):
        print(f"Hermes ssl_verify patch skipped: version={version or 'unknown'}")
        return

    install_dir = Path(os.environ.get("HERMES_INSTALL_DIR", DEFAULT_INSTALL_DIR))
    run_agent = install_dir / "run_agent.py"
    if not run_agent.is_file():
        raise SystemExit(f"Hermes ssl_verify patch failed: {run_agent} not found")

    source = run_agent.read_text(encoding="utf-8")
    if MARKER in source:
        print(f"Hermes ssl_verify patch already applied: version={version}")
        return
    if OLD not in source:
        raise SystemExit("Hermes ssl_verify patch failed: target block not found")

    run_agent.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"Hermes ssl_verify patch applied: version={version}")


if __name__ == "__main__":
    main()
