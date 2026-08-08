# fedora44-ai-core

`ghcr.io/safrano9999/fedora44-ai-core` is the small, frequently changed
ephemeral layer in the Fedora image chain:

```text
fedora44-ai-core-pre -> fedora44-ai-core -> fedora44-ai-base -> fedora44-ai-safrano9999
```

The heavy generic Fedora 44 packages, toolchains, OpenClaw/Hermes installations,
and third-party command-line tools live in `fedora44-ai-core-pre`. Core imports
the pinned deterministic OpenClaw distribution, ten `openclaw_ephemeral`
runtime files, the pinned NOTE release, and the OpenClaw/Hermes runtime units.
`build/prepare-build-context.sh` verifies and stages those inputs below ignored
`build/vendor/`; the Containerfile verifies the release assets again and
installs them directly into the Fedora-native npm and Python runtimes inherited
from Core-pre. No Debian or Ephemeral container image is used as a build
source. The image
retains no generated OpenClaw configuration; configuration is rebuilt from
injected environment variables on each container start.

Optional repeatable `MCP_SERVER_NAME`, `MCP_SERVER_URL`, and
`MCP_SERVER_BEARER` groups are projected into both global agent configs at
startup by their respective ephemeral generators: OpenClaw owns its JSON
projection and Hermes owns its YAML projection. The first group is suffixless;
subsequent `config.sh` entries use
`_02`, `_03`, and so on. A missing name is derived from the URL hostname and a
missing Bearer configures an unauthenticated endpoint. Bearer values remain in
the injected environment; generated JSON/YAML stores only `${...}` references.
All tools are exposed to all agents, parallel tool calls are enabled, and the
OpenClaw Codex projection defaults MCP tool approvals to `approve`.

Core intentionally contains no checked-out Safrano project repository. Base
and Safrano add their disjoint repository sets in later layers.

Prepare or build locally with:

```bash
./build/prepare-build-context.sh
./build/build-local.sh
```

`./setup.sh` renders per-instance Compose and Quadlet files below
`CONTAINER/<name>/`. Use `--config-only`, `--pull`, or `--build` for
noninteractive operation; an interactive run defaults to the local build.
