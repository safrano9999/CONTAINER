#!/usr/bin/env python3
import json
import os
import re
import subprocess
import urllib.error
import urllib.request


CODEX_AUTH_PATHS = ("/root/.codex/auth.json", "/named_volumes/CODEX_AUTH/auth.json")


def openclaw_json(*args: str) -> dict:
    result = subprocess.run(
        ["openclaw", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def available_models(provider: str) -> dict[str, dict]:
    catalog = openclaw_json("models", "list", "--all", "--provider", provider, "--json")
    return {
        model["key"]: {}
        for model in catalog.get("models", [])
        if model.get("key")
        and model.get("available") is True
        and model.get("missing") is False
    }


def model_key(provider: str, model_id: str) -> str:
    model_id = model_id.strip()
    if model_id.startswith("models/"):
        model_id = model_id.split("/", 1)[1]
    return f"{provider}/{model_id}"


def unsupported_model(provider: str, model_id: str) -> bool:
    if provider == "xai":
        return any(part in model_id for part in ("multi-agent", "imagine-image", "imagine-video"))
    return False


def openai_v1_configs() -> list[dict[str, str]]:
    configs: list[dict[str, str]] = []
    for key, value in os.environ.items():
        match = re.fullmatch(r"OPENAI_V1_PROVIDER(_[0-9]+)?", key)
        if not match:
            continue
        provider = value.strip()
        suffix = match.group(1) or ""
        url = os.environ.get(f"OPENAI_V1_URL{suffix}", "").strip()
        alias = os.environ.get(f"OPENAI_V1_API_KEY_ALIAS{suffix}", "").strip()
        api_key = os.environ.get(alias, "").strip() if alias else ""
        api_key = api_key or os.environ.get(f"OPENAI_V1_KEY{suffix}", "").strip()
        if provider and url and api_key:
            configs.append({"provider": provider, "url": url, "api_key": api_key})
    return sorted(configs, key=lambda item: item["provider"])


def openai_v1_models(config: dict[str, str]) -> dict[str, dict]:
    url = config["url"].rstrip("/") + "/models"
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {config['api_key']}"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    return {
        model_key(config["provider"], str(model.get("id", ""))): {}
        for model in payload.get("data", [])
        if model.get("id") and not unsupported_model(config["provider"], str(model["id"]))
    }


def has_codex_oauth() -> bool:
    return any(os.path.isfile(path) for path in CODEX_AUTH_PATHS)


def codex_oauth_models() -> dict[str, dict]:
    if not has_codex_oauth():
        return {}
    result = subprocess.run(
        ["codex", "debug", "models"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        return {}
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    return {
        model_key("openai", str(model.get("slug", ""))): {}
        for model in payload.get("models", [])
        if model.get("slug")
    }


def main() -> None:
    status = openclaw_json("models", "status", "--json")
    auth_providers = status.get("auth", {}).get("providers", [])
    providers: set[str] = set()
    v1_providers: set[str] = set()
    models: dict[str, dict] = {}

    for config in openai_v1_configs():
        provider = config["provider"]
        try:
            discovered = openai_v1_models(config)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            print(f"Skipping {provider}: {exc}")
            continue
        if discovered:
            v1_providers.add(provider)
            providers.add(provider)
            models.update(discovered)

    for key in os.environ:
        if not key.endswith("_API_KEY"):
            continue
        source = f"env: {key}"
        for entry in auth_providers:
            provider = entry.get("provider")
            if entry.get("env", {}).get("source") != source or not provider:
                continue
            if provider in v1_providers or (provider == "google" and "gemini" in v1_providers):
                continue
            providers.add(provider)

    codex_models = codex_oauth_models()
    if codex_models:
        providers.add("openai")
        models.update(codex_models)

    for provider in sorted(providers):
        if provider not in v1_providers:
            models.update(available_models(provider))

    if models:
        if "openai" in providers:
            models.setdefault("openai/gpt-5.6-terra", {})
            default_model = "openai/gpt-5.6-terra"
        else:
            default_model = next(
                iter(sorted(models)),
                "",
            )
        subprocess.run(
            [
                "openclaw",
                "config",
                "set",
                "agents.defaults.models",
                json.dumps(models, separators=(",", ":")),
                "--strict-json",
                "--replace",
            ],
            check=True,
        )
        if default_model:
            subprocess.run(
                [
                    "openclaw",
                    "config",
                    "set",
                    "agents.defaults.model.primary",
                    default_model,
                ],
                check=True,
            )

    print(f"Registered {len(models)} model(s) from: {', '.join(sorted(providers)) or 'none'}")


if __name__ == "__main__":
    main()
