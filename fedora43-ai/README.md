# fedora43-ai

`fedora43-ai` is a Fedora 43 based all-in-one AI/dev/crypto container profile. It
builds a systemd-enabled container image that bundles several local
`safrano9999` applications, AI CLIs, OpenClaw, Hermes Agent, LiteLLM-facing
configuration, Tailscale access, and selected crypto utilities.

The repository is intentionally a container orchestrator, not the source of every
application it runs. `setup.sh` pulls the application repositories into
`./safrano9999/`, merges their examples, renders runtime files, and then either
pulls a prebuilt image or builds the local `Containerfile`.

## What This Container Contains

At a high level the image includes:

- Fedora 43 with systemd as PID 1.
- OpenClaw gateway and OpenClaw CLI.
- Hermes Agent gateway, dashboard, Telegram integration, and optional OpenAI
  compatible API endpoint.
- LiteLLM wiring for both OpenClaw and Hermes.
- Codex CLI, Claude Code CLI, OpenClaw, and the OpenClaw Brave plugin.
- The local `safrano9999` app stack:
  - `CODEANALYST`
  - `JUGO`
  - `CITADEL`
  - `VikAI`
  - `PV_D-A-CH`
  - `NAPOLEON_HILLS_AI_MASTERMIND_CLASSES`
  - `SOLANA_AIRGAPPED_DEBIAN_WORKFLOW`
  - `NaturalGrounding-Tiktok-Ying-Video-Manager`
- Tailscale support inside the container.
- Crypto tools:
  - BIP39 offline web page
  - Electrum
  - LND / `lncli`
  - Geth
  - Solana CLI
- Convenience tools such as `git`, `gh`, `tmux`, `rg`, `jq`, `curl`, `ffmpeg`,
  `cloudflared`, network tooling, and build tooling.

## Repository Layout

```text
.
├── Containerfile
├── setup.sh
├── merge.sh
├── clean.sh
├── up.sh
├── up_rootless.sh
├── env.fedora43-ai.example
├── config.fedora43-ai.conf_example
├── services/
│   ├── *.service
│   ├── openclaw-configure.py
│   ├── openclaw-patch-models-command.py
│   ├── hermes-configure-litellm.py
│   ├── hermes-patch-ssl-verify.py
│   └── vikai-bootstrap-openclaw-agents.py
└── safrano9999/
    ├── CODEANALYST/
    ├── JUGO/
    ├── CITADEL/
    └── VikAI/
```

Generated files are intentionally ignored:

- `.env`
- `env.example`
- `requirements.txt`
- `config.conf`
- `config.conf_example`
- `compose.yml`
- `fedora43-ai.container`
- `config.sh`
- `merge_conf.sh`

`config.sh` is not owned by this repository. `setup.sh` hardlinks it from
`../../SCRIPTS/safrano9999/config.sh` when configuration is allowed.

## Source Of Truth Model

This setup separates secrets from non-secret runtime decisions:

- `env.example`
  contains secrets and runtime keys. It is generated from the app repos plus
  `env.fedora43-ai.example`.

- `.env`
  is the filled runtime secret file. It is ignored and should not be committed.

- `config.conf_example`
  contains non-secret defaults such as ports, bind host, capabilities, devices,
  and volumes. It is generated from the app repos plus
  `config.fedora43-ai.conf_example`.

- `config.conf`
  is the filled local runtime config. It is ignored and should not be committed.

- `compose.yml`
  is generated from `config.conf` or, if that does not exist,
  `config.conf_example`.

- `fedora43-ai.container`
  is the generated Podman Quadlet unit.

The examples are source-of-truth inputs. The generated runtime files are local
outputs.

## Setup Flow

Run:

```bash
./setup.sh
```

`setup.sh` performs these steps:

