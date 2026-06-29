# safrano9999-openclaw Container Build

This document maps the current `Containerfile` to its logical image instructions. It records where each input originates, where it is installed, and which runtime component uses it.

## Build entrypoint and source of truth

`setup.sh` is the host-side entrypoint. Before Podman or Docker reads the `Containerfile`, it performs the following work:

1. Recreate every file below `./SCRIPTS/safrano9999/` as a hardlink to `../../SCRIPTS/safrano9999/`.
2. Hardlink the canonical `SCRIPTS/safrano9999/merge.sh` to `./merge.sh`.
3. Download the signed release ZIP and SHA-256 file for DAILYNEWS, CALENDAR, ZEROINBOX, KACHELMANN, and CITADEL.
4. Verify every downloaded ZIP with `sha256sum`.
5. Run the single SOT `merge.sh` for `env.example`, `config.conf_example`, `container.example`, and `requirements.txt`.
6. Exclude CITADEL's standalone configuration from the merge; this image supplies a focused OpenClaw plugin profile with localhost and Tailscale providers.
7. Run the shared `config.sh`, producing `.env`, `config.conf`, `container.conf`, and `build.conf`.
8. Render `compose.yml` and `safrano9999-openclaw.container` from the generated configuration.
9. Ask whether to pull `docker.io/safrano9999/safrano9999-openclaw:latest` or build `localhost/safrano9999-openclaw:latest`.

The host checkout preserves SOT identity through hardlinks. `COPY` creates normal image files; host inode identity does not cross the image-build boundary.

## Configuration model

- `.env` contains credentials and tokens.
- `config.conf` contains non-secret runtime settings.
- `container.conf` contains publish ports, network selection, capabilities, devices, and volumes.
- `build.conf` contains the OpenClaw base image, output image, and plugin release tag. It is not injected at runtime.
- The generated Quadlet injects `.env`, `config.conf`, and `container.conf` with `EnvironmentFile=`.
- CITADEL runs as an OpenClaw command plugin. Its standalone FastAPI WebUI and Cloudflare, subnet, and Tailscale extensions are disabled in this image.
- PID 1 is `tini`, which executes the shared Debian entrypoint. This image does not use systemd.

## Image instructions

### 01 - OpenClaw base-image argument

```dockerfile
ARG OPENCLAW_IMAGE
```

- **Purpose:** Receives the official OpenClaw image used by the next instruction.
- **Source:** `safrano9999-openclaw.build.conf_example` is resolved to `build.conf`; `setup.sh` passes the value as `--build-arg OPENCLAW_IMAGE=...`.
- **Scope:** Build-time only.

### 02 - OpenClaw base image

```dockerfile
FROM ${OPENCLAW_IMAGE}
```

- **Purpose:** Supplies Node.js, OpenClaw, `tini`, and the official `/app` layout.
- **Runtime:** The final gateway still uses the official OpenClaw CLI and application paths.

### 03 - Image metadata

```dockerfile
LABEL org.opencontainers.image.title="safrano9999-openclaw" \
      org.opencontainers.image.description="OpenClaw gateway bundled with DAILYNEWS, CALENDAR, ZEROINBOX, KACHELMANN and CITADEL with localhost and Tailscale providers."
```

- **Purpose:** Describes the image and its five bundled plugins.
- **Runtime effect:** None.

### 04 - Root build and runtime user

```dockerfile
USER root
```

- **Purpose:** Permits apt installation and allows the runtime entrypoint to start `tailscaled` when `TS_AUTHKEY` is configured.
- **Runtime:** OpenClaw also runs as root, with state below `/root/.openclaw`.

### 05 - Non-interactive apt mode

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
```

- **Purpose:** Prevents package installation from opening interactive prompts.

### 06 - Debian tools and GitHub CLI

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      git gh tmux wget less vim-tiny nano \
      jq ripgrep fd-find unzip xz-utils file \
      python3 python3-venv python3-pip \
      iproute2 iputils-ping dnsutils procps net-tools lsof \
 && rm -rf /var/lib/apt/lists/*
```

- **Purpose:** Installs Git/GitHub tooling, editors, archive tools, Python/venv support, and network diagnostics needed by plugins and CITADEL scanning.
- **Cleanup:** Removes apt indexes after installation.

### 07 - Tailscale installation

```dockerfile
RUN curl -fsSL https://tailscale.com/install.sh | sh \
 && rm -rf /var/lib/apt/lists/*
```

- **Purpose:** Installs `tailscaled` and the Tailscale CLI.
- **Runtime activation:** The entrypoint starts Tailscale only when `TS_AUTHKEY` exists.
- **Container requirements:** `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun` come from `container.conf`.

### 08 - Deterministic OpenClaw patch installer

```dockerfile
COPY SCRIPTS/safrano9999/image/services/openclaw/openclaw-patch-deterministic.sh /usr/local/bin/openclaw-patch-deterministic
```

- **SOT:** `../../SCRIPTS/safrano9999/image/services/openclaw/openclaw-patch-deterministic.sh`.
- **Purpose:** Copies the checksum-verifying release installer into the image.

