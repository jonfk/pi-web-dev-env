#!/usr/bin/env bash
set -euo pipefail

drop_to_assistant_user() {
  if [[ "$(id -u)" != "0" ]]; then
    return
  fi

  local assistant_user="${ASSISTANT_USER:-ubuntu}"
  local assistant_home
  assistant_home="$(getent passwd "${assistant_user}" | cut -d: -f6)"

  chown "${assistant_user}:${assistant_user}" \
    "${assistant_home}/.pi" \
    "${assistant_home}/.cargo" \
    "${assistant_home}/.config" \
    "${assistant_home}/.local" \
    "${assistant_home}/.ssh"

  exec sudo -H -E -u "${assistant_user}" -- "$0" "$@"
}

write_wede_config() {
  local config_dir="${HOME}/.config/wede"
  local password="${WEDE_PASSWORD:-admin}"
  local port="${WEDE_PORT:-9090}"
  local auth_disabled="false"

  case "${WEDE_AUTH_DISABLED:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      auth_disabled="true"
      ;;
  esac

  mkdir -p "${config_dir}"
  jq -n --arg password "${password}" --arg port "${port}" --argjson authDisabled "${auth_disabled}" \
    '{password: $password, port: $port, authDisabled: $authDisabled}' > "${config_dir}/wede.config.json"
}

run_bootstrap() {
  if [[ -x /usr/local/bin/pi-web-dev-env-bootstrap ]]; then
    /usr/local/bin/pi-web-dev-env-bootstrap
  fi
}

drop_to_assistant_user "$@"
run_bootstrap

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
  pi-webui)
    shift
    cd /opt/pi-webui
    exec node dist/server/index.js "$@"
    ;;
  pi)
    shift
    exec pi "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