1. Ensures `./safrano9999/` exists.
2. Clones or fast-forwards:
   - `CODEANALYST`
   - `JUGO`
   - `CITADEL`
   - `VikAI`
   - `PV_D-A-CH`
   - `NAPOLEON_HILLS_AI_MASTERMIND_CLASSES`
   - `SOLANA_AIRGAPPED_DEBIAN_WORKFLOW`
   - `NaturalGrounding-Tiktok-Ying-Video-Manager` from `feature/webui-db-backend-dual`
3. Runs `merge.sh`.
4. Merges all `env.example` files into the local generated `env.example`.
5. Merges all `requirements.txt` files into the local generated
   `requirements.txt`.
6. Hardlinks `merge_conf.sh` from `../../SCRIPTS/safrano9999/image/install/merge_conf.sh`.
7. Merges all `config.conf_example` files into the local generated
   `config.conf_example`.
8. Unless `--no-config` is used, hardlinks and runs `config.sh`.
9. Renders `compose.yml`.
10. Renders `fedora43-ai.container`.
11. Asks whether to pull the image from Docker Hub or build locally.

Options:

```bash
./setup.sh --config
```

Only update repos, merge examples, run config, render `compose.yml` and
`fedora43-ai.container`, then exit.

```bash
./setup.sh --no-config
```

Update repos and regenerate runtime files without running `config.sh`.

```bash
./setup.sh --fresh
```

Skip config and run a local `podman build --pull=always --no-cache`.

```bash
./setup.sh my-instance-name
```

Use another compose project/container instance name for local compose builds.

## Build And Run

The normal interactive path is:

```bash
./setup.sh
```

When prompted, choose:

- `1` to pull `docker.io/safrano9999/fedora43-ai:latest`
- `2` to build `localhost/fedora43-ai:latest` locally

To start with generated compose:

```bash
./up_rootless.sh fedora43-ai
```

or:

```bash
INSTANCE=fedora43-ai podman-compose -f compose.yml up -d
```

To use the generated Quadlet:

```bash
mkdir -p ~/.config/containers/systemd
cp fedora43-ai.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start fedora43-ai
```

If `fedora43-ai.container` changes, reload systemd before restart:

```bash
systemctl --user daemon-reload
systemctl --user restart fedora43-ai
```

## Default Published Ports

The generated config maps published ports from `config.conf`.

| Component | Internal Port | Default Host Port | Purpose |
|---|---:|---:|---|
| CITADEL | `10999` | `10999` | Service dashboard / scan UI |
| CODEANALYST | `11000` | `11000` | Code dependency and tool usage UI |
| JUGO | `11001` | `11001` | Language learning UI |
| BIP39 | `11002` | `11002` | Offline BIP39 HTML page |
| PV_D-A-CH | `11003` | `11003` | PV/QGIS workflow UI |
| Napoleon | `11004` | `11004` | Napoleon Hill mastermind UI |
| NaturalGrounding | `11005` | `11005` | TikTok video manager UI |
| OpenClaw Gateway | `18789` | `20789` | OpenClaw gateway and Control UI |
| Hermes Dashboard | `9119` | `19119` | Hermes dashboard |
| Hermes API Server | `8642` | `18642` | Optional OpenAI compatible `/v1` API |

`HOST` in `config.conf` controls the host-side publish address. The default is
`127.0.0.1`, so the services are bound to localhost unless explicitly changed.
Inside the container, web services bind to `0.0.0.0`; host reachability is
controlled by the generated compose/Quadlet port mapping.

## Environment Variables

The merged `env.example` includes the secrets and API keys needed by the stack.
Important entries:

