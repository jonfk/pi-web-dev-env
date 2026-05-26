#!/usr/bin/env bash
set -euo pipefail

state_dir="${HOME}/.pi-web-dev-env"
marker_file="${state_dir}/bootstrap.done"
ssh_dir="${HOME}/.ssh"
ssh_key="${ssh_dir}/id_ed25519"
user_bootstrap="/usr/local/share/pi-web-dev-env/user-bootstrap.sh"

if [[ -f "${marker_file}" ]]; then
  exit 0
fi

mkdir -p "${state_dir}" "${ssh_dir}" "${HOME}/.config"
chmod 0700 "${ssh_dir}"

if [[ -f "${ssh_key}" ]]; then
  chmod 0600 "${ssh_key}" 2>/dev/null || true

  if [[ ! -f "${ssh_dir}/config" ]]; then
    cat > "${ssh_dir}/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
    chmod 0600 "${ssh_dir}/config"
  fi

  ssh-keyscan github.com >> "${ssh_dir}/known_hosts" 2>/dev/null || true
  sort -u "${ssh_dir}/known_hosts" -o "${ssh_dir}/known_hosts" 2>/dev/null || true
  chmod 0644 "${ssh_dir}/known_hosts" 2>/dev/null || true
fi

if [[ -f "${user_bootstrap}" ]]; then
  bash "${user_bootstrap}"
fi

touch "${marker_file}"
