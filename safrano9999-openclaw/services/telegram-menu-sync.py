#!/usr/bin/env python3
"""Publish the deterministic plugin-only Telegram command menu."""

import json
import os
import urllib.error
import urllib.request


COMMANDS = [
    {"command": "kachelmann", "description": "KACHELMANN Routinen"},
    {"command": "routines", "description": "Alias fuer KACHELMANN"},
    {"command": "calendar", "description": "Kommende Termine"},
    {"command": "zeroinbox", "description": "Mails sortieren und PDF senden"},
    {"command": "mails", "description": "Alias fuer ZEROINBOX"},
    {"command": "dailynews", "description": "Dailynews PDF erzeugen"},
]

SCOPES = [
    None,
    {"type": "all_group_chats"},
]


def _post(token: str, method: str, payload: dict) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/{method}",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    token = os.environ.get("TELEGRAMTOKEN_OPENCLAW", "").strip()
    if not token:
        print("Telegram menu sync skipped: TELEGRAMTOKEN_OPENCLAW not set")
        return 0
    for scope in SCOPES:
        payload = {"commands": COMMANDS}
        if scope:
            payload["scope"] = scope
        result = _post(token, "setMyCommands", payload)
        if not result.get("ok"):
            print(f"Telegram menu sync failed: {result!r}")
            return 1
    print(f"Telegram plugin menu synced: {', '.join('/' + c['command'] for c in COMMANDS)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        print(f"Telegram menu sync failed: {exc}")
        raise SystemExit(1)
