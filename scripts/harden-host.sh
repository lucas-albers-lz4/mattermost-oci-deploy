#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/mattermost}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADMIN_ALLOWED_CIDR=${ADMIN_ALLOWED_CIDR:-}
SSH_PORT=${SSH_PORT:-22}
APPLY_SSHD_HARDENING=${APPLY_SSHD_HARDENING:-false}
ENABLE_CALLS_PORT=${ENABLE_CALLS_PORT:-true}

if [ -z "${SSHD_TEMPLATE:-}" ]; then
  if [ -f "$SCRIPT_DIR/../templates/sshd/99-mattermost-hardening.conf" ]; then
    SSHD_TEMPLATE="$SCRIPT_DIR/../templates/sshd/99-mattermost-hardening.conf"
  else
    SSHD_TEMPLATE="$SCRIPT_DIR/99-mattermost-hardening.conf"
  fi
fi

if [ -z "$ADMIN_ALLOWED_CIDR" ]; then
  echo "Set ADMIN_ALLOWED_CIDR to your admin public IP/CIDR, for example 198.51.100.10/32." >&2
  exit 64
fi

case "$SSH_PORT" in
  ''|*[!0-9]*)
    echo "SSH_PORT must be numeric." >&2
    exit 64
    ;;
esac

echo "[harden-host] configuring UFW"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from "$ADMIN_ALLOWED_CIDR" to any port "$SSH_PORT" proto tcp comment "admin ssh"
sudo ufw allow 80/tcp comment "http acme"
sudo ufw allow 443/tcp comment "https"
if [ "$ENABLE_CALLS_PORT" = "true" ]; then
  sudo ufw allow 8443/udp comment "mattermost calls"
fi
sudo ufw --force enable
sudo ufw status verbose

if command -v fail2ban-client >/dev/null 2>&1; then
  echo "[harden-host] enabling fail2ban"
  sudo systemctl enable --now fail2ban
fi

if [ "$APPLY_SSHD_HARDENING" = "true" ]; then
  if [ ! -f "$SSHD_TEMPLATE" ]; then
    echo "SSH hardening template not found: $SSHD_TEMPLATE" >&2
    exit 66
  fi

  echo "[harden-host] installing SSH hardening drop-in"
  sudo install -m 0644 "$SSHD_TEMPLATE" /etc/ssh/sshd_config.d/99-mattermost-hardening.conf
  sudo sshd -t

  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    sudo systemctl reload ssh
  else
    sudo systemctl reload sshd
  fi

  echo "[harden-host] open a second SSH session before closing this one"
else
  echo "[harden-host] SSH hardening not applied. Set APPLY_SSHD_HARDENING=true after verifying key-based SSH."
fi
