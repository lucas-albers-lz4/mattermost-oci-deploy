#!/usr/bin/env bash
# shellcheck disable=SC2029
set -euo pipefail

MODE=
RESTORE_TS=
TOFU_DIR=${TOFU_DIR:-infra/opentofu}
APP_DIR=${APP_DIR:-/opt/mattermost}
REMOTE_USER=${REMOTE_USER:-ubuntu}
REMOTE_DEPLOY_DIR=${REMOTE_DEPLOY_DIR:-$APP_DIR/deploy}
ENV_OUT=${ENV_OUT:-generated.env}
SECRETS_FILE=${SECRETS_FILE:-.mattermost-secrets.env}
SSH_REMOTE_OPTS=${SSH_REMOTE_OPTS:-}
AUTO_CONFIRM_DNS=${AUTO_CONFIRM_DNS:-${AUTO_CONFIRM_DUCKDNS:-false}}
DNS_VERIFY_TIMEOUT_SECONDS=${DNS_VERIFY_TIMEOUT_SECONDS:-300}
DNS_VERIFY_INTERVAL_SECONDS=${DNS_VERIFY_INTERVAL_SECONDS:-10}
APPLY_HOST_HARDENING=${APPLY_HOST_HARDENING:-true}
APPLY_SSHD_HARDENING=${APPLY_SSHD_HARDENING:-true}

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy-from-zero.sh --fresh
  scripts/deploy-from-zero.sh --restore <backup-timestamp>

DNS is intentionally manual. The script prints the required DNS update and waits for confirmation.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fresh)
      MODE=fresh
      shift
      ;;
    --restore)
      MODE=restore
      RESTORE_TS=${2:-}
      [ -n "$RESTORE_TS" ] || { usage >&2; exit 64; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

[ -n "$MODE" ] || { usage >&2; exit 64; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "required command not found: $1" >&2; exit 69; }
}

json_get() {
  key=$1
  file=$2
  python3 - "$key" "$file" <<'PY'
import json
import sys

key, path = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get(key, {}).get("value", ""))
PY
}

dns_points_to_ip() {
  hostname=$1
  expected_ip=$2

  python3 - "$hostname" "$expected_ip" <<'PY'
import socket
import sys

hostname, expected_ip = sys.argv[1], sys.argv[2]
try:
    records = socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM)
except socket.gaierror:
    sys.exit(1)

resolved_ips = {record[4][0] for record in records}
sys.exit(0 if expected_ip in resolved_ips else 1)
PY
}

wait_for_dns() {
  expected_ip=$1
  shift
  elapsed=0

  echo "Verifying DNS resolves to $expected_ip..."
  while [ "$elapsed" -le "$DNS_VERIFY_TIMEOUT_SECONDS" ]; do
    all_ready=true
    for hostname in "$@"; do
      if dns_points_to_ip "$hostname" "$expected_ip"; then
        echo "  $hostname -> $expected_ip"
      else
        echo "  waiting for $hostname -> $expected_ip"
        all_ready=false
      fi
    done

    [ "$all_ready" = "true" ] && return 0
    sleep "$DNS_VERIFY_INTERVAL_SECONDS"
    elapsed=$((elapsed + DNS_VERIFY_INTERVAL_SECONDS))
  done

  echo "DNS did not resolve to $expected_ip within ${DNS_VERIFY_TIMEOUT_SECONDS}s." >&2
  echo "Update DNS for: $*" >&2
  return 1
}

require_command tofu
require_command python3
require_command rsync
require_command ssh

tofu -chdir="$TOFU_DIR" init
tofu -chdir="$TOFU_DIR" apply -auto-approve

outputs=$(mktemp)
tofu -chdir="$TOFU_DIR" output -json > "$outputs"

public_ip=$(json_get public_ip "$outputs")
prod_hostname=$(json_get prod_hostname "$outputs")
test_hostname=$(json_get test_hostname "$outputs")
dns_step=$(json_get dns_manual_step "$outputs")

TEST_ALLOWED_CIDR=${TEST_ALLOWED_CIDR:?Set TEST_ALLOWED_CIDR to your admin public IP/CIDR before running.}
OUTPUT_FILE="$outputs" ENV_OUT="$ENV_OUT" SECRETS_FILE="$SECRETS_FILE" TEST_ALLOWED_CIDR="$TEST_ALLOWED_CIDR" ./scripts/render-env.sh

