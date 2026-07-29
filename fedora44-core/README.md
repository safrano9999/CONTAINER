# fedora44-core

`fedora44-core` is the private, reusable heavy base for the Fedora 44 AI
images:

```text
ghcr.io/safrano9999/fedora44-core
```

The image intentionally contains only the generic third-party layer. It is a
systemd-capable Fedora 44 base with:

- the Fedora CLI, development, media, diagnostics and networking package set;
- Node.js, Python, `uv`, Codex CLI, Claude Code and unpatched OpenClaw
  `2026.7.1`;
- Hermes Agent (pinned commit plus the existing Nous API-key patch), Fugu,
  official OpenClaw Brave/Codex plugins, Vditor, webhook and cloudflared;
- Cockpit and Tailscale packages;
- Electrum, LND, Geth, Agave/Solana and the BIP39 offline page;
- the shared Python dependency layer used by the later Fedora AI image.

The build is currently `linux/amd64` because cloudflared, Electrum, LND, Geth
and Agave are installed from their existing amd64 artifacts.

## Deliberate boundary

This image does **not** contain:

- any checked-out `safrano9999/*` project repository;
- any Safrano OpenClaw plugin or project service;
- NOTE or another Safrano plugin archive;
- the deterministic OpenClaw patch;
- `openclaw-ephemeral`, its Python package, or an OpenClaw systemd unit;
- runtime configuration assembled from injected environment variables.

Those belong in `fedora44-ai-base` or a later image. Keeping that boundary
means rebuilding project sources or OpenClaw runtime configuration does not
repeat the expensive Fedora/toolchain installation.

## Reproducible inputs

Fixed inputs live in `build.conf`. `prepare-build-context.sh` resolves the
moving upstream inputs (for example Node `stable`, latest `uv`, package CLI
versions and signed-source commits) into `.resolved-build.env` immediately
before a build. The build verifies the downloaded checksums, signatures,
commits and installed versions in the same places as the existing
`fedora44-ai` build.

OpenClaw itself is fixed to `2026.7.1`. Applying the matching deterministic
patch is deliberately deferred to the next image layer.

## Local build

```bash
./prepare-build-context.sh
./build-local.sh
```

Use `./build-local.sh --no-cache` for the same cache policy as CI. The GitHub
workflow uses no persistent Buildx cache and publishes to the private GHCR
package `ghcr.io/safrano9999/fedora44-core`.

Run the lightweight repository checks without building the image:

```bash
./tests/check-build-context.sh
```

