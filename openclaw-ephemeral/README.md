# openclaw-ephemeral

Runtime wrapper and exact image-source snapshot for:

```text
docker.io/safrano9999/openclaw-ephemeral:latest
```

The image payload is copied byte-for-byte from public source commit
`02473052735acf3da1a89c5000b9bc7772152271`. Its eleven build inputs and hashes
are recorded in `.openclaw-ephemeral-source.tsv`; the build-context allowlist
excludes this wrapper and all generated configuration.

`setup.sh` merges the namespaced examples through the shared `merge.sh` and
`config.sh` sources of truth. It configures the OpenClaw gateway, NOTE,
Telegram and repeatable OpenAI-v1 providers without bringing in the downstream
Safrano plugin, Citadel, Tailscale or cron layers.

Render an instance without an image operation:

```bash
./setup.sh --no-build
```
