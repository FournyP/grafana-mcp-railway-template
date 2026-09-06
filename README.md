# Grafana MCP Railway Template

Deploys [mcp-grafana](https://github.com/grafana/mcp-grafana) — Grafana's official MCP server, giving AI agents your dashboards, datasources, Prometheus/Loki queries, alert rules, incidents and Sift investigations — behind an NGINX bearer-token auth gateway.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/grafana-mcp?referralCode=C3Uv6n&utm_medium=integration&utm_source=template&utm_campaign=generic)

## 🏗️ Architecture

```
client ──Authorization: Bearer <key>──► grafana-mcp-gateway (nginx, public)
                                              │
                                              ▼ private network
                                 grafana-mcp (private) ──► Grafana
```

Two Railway services:

- **`grafana-mcp-gateway`** — `nginx:1.29.8-alpine`, exposes a public domain, validates the `Authorization: Bearer <key>` header against `API_KEYS`, and forwards streamable-HTTP traffic to the mcp service via Railway's private network.
- **`grafana-mcp`** — the official `grafana/mcp-grafana` image at a pinned tag, run with `--transport=streamable-http`. **Do not give this service a public domain**; it is only reachable at `grafana-mcp.railway.internal:8000`.

The gateway talks to Grafana through nothing but the mcp service, and the mcp service reaches Grafana over `GRAFANA_URL` — point that at your Grafana's private endpoint so Grafana itself never needs to be public either.

## ✨ Features

- Bearer-token auth with a comma-separated allowlist of keys
- Streamable HTTP passthrough (`/mcp`)
- Unauthenticated `/health` (and `/healthz`) on the gateway for Railway healthchecks
- Grafana-API access mode (`restricted` by default) as defense-in-depth on top of the network-level bearer auth
- Both Grafana auth methods: service account token, or username + password
- Optional keyed-path entrypoint for MCP clients that cannot send an `Authorization` header
- Zero custom code — gateway is plain nginx, mcp is the upstream official image

## 💁‍♀️ How to use

1. Click the Railway button 👆
2. Fill in the variables (see below)
3. Deploy! 🚄
4. Point your MCP client at `https://<gateway-domain>/mcp` (streamable-HTTP, `"type": "http"`) with header `Authorization: Bearer <your-key>`. Quick check:
   ```bash
   curl -sS -X POST https://<gateway-domain>/mcp \
     -H "Authorization: Bearer <your-key>" \
     -H "Content-Type: application/json" \
     -H "Accept: application/json, text/event-stream" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
   ```

## 🔧 Variables

### Gateway service

| Variable           | Required | Description                                                                                                                                     |
| ------------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `API_KEYS`         | yes      | Comma-separated list of allowed bearer tokens. Allowed chars per key: `A-Z a-z 0-9 . _ ~ + / = -`                                               |
| `MCP_HOST`         | no       | Defaults to `grafana-mcp.railway.internal`. Only override if you rename the mcp service.                                                        |
| `MCP_PORT`         | no       | Defaults to `8000`.                                                                                                                             |
| `MCP_SERVER_TOKEN` | no       | Credential the gateway presents to the mcp service, replacing the client's own header. Must equal the mcp service's `MCP_GRAFANA_SERVER_TOKEN`. |
| `PATH_KEY_AUTH`    | no       | `true` enables the keyed-path entrypoint (see below). Default `false`.                                                                          |

### MCP service

| Variable                                | Required | Description                                                                                                                                                                            |
| --------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GRAFANA_URL`                           | yes      | Base URL of your Grafana, e.g. `http://grafana.railway.internal:3000`                                                                                                                  |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN`         | one of   | Grafana service account token. Recommended — permissions are scoped to the service account.                                                                                            |
| `GRAFANA_USERNAME` + `GRAFANA_PASSWORD` | one of   | Basic auth. Use when creating a service account is impractical (e.g. wiring straight to `${{Grafana.GF_SECURITY_ADMIN_USER}}` / `${{Grafana.GF_SECURITY_ADMIN_PASSWORD}}` on Railway). |
| `ACCESS_MODE`                           | no       | `restricted` (default) passes `--disable-write`, so no tool can mutate Grafana. Set to `unrestricted` for full read/write.                                                             |
| `MCP_GRAFANA_SERVER_TOKEN`              | no       | Bearer token mcp-grafana itself requires from callers. Pair with the gateway's `MCP_SERVER_TOKEN`.                                                                                     |
| `ENABLED_TOOLS`                         | no       | Comma-separated allowlist of tool categories, e.g. `loki,prometheus,dashboard`. All enabled by default.                                                                                |
| `LOG_LEVEL`                             | no       | `debug` / `info` (default) / `warn` / `error`                                                                                                                                          |
| `PORT`                                  | no       | Defaults to `8000`. Railway injects this.                                                                                                                                              |

Set exactly one of the two Grafana auth options — the mcp service refuses to start with neither.

## 🔑 Keyed-path entrypoint (opt-in)

Some MCP clients enumerate a server's tools before they have anywhere to store a
credential, so their discovery request arrives with no `Authorization` header and
takes a `401`. Setting `PATH_KEY_AUTH=true` on the gateway adds a second way in:

```
https://<gateway-domain>/k/<your-key>/mcp
```

The key is validated against the same `API_KEYS` allowlist. An absent or wrong
key is still `401`, and a valid key unlocks nothing but `/mcp` — the key segment
is stripped before proxying, so the mcp service only ever sees `/mcp`.

**The key travels in the URL**, where it can be recorded by edge and proxy logs
outside your control (the gateway itself logs nothing for this path). So:

- Issue a **separate key** in `API_KEYS` for each client that uses this path, so
  it can be rotated without touching the others.
- Leave `PATH_KEY_AUTH` off and use the header form everywhere else.
- Keys used on this path may not contain `/` (the header form allows it), since
  a slash would split the path segment.

If you also set `MCP_GRAFANA_SERVER_TOKEN` on the mcp service, you **must** set
`MCP_SERVER_TOKEN` on the gateway — a keyed-path request has no `Authorization`
header of its own for the upstream to validate.

## 🔒 Two layers of protection

- **Bearer auth at the gateway** is the network boundary — nothing reaches the MCP without a valid key.
- **`ACCESS_MODE=restricted`** is the Grafana-API boundary — even if a key leaks, the attacker cannot create or modify dashboards, alert rules, annotations or incidents.

A third layer is available: set `MCP_GRAFANA_SERVER_TOKEN` on the mcp service and the matching `MCP_SERVER_TOKEN` on the gateway. mcp-grafana then rejects anything that did not come through the gateway, and it stops logging the security error it emits on startup whenever a networked transport runs without caller authentication.

## 📝 Notes

- **Generate strong keys:** `openssl rand -hex 32`
- **Rotating a key:** update `API_KEYS` on the gateway service and redeploy it. The mcp service is untouched.
- **`/health` and `/healthz` are unauthenticated** so Railway (and any uptime monitor) can probe without a token. Everything else requires `Authorization: Bearer <key>`.
- **Invalid / missing token:** the gateway returns `401` with a `WWW-Authenticate: Bearer realm="grafana-mcp"` header.
- **Do not expose the mcp service publicly.** All traffic should enter through the gateway.
- **`Origin` headers are rejected** by mcp-grafana by default, so browser-based clients cannot call this server directly. That is upstream's anti-DNS-rebinding default, not a gateway setting.
- Upstream source: https://github.com/grafana/mcp-grafana — pinned via the tag in `mcp/Dockerfile`. Bump it to pick up upstream changes.

## ⚖️ License

[MIT](LICENSE)
