#!/bin/sh
set -e

PORT="${PORT:-8000}"
ACCESS_MODE="${ACCESS_MODE:-restricted}"

if [ -z "${GRAFANA_URL:-}" ]; then
  echo "mcp: GRAFANA_URL is required (e.g. http://grafana.railway.internal:3000)" >&2
  exit 1
fi

# mcp-grafana reads its Grafana credentials straight from the environment, so
# both supported auth methods work with no flags. Fail here rather than let the
# server start and 401 on every tool call.
if [ -n "${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "mcp: authenticating to Grafana with a service account token" >&2
elif [ -n "${GRAFANA_USERNAME:-}" ] && [ -n "${GRAFANA_PASSWORD:-}" ]; then
  echo "mcp: authenticating to Grafana as ${GRAFANA_USERNAME} (basic auth)" >&2
else
  echo "mcp: set GRAFANA_SERVICE_ACCOUNT_TOKEN, or both GRAFANA_USERNAME and GRAFANA_PASSWORD" >&2
  exit 1
fi

case "$ACCESS_MODE" in
  restricted)
    # Grafana-API boundary: read-only tools only, so a leaked gateway key still
    # cannot mutate dashboards, alert rules or incidents.
    WRITE_FLAG="--disable-write"
    ;;
  unrestricted)
    WRITE_FLAG=""
    ;;
  *)
    echo "mcp: ACCESS_MODE must be 'restricted' or 'unrestricted', got '${ACCESS_MODE}'" >&2
    exit 1
    ;;
esac

ENABLED_TOOLS_FLAG=""
if [ -n "${ENABLED_TOOLS:-}" ]; then
  ENABLED_TOOLS_FLAG="--enabled-tools=${ENABLED_TOOLS}"
fi

LOG_LEVEL_FLAG=""
if [ -n "${LOG_LEVEL:-}" ]; then
  LOG_LEVEL_FLAG="--log-level=${LOG_LEVEL}"
fi

# mcp-grafana rejects any request whose Host header is outside --allowed-hosts
# (403, on every route). The gateway rewrites Host to 127.0.0.1:${PORT}; set the
# allowlist explicitly rather than relying on the value derived from --address.
# Word splitting on the optional flags is intentional — they are empty or one token.
# shellcheck disable=SC2086
exec /app/mcp-grafana \
  --transport=streamable-http \
  --address="0.0.0.0:${PORT}" \
  --allowed-hosts="127.0.0.1:${PORT},localhost:${PORT},[::1]:${PORT}" \
  ${WRITE_FLAG} ${ENABLED_TOOLS_FLAG} ${LOG_LEVEL_FLAG}
