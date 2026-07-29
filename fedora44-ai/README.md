# fedora44-ai layered image builder

This directory builds the two private project layers at the end of the Fedora
image chain:

```text
ghcr.io/safrano9999/fedora44-ai-core
  -> ghcr.io/safrano9999/fedora44-ai-core2
  -> ghcr.io/safrano9999/fedora44-ai-base
  -> ghcr.io/safrano9999/fedora44-ai-safrano9999
```

`ai-base` inherits the generic systemd, OpenClaw Ephemeral, Hermes Ephemeral,
Tailscale, Cockpit, Vditor and named-volume runtime from `fedora44-ai-core2`.
It adds only WELCOME, CODEANALYST, CITADEL, DIESDAS- and NEXTCLOUD plus their
requirements and services.

`ai-safrano9999` inherits the published Base image and adds only the remaining
Safrano repositories, their requirements and their services. Heavy Fedora,
Node, Hermes, OpenClaw, media and crypto installations are never repeated in
either target.

## Build-time versus runtime

`prepare-build-context.sh` performs build-time source staging:

- shallow-clones the exact project repositories;
- writes source manifests;
- stages release-only plugin payloads where required;
- generates separate Base and Safrano requirement files;
- restores the small set of image-layer build helpers from `SCRIPTS`.

At container runtime, `fedora44-ai-core2` owns environment projection, targeted
named-volume links and complete ephemeral OpenClaw/Hermes configuration.
`openclaw-safrano9999.service` runs after the fresh OpenClaw configuration and
only registers the additional project plugins before the gateway starts.

Canonical build helpers live below:

```text
SCRIPTS/safrano9999/image/fedora44-ai/
```

The GitHub workflow always uses a fresh context and no persistent Buildx cache.
