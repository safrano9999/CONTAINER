# Thunderbird MCP container

Private combined image based on `jlesage/thunderbird:v26.08.1`. It contains
Thunderbird MCP `v0.7.4`, its Node bridge, and Supergateway `3.4.3`.

Image: `ghcr.io/safrano9999/thunderbird-mcp-alpine:v0.7.4`

Endpoints:

- Thunderbird web UI: `http://127.0.0.1:11120`
- MCP Streamable HTTP: `http://127.0.0.1:11121/mcp`
- MCP health check: `http://127.0.0.1:11121/healthz`

`/config` is the required persistent Thunderbird profile. `/exchange` is an
optional host-visible directory for files attached to outgoing messages. The
upstream extension saves decoded incoming attachments below
`/tmp/thunderbird-mcp/<message-id>/`; it does not currently accept a custom
save directory.

Run `./setup.sh` to configure and pull the private GHCR image. Container builds
and pushes are performed exclusively by GitHub Actions. The script prints the
Quadlet link command but does not install or start the user service
automatically.
