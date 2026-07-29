# fedora44-ai-core

`ghcr.io/safrano9999/fedora44-ai-core` is the heavy root of the Fedora image
chain:

```text
fedora44-ai-core -> fedora44-ai-base -> fedora44-ai-safrano9999
```

Core owns Fedora 44, the toolchains and pinned third-party programs, plus the
complete generic OpenClaw/Hermes runtime formerly split into Core2. It imports
the deterministic OpenClaw distribution and `openclaw_ephemeral` package from
the pinned `OPENCLAW_EPHEMERAL_IMAGE`, rebuilds the NOTE environment on
Fedora, installs the runtime helpers and systemd units, and leaves no generated
OpenClaw configuration in the image. Configuration is rebuilt from injected
environment variables on each container start.

Core intentionally contains no checked-out Safrano project repository. Base
and Safrano add their disjoint repository sets in later layers.

Prepare or build locally with:

```bash
./prepare-build-context.sh
./build-local.sh
```

`./setup.sh` renders per-instance Compose and Quadlet files below
`CONTAINER/<name>/`. Use `--config-only`, `--pull`, or `--build` for
noninteractive operation; an interactive run defaults to the local build.

The complete static and noninteractive chain check is:

```bash
./tests/check-build-context.sh
```