| Variable | Used By | Purpose |
|---|---|---|
| `LITELLM_URL` | OpenClaw, Hermes | LiteLLM base URL without the container port appended |
| `LITELLM_PORT` | OpenClaw, Hermes | LiteLLM port |
| `LITELLM_API_KEY` | OpenClaw, Hermes | Bearer key for LiteLLM |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw | Gateway token for OpenClaw auth |
| `OPENCLAW_LITELLM_MODEL` | OpenClaw | Default model, for example `deepseek-v4-flash` |
| `HERMES_LITELLM_MODEL` | Hermes | Default Hermes model |
| `HERMES_API_SERVER_KEY` | Hermes | Optional key for Hermes OpenAI compatible API |
| `TELEGRAMTOKEN_OPENCLAW` | OpenClaw | Telegram bot token routed to `agent:main:main` |
| `TELEGRAMTOKEN_HERMES` | Hermes | Telegram bot token for Hermes |
| `BRAVE_API_KEY` | OpenClaw | Enables Brave search plugin config |
| `TOKEN_WORKER` | VikAI/OpenClaw | Vikunja API token for worker agent |
| `TOKEN_ARCHITECT` | VikAI/OpenClaw | Vikunja API token for architect agent |
| `TOKEN_QC` | VikAI/OpenClaw | Vikunja API token for QC agent |
| `TS_AUTHKEY` | Tailscale | Auth key for in-container Tailscale |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code | Optional Claude auth material |

The default `OPENCLAW_GATEWAY_TOKEN` example is intentionally a command hint:

```bash
openssl rand -hex 32
```

## Configuration Variables

The merged `config.conf_example` contains non-secret runtime controls. Important
entries:

| Variable | Purpose |
|---|---|
| `HOST` | Host-side bind address for published ports |
| `*_PORT` | Internal service port |
| `*_PUBLISH_PORT` | Host-side published port |
| `CITADEL_SUBNET_IP` | Subnet IP CITADEL should use when producing service links |
| `TS_HOSTNAME` | Tailscale hostname |
| `CITADEL_CAPABILITIES` | Extra container capabilities such as `NET_ADMIN,NET_RAW` |
| `CITADEL_DEVICES` | Devices such as `/dev/net/tun` |
| `CITADEL_VOLUMES` | Extra volumes such as `tailscale:/var/lib/tailscale` |
| `VIKUNJA_HOST` | Vikunja host used by VikAI |
| `VIKUNJA_CONTAINER` | Vikunja container name for local exec-style integration |
| `VIKAI_DEFAULT_TRANSPORT` | Default VikAI transport, currently `cli` |
| `VIKAI_DEFAULT_TARGET` | Default VikAI target, for example `openclaw-tui` |

`INJECT_OVERWRITE=true` documents the intended precedence: injected process
environment wins over config/env files when the application runtime supports
that behavior.

## Generated Compose And Quadlet

`setup.sh` renders both `compose.yml` and `fedora43-ai.container` from
`config.conf`.

The renderer supports:

- published ports via `*_PUBLISH_PORT`
- host bind address via `HOST` or `*_PUBLISH_HOST`
- regular environment variables
- capabilities via `*_CAPABILITIES`
- devices via `*_DEVICES`
- volumes via `*_VOLUMES`

Generated compose always includes:

- `.env` as `env_file`
- `/tmp/.X11-unix:/tmp/.X11-unix`
- environment values rendered from `config.conf`

Generated Quadlet always includes:

- `EnvironmentFile=<repo>/.env`
- generated `Environment=...` lines
- generated `PublishPort=...` lines
- generated `Volume=...` lines
- generated capabilities/devices

## Containerfile Layer Strategy

The `Containerfile` is arranged so large and slow layers come first:

1. Fedora base packages through DNF.
2. Solana CLI.
3. `uv`.
4. Hermes Agent source and installer.
5. global npm tools:
   - `@openai/codex@latest`
   - `@anthropic-ai/claude-code@latest`
   - `openclaw@latest`
6. OpenClaw Brave plugin.
7. `cloudflared`.
8. systemd container cleanup.
9. crypto utilities.
10. Python requirements.
11. local `safrano9999` repositories.
12. systemd units.
13. configuration and patch helper scripts.

The last layer copies the service scripts and runs the image-level patches. This
keeps routine patch iterations fast because DNF, npm, Hermes, crypto downloads,
and Python dependency layers do not need to rebuild unless their inputs change.

## Systemd Services

Inside the container, systemd manages the runtime.