### 09 - Deterministic OpenClaw dist

```dockerfile
RUN chmod +x /usr/local/bin/openclaw-patch-deterministic \
 && /usr/local/bin/openclaw-patch-deterministic
```

- **Purpose:** Downloads, verifies, and installs the patched OpenClaw `/app/dist` implementing the deterministic `dummy/dummy` model behavior.
- **Verification:** The helper checks SHA-256 and runs `node /app/openclaw.mjs --version`.
- **Current pin:** The helper still defaults to the `2026.6.5` deterministic artifact and must be updated before the next release build.

### 10 - Plugin installation root

```dockerfile
ENV OPENCLAW_PLUGINS_DIR=/opt/safrano9999-openclaw
```

- **Purpose:** Defines the permanent source directories for all bundled plugin repositories.

### 11 - Temporary plugin stage

```dockerfile
ENV SAFRANO9999_STAGE_DIR=${OPENCLAW_PLUGINS_DIR}/.stage
```

- **Purpose:** Defines the temporary directory receiving the verified release ZIP files from the build context.
- **Lifetime:** Removed after plugin installation.

### 12 - Shared plugin installer

```dockerfile
COPY SCRIPTS/safrano9999/image/services/openclaw/safrano9999_plugins.py /usr/local/bin/safrano9999_plugins.py
```

- **SOT:** Shared Python installer under `SCRIPTS`.
- **Purpose:** Validates manifests, prepares plugin Python environments, installs OpenClaw extensions, and registers plugin IDs.

### 13 - Shared container helper

```dockerfile
COPY SCRIPTS/safrano9999/image/safrano9999_container.sh /usr/local/lib/safrano9999_container.sh
```

- **Purpose:** Provides `safrano9999_OC_plugins`, release extraction, webhook generation, and fullrun generation.

### 14 - Verified plugin archives

```dockerfile
COPY safrano9999 ${SAFRANO9999_STAGE_DIR}
```

- **Source:** `setup.sh` downloads and verifies the five release ZIPs before the build starts.
- **Purpose:** Makes plugin sources available without cloning from the network during this image stage.

### 15 - Plugin installation and CITADEL provider profile

```dockerfile
RUN bash -lc 'set -eux; \
    mkdir -p /root/.openclaw; \
    chmod +x /usr/local/lib/safrano9999_container.sh; \
    . /usr/local/lib/safrano9999_container.sh; \
    safrano9999_OC_plugins CITADEL; \
    for root in "$OPENCLAW_PLUGINS_DIR/CITADEL" /root/.openclaw/extensions/citadel; do \
      [ -d "$root/extensions/enabled" ] || continue; \
      mkdir -p "$root/extensions/disabled"; \
      for provider in cloudflare subnet; do \
        [ ! -d "$root/extensions/enabled/$provider" ] \
          || mv "$root/extensions/enabled/$provider" "$root/extensions/disabled/$provider"; \
      done; \
    done; \
    safrano9999_OC_plugins --fullrun \
      DAILYNEWS CALENDAR ZEROINBOX KACHELMANN; \
    rm -rf "$SAFRANO9999_STAGE_DIR"'
```

- **CITADEL:** Installs the command plugin, then leaves the localhost and Tailscale providers enabled in both source and installed extension trees.
- **Fullrun plugins:** DAILYNEWS, CALENDAR, ZEROINBOX, and KACHELMANN contribute deterministic webhook commands.
- **Python:** Per-plugin setup scripts or fallback virtual environments are created during the build.
- **Cleanup:** Removes the temporary archive stage.

### 16 - Runtime paths and defaults

```dockerfile
ENV HOME=/root \
    OPENCLAW_CONFIG=/root/.openclaw/openclaw.json \
    OPENCLAW_CONFIG_DIR=/root/.openclaw \
    OPENCLAW_GATEWAY_PORT=18789 \
    TS_STATE_DIR=/var/lib/tailscale \
    OPENCLAW_DISABLE_BONJOUR=1
```

- **OpenClaw state:** `/root/.openclaw`.
- **Gateway:** Internal port `18789`; the host port comes from `OPENCLAW_GATEWAY_PUBLISH_PORT` in `container.conf`.
- **Tailscale:** State defaults to `/var/lib/tailscale`.
- **Bonjour:** Disabled to avoid container multicast discovery.

### 17 - Deterministic default model

```dockerfile
RUN openclaw models set dummy/dummy \
 && openclaw config get agents.defaults.model.primary
```

- **Purpose:** Sets and verifies the credential-free deterministic gateway model.
- **Boundary:** Plugin-specific OpenAI-v1 settings remain plugin runtime configuration; this image does not configure an OpenClaw LLM provider.

### 18 - Gateway port metadata

```dockerfile
EXPOSE 18789
```

- **Purpose:** Documents the internal OpenClaw gateway port.
- **Publishing:** Does not publish the port by itself; Quadlet or Compose performs that mapping.

