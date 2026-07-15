#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/mattermost}
REPO_DIR=${REPO_DIR:-$(pwd)}
INSTALL_PACKAGES=${INSTALL_PACKAGES:-true}
COPY_ASSETS=${COPY_ASSETS:-true}
INSTALL_TIMERS=${INSTALL_TIMERS:-true}
INSTALL_KSPLICE=${INSTALL_KSPLICE:-true}
REQUIRE_KSPLICE=${REQUIRE_KSPLICE:-false}

if [ ! -f "$REPO_DIR/templates/compose.yml" ]; then
  echo "Run this from the repo root or set REPO_DIR=/path/to/repo." >&2
  exit 64
fi

if [ "$INSTALL_PACKAGES" = "true" ]; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg python3-venv python3-pip unattended-upgrades apt-listchanges ufw fail2ban

  sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  sudo tee /etc/apt/apt.conf.d/52mattermost-security-upgrades >/dev/null <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
// Servers: install security updates even while Ubuntu is still phasing them.
APT::Get::Always-Include-Phased-Updates "true";
EOF

  sudo install -m 0644 "$REPO_DIR/templates/apt/50unattended-upgrades-mattermost" /etc/apt/apt.conf.d/50unattended-upgrades-mattermost

  sudo install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker ubuntu

  if ! command -v oci >/dev/null 2>&1; then
    sudo python3 -m venv /opt/oci-cli
    sudo /opt/oci-cli/bin/pip install --upgrade pip
    sudo /opt/oci-cli/bin/pip install oci-cli
    sudo ln -sf /opt/oci-cli/bin/oci /usr/local/bin/oci
  fi

  if [ "$INSTALL_KSPLICE" = "true" ]; then
    if command -v uptrack-upgrade >/dev/null 2>&1; then
      echo "Ksplice already installed."
    elif curl -fsSL https://ksplice.oracle.com/uptrack/install-uptrack-oc -o /tmp/install-uptrack-oc; then
      if sudo sh /tmp/install-uptrack-oc --autoinstall; then
        rm -f /tmp/install-uptrack-oc
      else
        rm -f /tmp/install-uptrack-oc
        if [ "$REQUIRE_KSPLICE" = "true" ]; then
          echo "Ksplice installation failed." >&2
          exit 70
        fi
        echo "WARN: Ksplice installation failed; continuing." >&2
      fi
    elif [ "$REQUIRE_KSPLICE" = "true" ]; then
      echo "Ksplice installer download failed." >&2
      exit 70
    else
      echo "WARN: Ksplice installer download failed; continuing." >&2
    fi

    if [ -f /etc/uptrack/uptrack.conf ]; then
      sudo sed -i 's/^autoinstall[[:space:]]*=.*/autoinstall = yes/' /etc/uptrack/uptrack.conf
    fi
    if command -v uptrack-upgrade >/dev/null 2>&1; then
      if ! sudo uptrack-upgrade -y && [ "$REQUIRE_KSPLICE" = "true" ]; then
        echo "Ksplice update application failed." >&2
        exit 70
      fi
    fi
  fi
fi

sudo mkdir -p "$APP_DIR"/{caddy,mattermost-arm64,postgres/init,ops/lib,backups,rclone}
sudo chown -R ubuntu:ubuntu "$APP_DIR"

