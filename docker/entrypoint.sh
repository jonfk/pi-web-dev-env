#!/usr/bin/env bash
set -euo pipefail

write_wede_config() {
  local config_dir="${HOME}/.config/wede"
  local password="${WEDE_PASSWORD:-admin}"
  local port="${WEDE_PORT:-9090}"

  mkdir -p "${config_dir}"
  jq -n --arg password "${password}" --arg port "${port}" \
    '{password: $password, port: $port}' > "${config_dir}/wede.config.json"
}

case "${1:-}" in
  pipane)
    shift
    cd /opt/pipane
    exec node bin/pipane.js "$@"
    ;;
  wede)
    shift
    write_wede_config
    exec wede --port "${WEDE_PORT:-9090}" "${WEDE_WORKSPACE:-/workspace}" "$@"
    ;;
  pi)
    shift
    exec pi "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