### 19 - Gateway health check

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/healthz" >/dev/null || exit 1
```

- **Purpose:** Marks the container healthy only after the gateway health endpoint responds.

### 20 - OpenClaw runtime configurator

```dockerfile
COPY SCRIPTS/safrano9999/container/safrano9999-openclaw/openclaw-configure.py /usr/local/bin/openclaw-configure
```

- **Purpose:** Generates OpenClaw plugin, Telegram, and gateway configuration from injected environment values.
- **Runtime caller:** The entrypoint invokes it before starting the gateway.

### 21 - Shared OpenClaw functions

```dockerfile
COPY SCRIPTS/safrano9999/image/services/openclaw/openclaw_common.py /usr/local/bin/openclaw_common.py
```

- **Purpose:** Supplies shared OpenClaw command and configuration helpers used by `openclaw-configure`.

### 22 - Container entrypoint

```dockerfile
COPY SCRIPTS/safrano9999/container/safrano9999-openclaw/entrypoint.sh /usr/local/bin/safrano9999-openclaw-entrypoint
```

- **Runtime sequence:** Optional Tailscale, OpenClaw configuration, ZEROINBOX labels, KACHELMANN WebUI, CITADEL localhost scan, cron setup, optional fullrun, then the gateway.

### 23 - Routine helper

```dockerfile
COPY SCRIPTS/safrano9999/container/safrano9999-openclaw/safrano9999-routines.sh /usr/local/bin/safrano9999-routines
```

- **Purpose:** Provides the shared deterministic plugin routine wrapper.

### 24 - Cron installer

```dockerfile
COPY SCRIPTS/safrano9999/container/openclaw/openclaw_crontabs.sh /usr/local/bin/openclaw-crontabs
```

- **Purpose:** Converts configured CET schedules into OpenClaw cron jobs after gateway startup.

### 25 - Command-authorization helper

```dockerfile
COPY SCRIPTS/safrano9999/container/openclaw/openclaw_allow_all.mjs /usr/local/bin/openclaw-allow-all
```

- **Purpose:** Repairs command authorization if cron registration requires it.

### 26 - Cron defaults

```dockerfile
COPY SCRIPTS/safrano9999/container/openclaw/openclaw_crontabs.conf /etc/safrano9999/openclaw-crontabs.conf
```

- **Purpose:** Installs the shared cron configuration source below `/etc/safrano9999`.

### 27 - Runtime modes and state directories

```dockerfile
RUN chmod +x /usr/local/bin/openclaw-configure /usr/local/bin/safrano9999-openclaw-entrypoint /usr/local/bin/safrano9999-routines /usr/local/bin/openclaw-crontabs /usr/local/bin/openclaw-allow-all \
 && mkdir -p /root/.openclaw /var/lib/tailscale
```

- **Purpose:** Marks runtime helpers executable and creates OpenClaw and Tailscale state roots.

### 28 - PID 1

```dockerfile
ENTRYPOINT ["tini", "-s", "--", "/usr/local/bin/safrano9999-openclaw-entrypoint"]
```

- **Purpose:** Uses the base image's `tini` to reap child processes and forward signals.
- **Final process:** The entrypoint uses `exec` to replace itself with `openclaw gateway run`.

## Runtime startup sequence

1. Resolve the OpenClaw CLI command.
2. Start and join Tailscale only when `TS_AUTHKEY` exists.
3. Run `openclaw-configure`.
4. Initialize ZEROINBOX Gmail labels when its Python environment and helper exist.
5. Start the KACHELMANN FastAPI WebUI on `KACHELMANN_PORT` and wait briefly for it to accept connections.
6. Run the CITADEL scan from the installed extension. Only localhost routing is enabled, so the initial HTTP service list contains KACHELMANN rather than host-level providers.
7. Schedule asynchronous OpenClaw cron setup.
8. Optionally schedule the generated fullrun script.
9. Execute the OpenClaw gateway with LAN binding and optional token authentication.

## Remaining release work

1. Build and publish the deterministic OpenClaw patch asset for the tested OpenClaw `2026.6.10` code, then update `openclaw-patch-deterministic.sh`; its current default asset is `2026.6.5`.
2. Commit and tag the plugin repositories with the corrected shared ZIP builder so `container.example` is present in release archives. KACHELMANN needs this for `KACHELMANN_PUBLISH_PORT`.
3. Add build-context ignore rules before a release build. The repository currently has no `.containerignore` or `.dockerignore`, so local `.env`, generated configuration, and `tmp/` are sent to the local build engine even though the `Containerfile` does not copy them into an image layer.
4. Run a fresh local image build and smoke-test OpenClaw startup, all five plugin registrations, KACHELMANN health, the initial CITADEL scan, `/citadel`, and the gateway health check.

When `KACHELMANN_DB_BACKEND=sqlite`, `setup.sh` creates the named volume `${CONTAINER_NAME}-kachelmann-sqlite`. It mounts that volume at both KACHELMANN `sqlite/` directories so the WebUI and installed OpenClaw plugin share one persistent database while all plugin code remains in the image layer.