if [ "$COPY_ASSETS" = "true" ]; then
  cp "$REPO_DIR/templates/compose.yml" "$APP_DIR/compose.yml"
  cp "$REPO_DIR/templates/Caddyfile" "$APP_DIR/caddy/Caddyfile"
  cp "$REPO_DIR/templates/mattermost-arm64.Dockerfile" "$APP_DIR/mattermost-arm64/Dockerfile"
  cp "$REPO_DIR/templates/mattermost-entrypoint.sh" "$APP_DIR/mattermost-arm64/entrypoint.sh"
  cp "$REPO_DIR/templates/postgres-init.sh" "$APP_DIR/postgres/init/001-create-mattermost-dbs.sh"
  cp "$REPO_DIR/templates/rclone/rclone.conf.tpl" "$APP_DIR/rclone/rclone.conf.tpl"
  cp "$REPO_DIR/scripts/backup-mattermost.sh" "$APP_DIR/ops/backup-mattermost.sh"
  cp "$REPO_DIR/scripts/download-backup.sh" "$APP_DIR/ops/download-backup.sh"
  cp "$REPO_DIR/scripts/restore-test-from-backup.sh" "$APP_DIR/ops/restore-test-from-backup.sh"
  cp "$REPO_DIR/scripts/restore-production-from-backup.sh" "$APP_DIR/ops/restore-production-from-backup.sh"
  cp "$REPO_DIR/scripts/health-check.sh" "$APP_DIR/ops/health-check.sh"
  cp "$REPO_DIR/scripts/harden-host.sh" "$APP_DIR/ops/harden-host.sh"
  cp "$REPO_DIR/scripts/build-mattermost-image.sh" "$APP_DIR/ops/build-mattermost-image.sh"
  cp "$REPO_DIR/scripts/security-audit.sh" "$APP_DIR/ops/security-audit.sh"
  cp "$REPO_DIR/scripts/app-audit.sh" "$APP_DIR/ops/app-audit.sh"
  cp "$REPO_DIR/scripts/install-calls-plugin.sh" "$APP_DIR/ops/install-calls-plugin.sh"
  cp "$REPO_DIR/scripts/install-community-admin-plugin.sh" "$APP_DIR/ops/install-community-admin-plugin.sh"
  cp "$REPO_DIR/scripts/manage-test-instance.sh" "$APP_DIR/ops/manage-test-instance.sh"
  cp "$REPO_DIR/scripts/scheduled-reboot.sh" "$APP_DIR/ops/scheduled-reboot.sh"
  cp "$REPO_DIR/scripts/upgrade-caddy.sh" "$APP_DIR/ops/upgrade-caddy.sh"
  cp "$REPO_DIR/scripts/check-updates.sh" "$APP_DIR/ops/check-updates.sh"
  cp "$REPO_DIR/scripts/post-maintenance-report.sh" "$APP_DIR/ops/post-maintenance-report.sh"
  cp "$REPO_DIR/scripts/manage-community-users.sh" "$APP_DIR/ops/manage-community-users.sh"
  cp "$REPO_DIR/scripts/configure-push-notifications.sh" "$APP_DIR/ops/configure-push-notifications.sh"
  cp "$REPO_DIR/scripts/diagnose-push-notifications.sh" "$APP_DIR/ops/diagnose-push-notifications.sh"
  cp "$REPO_DIR/scripts/render-rclone-config.sh" "$APP_DIR/ops/render-rclone-config.sh"
  cp "$REPO_DIR/templates/postgres/README.md" "$APP_DIR/postgres/README.md"
  cp "$REPO_DIR/scripts/lib/common.sh" "$APP_DIR/ops/lib/common.sh"
  cp "$REPO_DIR/templates/sshd/99-mattermost-hardening.conf" "$APP_DIR/ops/99-mattermost-hardening.conf"
  chmod 755 "$APP_DIR/mattermost-arm64/entrypoint.sh" "$APP_DIR/postgres/init/001-create-mattermost-dbs.sh"
  chmod 750 "$APP_DIR/ops/"*.sh
fi

if [ ! -f "$APP_DIR/.env" ]; then
  cp "$REPO_DIR/templates/env.example" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  echo "Created $APP_DIR/.env from template. Edit it before starting the stack."
fi

if [ -f "$APP_DIR/.env" ] && [ -f "$APP_DIR/ops/render-rclone-config.sh" ]; then
  if grep -q '^OBJECT_STORAGE_NAMESPACE=' "$APP_DIR/.env" && grep -q '^COMPARTMENT_OCID=' "$APP_DIR/.env"; then
    APP_DIR="$APP_DIR" "$APP_DIR/ops/render-rclone-config.sh" || true
  fi
fi

if [ "$INSTALL_TIMERS" = "true" ]; then
  for unit in \
    mattermost-backup.service mattermost-backup.timer \
    mattermost-health.service mattermost-health.timer \
    mattermost-reboot.service mattermost-reboot.timer \
    mattermost-caddy-update.service mattermost-caddy-update.timer \
    mattermost-update-check.service mattermost-update-check.timer \
    mattermost-post-maintenance.service mattermost-post-maintenance.timer; do
    sudo install -m 0644 "$REPO_DIR/templates/systemd/$unit" "/etc/systemd/system/$unit"
  done
  sudo systemctl daemon-reload
  sudo systemctl enable --now \
    mattermost-backup.timer \
    mattermost-health.timer \
    mattermost-reboot.timer \
    mattermost-caddy-update.timer \
    mattermost-update-check.timer \
    mattermost-post-maintenance.timer
fi

if [ -f "$REPO_DIR/templates/apt/50unattended-upgrades-mattermost" ]; then
  sudo install -m 0644 "$REPO_DIR/templates/apt/50unattended-upgrades-mattermost" /etc/apt/apt.conf.d/50unattended-upgrades-mattermost
fi

if [ "$INSTALL_PACKAGES" = "true" ]; then
  sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades
fi

echo "Bootstrap complete. Next:"
echo "  1. Edit $APP_DIR/.env"
echo "  2. Render real Caddyfile hostnames if using env placeholders"
echo "  3. Run: cd $APP_DIR && docker compose -f compose.yml build mattermost-prod && docker compose -f compose.yml up -d"
echo "  4. Check timers: systemctl list-timers 'mattermost-*'"
echo "  5. Harden host after verifying SSH: sudo ADMIN_ALLOWED_CIDR=<your-ip>/32 $APP_DIR/ops/harden-host.sh"
