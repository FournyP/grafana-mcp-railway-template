#!/bin/sh
set -eu

: "${API_KEYS:?API_KEYS is required (comma-separated list of allowed bearer tokens)}"
: "${MCP_HOST:=grafana-mcp.railway.internal}"
: "${MCP_PORT:=8000}"
: "${PORT:=80}"
: "${PATH_KEY_AUTH:=false}"

# Validate each key. Keys are interpolated into an nginx map regex, so we
# restrict to characters that are safe inside a regex alternation group.
# Allowed: A-Z a-z 0-9 . _ ~ + / = -   (covers base64, base64url, hex, UUID)
check_charset() {
  case "$1" in
    *[!A-Za-z0-9._~+/=-]*)
      echo "gateway: $2 contains an invalid character; allowed: A-Z a-z 0-9 . _ ~ + / = -" >&2
      return 1
      ;;
  esac
}

echo "$API_KEYS" | tr ',' '\n' | while IFS= read -r key; do
  [ -z "$key" ] && continue
  check_charset "$key" API_KEYS || exit 1
done

API_KEY_PATTERN=$(echo "$API_KEYS" | tr ',' '\n' | sed '/^$/d' | paste -sd '|' -)
if [ -z "$API_KEY_PATTERN" ]; then
  echo "gateway: API_KEYS must contain at least one non-empty key" >&2
  exit 1
fi
export API_KEY_PATTERN

# Railway private DNS (*.railway.internal) is IPv6-only; pick up the container's
# nameserver from resolv.conf so nginx can resolve it.
RESOLVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
: "${RESOLVER:=127.0.0.11}"
# nginx requires IPv6 resolver addresses wrapped in brackets (otherwise the
# trailing `:xx` is parsed as a port). Railway's resolv.conf is IPv6.
case "$RESOLVER" in
  *:*) RESOLVER="[$RESOLVER]" ;;
esac
export RESOLVER

# Optional second auth layer: mcp-grafana validates this itself via
# MCP_GRAFANA_SERVER_TOKEN. Injecting it here (rather than passing the client's
# header through) keeps the gateway's API_KEYS rotatable on their own, and is
# what lets the keyed path — which carries no Authorization header — reach an
# mcp service that requires one.
if [ -n "${MCP_SERVER_TOKEN:-}" ]; then
  check_charset "$MCP_SERVER_TOKEN" MCP_SERVER_TOKEN || exit 1
  MCP_AUTH_HEADER="proxy_set_header Authorization \"Bearer ${MCP_SERVER_TOKEN}\";"
else
  MCP_AUTH_HEADER=""
fi
export MCP_AUTH_HEADER

export MCP_HOST MCP_PORT PORT

VARS='${API_KEY_PATTERN} ${RESOLVER} ${MCP_HOST} ${MCP_PORT} ${PORT} ${MCP_AUTH_HEADER}'

envsubst "$VARS" < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# nginx has no config-level conditionals, so the keyed-path block is gated
# here instead. The main config includes /etc/nginx/path-key.conf
# unconditionally, so the file must exist either way — empty when disabled.
case "$PATH_KEY_AUTH" in
  1|true|TRUE|True|yes|YES)
    echo "gateway: keyed-path entrypoint enabled (/k/<key>/mcp)" >&2
    envsubst "$VARS" < /etc/nginx/path-key.conf.template > /etc/nginx/path-key.conf
    ;;
  *)
    : > /etc/nginx/path-key.conf
    ;;
esac