| Service | Type | Purpose |
|---|---|---|
| `tailscaled.service` | simple | Starts `tailscaled` when `TS_AUTHKEY` is present |
| `tailscale-up.service` | oneshot | Runs `tailscale up` with auth key and optional hostname |
| `codeanalyst.service` | simple | Runs CODEANALYST FastAPI UI |
| `jugo.service` | simple | Runs JUGO FastAPI UI |
| `citadel-setup.service` | oneshot | Prepares CITADEL runtime directories |
| `citadel.service` | simple | Runs CITADEL FastAPI UI |
| `citadel-scan.service` | oneshot | Runs CITADEL `scan.sh` after a delay |
| `bip39.service` | simple | Serves the offline BIP39 HTML page |
| `fedora43-ai.service` | oneshot | Runs local init scripts from `/fedora/bin` |
| `openclaw-config.service` | oneshot | Writes OpenClaw runtime config before gateway start |
| `openclaw.service` | simple | Starts OpenClaw Gateway on internal port `18789` |
| `hermes.service` | simple | Starts Hermes Agent gateway |
| `hermes-dashboard.service` | simple | Starts Hermes dashboard on internal port `9119` |

Useful commands:

```bash
podman exec -it fedora43-ai bash
systemctl status openclaw.service
journalctl -u openclaw.service -f
journalctl -u openclaw-config.service -n 200
journalctl -u hermes.service -f
systemctl restart openclaw.service
systemctl restart hermes.service
```

## OpenClaw

OpenClaw is installed globally with npm:

```Dockerfile
npm install -g openclaw@latest
```

The OpenClaw Brave plugin is installed into the image:

```Dockerfile
openclaw plugins install @openclaw/brave-plugin
```

OpenClaw runtime is split into two systemd services:

- `openclaw-config.service`
- `openclaw.service`

### OpenClaw Config Service

`openclaw-config.service` runs `/usr/local/bin/openclaw-configure` once before
the gateway starts. The source file is `services/openclaw-configure.py`.

It does the following:

- Ensures `/root/.openclaw/openclaw.json` exists.
- Runs non-interactive OpenClaw onboarding when needed.
- Normalizes the LiteLLM base URL from:
  - `LITELLM_URL`
  - `LITELLM_PORT`
- Discovers models through LiteLLM `/v1/models`.
- Configures OpenClaw model mode as `merge`.
- Configures the `litellm` provider.
- Stores `LITELLM_API_KEY` as an environment-backed secret reference, not as a
  plaintext config value.
- Configures the default model from `OPENCLAW_LITELLM_MODEL`.
- Creates or updates `agent:main:main`.
- Removes agent model allowlists so agents can use the full available model
  catalog.
- Routes `TELEGRAMTOKEN_OPENCLAW` to the `main` agent.
- Enables Brave web search when `BRAVE_API_KEY` is present.
- Adds localhost/host/Tailscale origins to OpenClaw Control UI allowed origins.
- Bootstraps VikAI worker/architect/QC agents when all three VikAI tokens are
  present.

### OpenClaw Gateway Service

`openclaw.service` starts:

```bash
openclaw gateway run --bind lan --port 18789
```

If `OPENCLAW_GATEWAY_TOKEN` is set, the service adds:

```bash
--auth token --token "$OPENCLAW_GATEWAY_TOKEN"
```

The gateway internal port is `18789`. The default host mapping is `20789`.

### OpenClaw Control UI Origins

OpenClaw rejects Control UI browser origins that are not explicitly allowed.
`openclaw-configure.py` writes allowed origins for:

- `HOST:18789`
- `HOST:20789`
- Tailscale DNS name on both ports, when detectable
- Tailscale IPs on both ports, when detectable
- `TS_HOSTNAME` on both ports, when it looks like a DNS name

This keeps host access explicit while still supporting Tailscale URLs.

### OpenClaw Telegram Routing

`TELEGRAMTOKEN_OPENCLAW` belongs to the plain `main` agent. The VikAI agents are
separate and do not need Telegram tokens.

The config service writes a binding equivalent to:

```text
telegram default account -> agent main -> session main
```

