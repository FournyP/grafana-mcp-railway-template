# Changelog

Notable changes to this template. Entries are named after the mcp-grafana version they
ship, or after the change itself when a release only touches this template. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Infrastructure as Code — 2026-09-06

### Added

- `.railway/railway.ts`, an Infrastructure as Code definition of the project. See
  [Infrastructure as Code](README.md#-infrastructure-as-code).
- An `iac-typecheck` workflow, alongside the existing `docker-build` one.

## mcp-grafana 1.3.0 — 2026-09-03

### Added

- Initial release. Two services: an nginx gateway holding a public domain and validating
  `Authorization: Bearer <key>` against `API_KEYS`, and a private mcp service running the
  official `grafana/mcp-grafana` image with `--transport=streamable-http`.
- `ACCESS_MODE=restricted` (the default) passes `--disable-write`, so a leaked gateway key
  cannot mutate dashboards, alert rules or incidents.
- Optional second auth layer: set `MCP_GRAFANA_SERVER_TOKEN` on the mcp service and a
  matching `MCP_SERVER_TOKEN` on the gateway to rotate gateway keys independently.
- Optional `PATH_KEY_AUTH=true` accepts the key as a path segment (`/k/<key>/mcp`) for
  clients that cannot send an `Authorization` header.