echo
echo "Manual DNS checkpoint:"
echo "  $dns_step"
echo
if [ "$AUTO_CONFIRM_DNS" = "true" ]; then
  echo "AUTO_CONFIRM_DNS=true; continuing without prompt."
else
  echo "After updating DNS, press Enter to continue."
  read -r _
fi

wait_for_dns "$public_ip" "$prod_hostname" "$test_hostname"

echo "Waiting for SSH on $public_ip..."
for _ in $(seq 1 60); do
  # shellcheck disable=SC2086
  if ssh $SSH_REMOTE_OPTS -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$public_ip" true 2>/dev/null; then
    break
  fi
  sleep 10
done
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_USER@$public_ip" true

echo "Syncing repo to $REMOTE_USER@$public_ip:$REMOTE_DEPLOY_DIR"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "mkdir -p '$REMOTE_DEPLOY_DIR'"
# shellcheck disable=SC2086
rsync -az --delete \
  -e "ssh $SSH_REMOTE_OPTS" \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude '*.tfstate*' \
  --exclude '*.tfvars' \
  --exclude 'tfplan' \
  --exclude '.mattermost-secrets.env' \
  --exclude 'generated.env' \
  ./ "$REMOTE_USER@$public_ip:$REMOTE_DEPLOY_DIR/"

echo "Installing rendered env"
# shellcheck disable=SC2086
scp $SSH_REMOTE_OPTS "$ENV_OUT" "$REMOTE_USER@$public_ip:/tmp/mattermost.env"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "sudo install -m 0600 -o ubuntu -g ubuntu /tmp/mattermost.env '$APP_DIR/.env' && rm -f /tmp/mattermost.env"

echo "Bootstrapping host"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "cd '$REMOTE_DEPLOY_DIR' && APP_DIR='$APP_DIR' REPO_DIR='$REMOTE_DEPLOY_DIR' ./scripts/bootstrap-host.sh"

echo "Validating Caddyfile"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "docker run --rm --env-file '$APP_DIR/.env' -v '$APP_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile:ro' caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile"

if [ "$APPLY_HOST_HARDENING" = "true" ]; then
  echo "Hardening host firewall and SSH"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' ADMIN_ALLOWED_CIDR='$TEST_ALLOWED_CIDR' ENABLE_CALLS_PORT=true APPLY_SSHD_HARDENING='$APPLY_SSHD_HARDENING' '$APP_DIR/ops/harden-host.sh'"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_USER@$public_ip" true
fi

echo "Building local Mattermost image"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/build-mattermost-image.sh'"

if [ "$MODE" = "restore" ]; then
  echo "Downloading and restoring backup $RESTORE_TS"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/download-backup.sh' '$RESTORE_TS'"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' SKIP_PRE_RESTORE_BACKUP=true CONFIRM_PRODUCTION_RESTORE='$RESTORE_TS' '$APP_DIR/ops/restore-production-from-backup.sh' '$RESTORE_TS'"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/restore-test-from-backup.sh' '$RESTORE_TS'"
else
  echo "Starting fresh stack"
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "cd '$APP_DIR' && docker compose --env-file .env -p mattermost -f compose.yml up -d"
fi

echo "Installing Calls plugin on production (idempotent)"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/install-calls-plugin.sh'"

echo "Configuring mobile push notifications (HPNS + user defaults)"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/configure-push-notifications.sh'"

echo "Verifying production deployment"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/health-check.sh'"

echo "Validating test instance once, then stopping to save resources"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/manage-test-instance.sh' start"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/health-check.sh'"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/manage-test-instance.sh' stop"

echo "Running host security audit"
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$REMOTE_USER@$public_ip" "APP_DIR='$APP_DIR' '$APP_DIR/ops/security-audit.sh' --host-only"

echo "Deployment complete:"
echo "  Production: https://$prod_hostname/"
echo "  Test: https://$test_hostname/ (start with: ops/manage-test-instance.sh start)"
echo "  See docs/07-upgrades.md for upgrade-test workflow"