### OpenClaw `/models` Patch

The image contains a small build-time patch for OpenClaw's `/models` command:

```text
services/openclaw-patch-models-command.py
```

This is not a systemd service. It runs during the image build:

```Dockerfile
RUN /usr/local/bin/openclaw-patch-models-command
```

The patch modifies the installed OpenClaw `dist/commands-models-*.js` file after
npm installation. It mirrors the upstream source-level fix prepared for OpenClaw.

The behavior:

- Default `/models` uses the read-only catalog path.
- The read-only catalog path has a `750ms` timeout fallback.
- If the read-only catalog is slow, `/models` replies instead of hanging.
- `/models all` still uses the full catalog path.
- Provider wildcard configs still use the full catalog path.
- Runtime auth discovery is disabled for the normal visible catalog path.

This patch exists because large LiteLLM catalogs can contain hundreds of models.
Without the fast path, Telegram `/models` pagination can become very slow.

## Hermes Agent

Hermes Agent is installed into:

```text
/usr/local/lib/hermes-agent
```

The image clones the Hermes repository and also runs the official install script
with setup skipped:

```Dockerfile
git clone --depth 1 https://github.com/NousResearch/hermes-agent /usr/local/lib/hermes-agent
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --skip-setup
```

Runtime is split into:

- `hermes.service`
- `hermes-dashboard.service`

### Hermes LiteLLM Configuration

`hermes.service` runs two pre-start scripts:

```text
/usr/local/bin/hermes-patch-ssl-verify
/usr/local/bin/hermes-configure-litellm
```

`services/hermes-configure-litellm.py` writes:

```text
/root/hermes-home/config.yaml
```

It configures Hermes to use:

- provider: `litellm`
- default model: `HERMES_LITELLM_MODEL`, falling back to
  `OPENCLAW_LITELLM_MODEL`, then `deepseek-v4-flash`
- base URL: normalized from `LITELLM_URL` and `LITELLM_PORT`
- key env: `LITELLM_API_KEY`
- discovered models from LiteLLM `/v1/models`, when available
- `ssl_verify: false`

The LiteLLM key is referenced through environment, not written as plaintext into
the Hermes config.

### Hermes Gateway

`hermes.service` starts:

```bash
hermes gateway run --replace
```

It exports:

- `OPENAI_API_KEY=$LITELLM_API_KEY`
- `OPENAI_BASE_URL=<normalized LiteLLM URL>/v1`
- `TELEGRAM_BOT_TOKEN` from `TELEGRAMTOKEN_HERMES`, when a real token is set
- `API_SERVER_*` variables when `HERMES_API_SERVER_KEY` is set

The service intentionally does not force a custom provider/model through
`HERMES_INFERENCE_PROVIDER` or `HERMES_INFERENCE_MODEL`; Hermes should use the
generated config.

### Hermes Dashboard

`hermes-dashboard.service` starts:

```bash
hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure
```

The default host mapping is `19119`.

### Hermes OpenAI Compatible API

If `HERMES_API_SERVER_KEY` is set, `hermes.service` enables the Hermes API server:

- host: `0.0.0.0`
- internal port: `8642`
- default host port: `18642`

### Hermes SSL Verify Patch

`services/hermes-patch-ssl-verify.py` is a targeted compatibility patch for
Hermes `0.14.x`.

It only patches when Hermes reports version `0.14.*`. The patch teaches Hermes'
keepalive HTTP client to honor `ssl_verify: false` from config or
`HERMES_SSL_VERIFY=false`.

It runs:

- once at image build
- again as `ExecStartPre` before Hermes starts

Running it twice is safe because the script is marker-based and idempotent.

## LiteLLM Integration

LiteLLM is external to this container. The container expects a reachable LiteLLM
proxy through:

```env
LITELLM_URL=
LITELLM_PORT=
LITELLM_API_KEY=
```

Both OpenClaw and Hermes normalize the base URL the same way:

1. strip trailing slash
2. strip trailing `/v1` if present
3. append `:$LITELLM_PORT/v1`

