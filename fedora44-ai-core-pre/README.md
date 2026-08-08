# fedora44-ai-core-pre

`ghcr.io/safrano9999/fedora44-ai-core-pre` is the heavy, reusable first layer
of the Fedora 44 AI image chain:

```text
fedora44-ai-core-pre -> fedora44-ai-core -> fedora44-ai-base -> fedora44-ai-safrano9999
```

It contains only the generic Fedora/toolchain payload: system packages,
Node/Python tooling, the unconfigured OpenClaw and Hermes installations,
Codex/Claude CLIs, media/network utilities, and the generic blockchain tools.
It contains no `/opt/safrano9999` project tree, NOTE release, ephemeral runtime
configuration, or project-specific Safrano services. Its `image/runtime/`
overlay owns the generic Tailscale, Cockpit, Cloudflare connector, and BIP39
systemd integration inherited by every higher layer.

`fedora44-ai-core` adds the comparatively small and frequently changed layer:
the deterministic OpenClaw overlay, `openclaw-ephemeral`, NOTE, Hermes/OpenClaw
configuration generators, and their project-aware systemd runtime units.

Local build:

```bash
./build/build-local.sh
```
