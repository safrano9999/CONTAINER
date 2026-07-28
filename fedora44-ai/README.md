# fedora44-ai image builder

This private repository builds two Fedora 44 systemd container images:

- `ghcr.io/safrano9999/fedora44-ai-base`
- `ghcr.io/safrano9999/fedora44-ai-safrano9999`

Runtime configuration and container instances live in the separate
`fedora44-ai-base` and `fedora44-ai-safrano9999` repositories.

## Files

- `Containerfile`: the `ai-base` and `ai-safrano9999` image targets.
- `build.conf`: versioned build inputs for Node, Electrum, LND, Geth and webhook.
- `build/`: image services and build helpers, hardlinked from the SOT in `SCRIPTS`.
- `build-local.sh`: prepares the current sources and builds either image target locally.
- `prepare-build-context.sh`: stages source repositories, requirements,
  certificates, source manifests and the OpenClaw deterministic patch.
- `tag.sh`: tags and dispatches the GitHub Actions image build.

The canonical build helpers are stored under:

```text
SCRIPTS/safrano9999/image/fedora44-ai/
```

`prepare-build-context.sh` refreshes all local Hardlinks before staging. GitHub
Actions clones the current SCRIPTS repository and runs the same script, so the
SCRIPTS version remains authoritative.

## Build

Publish only the Safrano layer on top of the current Base image:

```bash
./tag.sh safrano9999
```

Rebuild Base first and then publish the Safrano layer:

```bash
./tag.sh all
```

Both modes publish a monthly counter tag and update `latest`.

To prepare the context without building an image locally:

```bash
./prepare-build-context.sh
```

The runtime repositories call the same builder when `Build locally` is selected:

```bash
./build-local.sh base
./build-local.sh safrano9999
```