Example:

```text
LITELLM_URL=https://example.local
LITELLM_PORT=888
```

becomes:

```text
https://example.local:888/v1
```

Both services query:

```text
GET /v1/models
Authorization: Bearer $LITELLM_API_KEY
```

OpenClaw writes discovered models into the `litellm` provider in
`openclaw.json`. Hermes writes discovered models into `hermes-home/config.yaml`.

## VikAI

`VikAI` is copied into the image at:

```text
/opt/safrano9999/VikAI
```

The repo contains:

- `SKILLS/`
- `functions/`
- `openclaw-workspace/`
- Vikunja client helpers

The container-side bootstrap script is:

```text
services/vikai-bootstrap-openclaw-agents.py
```

It is called from `openclaw-configure.py` when all three tokens are present:

```env
TOKEN_WORKER=
TOKEN_ARCHITECT=
TOKEN_QC=
```

It provisions three OpenClaw agents:

| Agent | Role | Token Env | Template |
|---|---|---|---|
| `worker` | worker | `TOKEN_WORKER` | `openclaw-workspace/worker` |
| `architect` | architect | `TOKEN_ARCHITECT` | `openclaw-workspace/architect` |
| `qc` | qc | `TOKEN_QC` | `openclaw-workspace/qc` |

For each agent it:

- ensures an OpenClaw agent entry exists
- creates/updates its workspace
- copies the workspace template
- removes `BOOTSTRAP.md`
- writes `.vikai_role`
- writes `.vikunjaenv` with the agent token
- creates `memory/`
- creates `.openclaw/workspace-state.json` if needed
- symlinks the appropriate VikAI skill files
- adds heartbeat config:

```json
{
  "every": "360m",
  "target": "last",
  "directPolicy": "allow"
}
```

The Vikunja target is:

- `VIKUNJA_URL` if explicitly set
- otherwise `VIKUNJA_HOST:641`

The `main` OpenClaw agent is separate from VikAI. It is the default agent and is
used for Telegram routing.

## Included safrano9999 Apps

### CODEANALYST

CODEANALYST runs from:

```text
/opt/safrano9999/CODEANALYST
```

Service:

```text
codeanalyst.service
```

Command:

```bash
uvicorn webui:app --host 0.0.0.0 --port ${CODEANALYST_PORT}
```

Default port:

```text
11000
```

CODEANALYST scans codebases and shows command/program usage, dependencies, and
source references.

### JUGO

JUGO runs from:

```text
/opt/safrano9999/JUGO
```

Service:

```text
jugo.service
```

Command:

```bash
uvicorn webui:app --host 0.0.0.0 --port ${JUGO_PORT}
```

Default port:

```text
11001
```

JUGO is a language-learning UI with translation, TTS, chat, and console flows.
It can use provider keys from `.env` and LiteLLM settings.

### CITADEL

CITADEL runs from:

```text
/opt/safrano9999/CITADEL
```

Services:

- `citadel-setup.service`
- `citadel.service`
- `citadel-scan.service`

Command:

```bash
uvicorn webui:app --host 0.0.0.0 --port ${CITADEL_WEBUI_PORT}
```

Default port:

```text
10999
```

CITADEL is a service dashboard and scanner. In this container profile, the
FastAPI web UI is used. `scan.sh` remains important and the image enables the
`subnet` and `tailscale` extensions when present:

```text
extensions/enabled/subnet
extensions/enabled/tailscale
```

CITADEL-related container privileges are generated from config:

```env
CITADEL_CAPABILITIES=NET_ADMIN,NET_RAW
CITADEL_DEVICES=/dev/net/tun
CITADEL_VOLUMES=tailscale:/var/lib/tailscale
```

### NaturalGrounding

NaturalGrounding runs from:

```text
/opt/safrano9999/NaturalGrounding-Tiktok-Ying-Video-Manager
```

Service:

```text
naturalgrounding.service
```

Command:

```bash
uvicorn webui:app --host 0.0.0.0 --port ${NATURALGROUNDING_PORT}
```

