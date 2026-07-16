#!/usr/bin/env bash
# shellcheck disable=SC2029
# Push repo scripts/templates to an existing VM and refresh /opt/mattermost/ops.
# Same rsync path as deploy-from-zero, without tofu / .env replace / rebuild.
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/mattermost}
REMOTE_USER=${REMOTE_USER:-ubuntu}
REMOTE_DEPLOY_DIR=${REMOTE_DEPLOY_DIR:-$APP_DIR/deploy}
SSH_REMOTE_OPTS=${SSH_REMOTE_OPTS:-}
REMOTE_HOST=${REMOTE_HOST:-}
REPO_DIR=${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

DRY_RUN=false
INSTALL_TIMERS=${INSTALL_TIMERS:-true}
# Default: refresh ops scripts + apt + timers; do not overwrite live compose/Caddy.
COPY_STACK_TEMPLATES=${COPY_STACK_TEMPLATES:-false}
VERIFY_REMOTE=${VERIFY_REMOTE:-true}

usage() {
  cat <<'EOF'
Usage:
  scripts/sync-ops-to-host.sh <host>
  REMOTE_HOST=matterhost scripts/sync-ops-to-host.sh

Sync this checkout to the VM deploy dir via rsync, then run bootstrap-host.sh with
INSTALL_PACKAGES=false so /opt/mattermost/ops (and apt/timer config) match git.

Does not modify /opt/mattermost/.env, rebuild images, or recreate containers.

Options:
  --dry-run           rsync -n only; skip bootstrap
  --full              also refresh compose/Caddy/image/postgres templates (COPY_STACK_TEMPLATES=true)
  --no-timers         do not reinstall systemd units (INSTALL_TIMERS=false)
  --no-verify         skip post-sync host check of check-updates.sh
  -h, --help          show this help

Environment:
  REMOTE_HOST           SSH host or SSH config Host alias (required unless positional)
  REMOTE_USER           default: ubuntu
  REMOTE_DEPLOY_DIR     default: /opt/mattermost/deploy
  APP_DIR               default: /opt/mattermost
  SSH_REMOTE_OPTS       extra ssh/scp options (same as deploy-from-zero)
  REPO_DIR              local repo root (default: parent of scripts/)

Examples:
  # Day-2: push ops/monitoring script fixes (e.g. commit c5c6f1a)
  scripts/sync-ops-to-host.sh matterhost

  # Dry-run first
  scripts/sync-ops-to-host.sh --dry-run matterhost

  # Also overwrite compose.yml / Caddyfile from templates
  scripts/sync-ops-to-host.sh --full matterhost
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 64
  }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --full)
      COPY_STACK_TEMPLATES=true
      shift
      ;;
    --no-timers)
      INSTALL_TIMERS=false
      shift
      ;;
    --no-verify)
      VERIFY_REMOTE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      exit 64
      ;;
    *)
      if [ -n "$REMOTE_HOST" ]; then
        echo "Unexpected argument: $1 (REMOTE_HOST already set to $REMOTE_HOST)" >&2
        exit 64
      fi
      REMOTE_HOST=$1
      shift
      ;;
  esac
done

if [ -z "$REMOTE_HOST" ]; then
  usage >&2
  exit 64
fi

# Allow user@host as the positional / REMOTE_HOST value.
if [[ "$REMOTE_HOST" == *@* ]]; then
  REMOTE_USER=${REMOTE_HOST%%@*}
  REMOTE_HOST=${REMOTE_HOST#*@}
fi

if [ ! -f "$REPO_DIR/templates/compose.yml" ] || [ ! -f "$REPO_DIR/scripts/bootstrap-host.sh" ]; then
  echo "REPO_DIR does not look like mattermost-oci-deploy: $REPO_DIR" >&2
  exit 64
fi

require_command rsync
require_command ssh

remote="$REMOTE_USER@$REMOTE_HOST"
rsync_flags=(-az)
if [ "$DRY_RUN" = "true" ]; then
  rsync_flags+=(-n --itemize-changes)
fi

echo "Local HEAD: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Target: $remote:$REMOTE_DEPLOY_DIR -> $APP_DIR/ops"
echo "COPY_STACK_TEMPLATES=$COPY_STACK_TEMPLATES INSTALL_TIMERS=$INSTALL_TIMERS DRY_RUN=$DRY_RUN"

# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS -o BatchMode=yes -o ConnectTimeout=15 "$remote" "mkdir -p '$REMOTE_DEPLOY_DIR'"

echo "Syncing repo..."
# shellcheck disable=SC2086
rsync "${rsync_flags[@]}" --delete \
  -e "ssh $SSH_REMOTE_OPTS" \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude '*.tfstate*' \
  --exclude '*.tfvars' \
  --exclude 'tfplan' \
  --exclude '.mattermost-secrets.env' \
  --exclude 'generated.env' \
  --exclude '.env' \
  --exclude 'docs/images/' \
  --exclude '.cursor/' \
  "$REPO_DIR/" "$remote:$REMOTE_DEPLOY_DIR/"

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run complete; bootstrap skipped."
  exit 0
fi

echo "Refreshing host assets via bootstrap-host.sh..."
# shellcheck disable=SC2086
ssh $SSH_REMOTE_OPTS "$remote" \
  "cd '$REMOTE_DEPLOY_DIR' && \
   APP_DIR='$APP_DIR' \
   REPO_DIR='$REMOTE_DEPLOY_DIR' \
   INSTALL_PACKAGES=false \
   COPY_ASSETS=true \
   COPY_STACK_TEMPLATES='$COPY_STACK_TEMPLATES' \
   INSTALL_TIMERS='$INSTALL_TIMERS' \
   INSTALL_KSPLICE=false \
   ./scripts/bootstrap-host.sh"

if [ "$VERIFY_REMOTE" = "true" ]; then
  echo "Verifying remote ops scripts..."
  # shellcheck disable=SC2086
  ssh $SSH_REMOTE_OPTS "$remote" \
    "test -x '$APP_DIR/ops/check-updates.sh' && \
     test -f '$APP_DIR/ops/lib/common.sh' && \
     grep -Fq 'Docker:' /etc/apt/apt.conf.d/50unattended-upgrades-mattermost && \
     echo OK: ops scripts and Docker apt allowlist present"
fi

echo
echo "Sync complete. Suggested checks on the host:"
echo "  ssh $remote '$APP_DIR/ops/check-updates.sh'"
echo "  ssh $remote '$APP_DIR/ops/security-audit.sh --host-only'"
if [ "$COPY_STACK_TEMPLATES" = "true" ]; then
  echo
  echo "NOTE: --full refreshed compose/Caddy templates. Recreate services only if intentional:"
  echo "  ssh $remote \"cd '$APP_DIR' && docker compose --env-file .env -p mattermost -f compose.yml up -d\""
fi