Default port:

```text
11005
```

The app uses SQLAlchemy with Postgres or MariaDB/MySQL. DB credentials come
from `NATURALGROUNDING_DB_*` settings. The video archive path is configured by:

```env
NATURALGROUNDING_VIDEOS_DIR=VIDEOS
NATURALGROUNDING_VOLUMES=./VIDEOS:/opt/safrano9999/NaturalGrounding-Tiktok-Ying-Video-Manager/VIDEOS:Z
```

`NATURALGROUNDING_VOLUMES` is rendered into both generated compose and Quadlet
container files by the existing `*_VOLUMES` config convention.

## Tailscale

Tailscale is optional. If `TS_AUTHKEY` is empty, the Tailscale services are
skipped by `ExecCondition`.

When `TS_AUTHKEY` is set:

1. `tailscaled.service` starts `tailscaled`.
2. `tailscale-up.service` runs:

```bash
tailscale up --authkey="$TS_AUTHKEY" --accept-routes --accept-dns
```

If `TS_HOSTNAME` is set, it adds:

```bash
--hostname="$TS_HOSTNAME"
```

The Tailscale state volume defaults to:

```text
tailscale:/var/lib/tailscale
```

OpenClaw also uses Tailscale information to add Control UI allowed origins.

## Crypto Tools

This container includes several crypto-related tools for local/offline workflows.

### BIP39

The image downloads `bip39-standalone.html` and verifies its SHA256 checksum.
It is served by:

```text
bip39.service
```

Default internal and host port:

```text
11002
```

The service runs:

```bash
python3 -m http.server ${BIP39_PORT} --bind 0.0.0.0
```

### Electrum

The image downloads Electrum AppImage version `4.7.2`, imports release keys,
verifies the `.asc` signature, extracts the AppImage, and exposes:

```bash
electrum
```

as a wrapper around the extracted AppRun.

### LND

The image downloads LND version `v0.20.1-beta`, verifies the configured SHA256
checksum, installs:

```bash
lnd
lncli
```

and verifies both commands during build.

### Geth

The image downloads Geth version `1.17.2` with commit `be4dc0c4`, checks the
configured MD5, imports the release signing key, verifies the `.asc` signature,
and installs:

```bash
geth
```

### Solana CLI

Solana CLI is installed from:

```text
https://release.anza.xyz/stable/install
```

The image verifies installation with:

```bash
solana --version
```

### Solana Air-Gapped Workflow

The `SOLANA_AIRGAPPED_DEBIAN_WORKFLOW` repo is copied into the image at:

```text
/opt/safrano9999/SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
```

It is included as a lightweight shell workflow, not as a systemd web service.
The Fedora image provides the runtime tools used by the scripts:

```bash
solana
solana-keygen
qrencode
zbarcam
bc
```

## Auth And Tokens

Token handling is deliberately environment-based:

- `.env` contains secrets.
- OpenClaw stores `LITELLM_API_KEY`, `TELEGRAMTOKEN_OPENCLAW`, and
  `BRAVE_API_KEY` as environment-backed references.
- Hermes stores the LiteLLM key env name, not the key value.
- VikAI writes each agent token into that agent's workspace `.vikunjaenv`.
- Codex login is persisted by `/fedora/codex-auth/auth.json`; run
  `codex-save-auth` after an interactive container login.

Do not commit `.env`, `config.conf`, generated compose, or generated Quadlet
files.

## Runtime Inspection

Enter the container:

```bash
podman exec -it fedora43-ai bash
```

List listening ports:

```bash
ss -tlpn
```

Check all services:

```bash
systemctl --failed
systemctl status openclaw.service hermes.service
systemctl status codeanalyst.service jugo.service citadel.service
```

Follow logs:

```bash
journalctl -u openclaw.service -f
journalctl -u openclaw-config.service -f
journalctl -u hermes.service -f
journalctl -u hermes-dashboard.service -f
journalctl -u citadel.service -f
```

Restart only OpenClaw:

```bash
systemctl restart openclaw.service
```

Regenerate OpenClaw config, then restart gateway:

```bash
systemctl restart openclaw-config.service
systemctl restart openclaw.service
```

Restart Hermes:

```bash
systemctl restart hermes.service
systemctl restart hermes-dashboard.service
```

## Maintenance

Update repos and regenerate config outputs:

```bash
./setup.sh --config
```

Build locally with normal cache behavior:

```bash
podman build -t localhost/fedora43-ai:latest -f Containerfile .
```

Build locally from scratch:

```bash
./setup.sh --fresh
```

Remove unused images/layers outside this repo with your normal Podman cleanup
workflow.

`clean.sh` is intentionally aggressive: it removes all Podman containers, pods,
and non-default networks visible to the current user. Read it before running it.

## Troubleshooting

### OpenClaw `/models` is slow

Confirm the image patch exists:

```bash
podman exec fedora43-ai rg -n "MODELS_COMMAND_CATALOG_TIMEOUT_MS|loadModelsCommandCatalog|runtimeAuthDiscovery" /usr/local/lib/node_modules/openclaw/dist
```

The expected timeout is:

```text
750ms
```

Restart OpenClaw after a live patch:

```bash
podman exec fedora43-ai systemctl restart openclaw.service
```

### OpenClaw Control UI says browser origin is not allowed

Check generated origins:

```bash
podman exec fedora43-ai jq '.gateway.controlUi.allowedOrigins' /root/.openclaw/openclaw.json
```

Then check:

- `HOST` in `config.conf`
- `OPENCLAW_GATEWAY_PUBLISH_PORT`
- `TS_HOSTNAME`
- Tailscale status inside the container

Restart config and gateway after changing config:

```bash
podman exec fedora43-ai systemctl restart openclaw-config.service
podman exec fedora43-ai systemctl restart openclaw.service
```

### LiteLLM returns 401

Check:

- `LITELLM_API_KEY`
- whether the key exists in the LiteLLM token database
- `LITELLM_URL`
- `LITELLM_PORT`
- whether `/v1/models` works with the same bearer key

Example:

```bash
curl -H "Authorization: Bearer $LITELLM_API_KEY" "$LITELLM_URL:$LITELLM_PORT/v1/models"
```

### Hermes uses the wrong provider

Hermes should use the generated config and `provider: litellm`. Check:

```bash
podman exec fedora43-ai sed -n '1,200p' /root/hermes-home/config.yaml
```

The service should not force `HERMES_INFERENCE_PROVIDER=custom` or
`HERMES_INFERENCE_MODEL=custom/...`.

### VikAI agents are missing

All three tokens must be present:

```env
TOKEN_WORKER=
TOKEN_ARCHITECT=
TOKEN_QC=
```

Then rerun:

```bash
podman exec fedora43-ai systemctl restart openclaw-config.service
podman exec fedora43-ai systemctl restart openclaw.service
```

Check:

```bash
podman exec fedora43-ai jq '.agents.list[].id' /root/.openclaw/openclaw.json
```

Expected:

```text
main
worker
architect
qc
```

## Design Notes

- The container owns runtime composition, not upstream app source.
- App repos stay in `./safrano9999/` for the container build context.
- `env.example` is for secrets and runtime keys.
- `config.conf_example` is for non-secret host/runtime composition.
- `config.sh` comes from `SCRIPTS/safrano9999/config.sh` and is shared infrastructure.
- OpenClaw source patching and container image patching are separate:
  - upstream OpenClaw gets source and tests
  - this image gets a build-time dist patch until upstream includes it
- OpenClaw config and OpenClaw gateway are separate services:
  - `openclaw-config.service`
  - `openclaw.service`
- The `/models` patch is not a service; it is applied during image build.
- Hermes config and Hermes runtime are handled through pre-start scripts in
  `hermes.service`.
- Published ports are controlled outside the container by compose/Quadlet.
- Internal services bind to `0.0.0.0` because access is controlled by published
  port mappings.
