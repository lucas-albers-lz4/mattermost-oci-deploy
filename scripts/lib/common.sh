#!/usr/bin/env bash

APP_DIR=${APP_DIR:-/opt/mattermost}
COMPOSE_FILE=${COMPOSE_FILE:-$APP_DIR/compose.yml}
ENV_FILE=${ENV_FILE:-$APP_DIR/.env}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-mattermost}
LOG_PREFIX=${LOG_PREFIX:-[mattermost]}

die() {
  echo "$LOG_PREFIX ERROR: $*" >&2
  exit 1
}

load_env() {
  [ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

compose() {
  docker compose --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

container_id() {
  service=$1
  id=$(compose ps -q "$service")
  [ -n "$id" ] || die "container missing for service: $service"
  echo "$id"
}

volume_name() {
  echo "${COMPOSE_PROJECT_NAME}_$1"
}

_webhook_payload() {
  # Build JSON {"text": "..."} with proper escaping (apt lines can contain quotes/brackets).
  MESSAGE=$1 HOST=$2 python3 - <<'PY'
import json
import os

print(json.dumps({"text": f"{os.environ['MESSAGE']} on {os.environ['HOST']}"}))
PY
}

_post_webhook() {
  text=$1

  if [ -z "${ALERT_WEBHOOK_URL:-}" ]; then
    echo "$LOG_PREFIX webhook skipped: ALERT_WEBHOOK_URL unset" >&2
    return 0
  fi

  host=$(hostname)
  payload=$(_webhook_payload "$text" "$host") || {
    echo "$LOG_PREFIX WARN: webhook payload encode failed" >&2
    return 0
  }

  if curl -fsS --max-time 10 \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$ALERT_WEBHOOK_URL" >/dev/null; then
    echo "$LOG_PREFIX webhook sent" >&2
  else
    echo "$LOG_PREFIX WARN: webhook post failed (check ALERT_WEBHOOK_URL / Mattermost reachability)" >&2
  fi
}

notify_failure() {
  status=$1
  message=$2
  _post_webhook "${message} with exit ${status}"
}

notify_webhook() {
  message=$1
  _post_webhook "$message"
}

notify_maintenance() {
  message=$1

  if [ "${ALERT_WEBHOOK_MAINTENANCE:-false}" = "true" ]; then
    notify_webhook "$message"
  fi
}

oci_namespace() {
  oci os ns get --auth instance_principal --query data --raw-output
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

_env_get() {
  key=$1
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

_env_set() {
  key=$1
  value=$2
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

_env_restore_or_unset() {
  key=$1
  prev=$2
  if [ -n "$prev" ]; then
    _env_set "$key" "$prev"
  else
    sed -i.bak "/^${key}=/d" "$ENV_FILE" 2>/dev/null || true
    rm -f "$ENV_FILE.bak"
  fi
}

wait_for_local_mmctl() {
  timeout_s=${1:-90}
  elapsed=0
  while [ "$elapsed" -lt "$timeout_s" ]; do
    if compose exec -T -u mattermost mattermost-prod \
      /mattermost/bin/mmctl --local plugin list >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  die "mmctl --local not ready after ${timeout_s}s (local mode socket / mattermost-prod)"
}

plugin_is_enabled() {
  plugin_id=$1
  list=$(compose exec -T -u mattermost mattermost-prod \
    /mattermost/bin/mmctl --local plugin list 2>/dev/null) || return 1
  printf '%s\n' "$list" | awk -v id="$plugin_id" '
    $0 == "Listing enabled plugins" { en=1; next }
    $0 ~ /^Listing / { en=0; next }
    en && index($0, id ":") == 1 { found=1; exit }
    END { exit found ? 0 : 1 }
  '
}

# True if plugin appears under enabled or disabled in mmctl plugin list.
plugin_is_installed() {
  plugin_id=$1
  list=$(compose exec -T -u mattermost mattermost-prod \
    /mattermost/bin/mmctl --local plugin list 2>/dev/null) || return 1
  printf '%s\n' "$list" | awk -v id="$plugin_id" '
    index($0, id ":") == 1 { found=1; exit }
    END { exit found ? 0 : 1 }
  '
}

mmctl_local() {
  compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local "$@"
}

# Disable and delete a plugin if present (for FORCE upgrades).
mmctl_plugin_delete() {
  plugin_id=$1
  wait_for_local_mmctl 60
  mmctl_local plugin disable "$plugin_id" >/dev/null 2>&1 || true
  mmctl_local plugin delete "$plugin_id" >/dev/null 2>&1 || true
}

# Mattermost amazons3 filestore path prefix used by this stack's compose.yml.
FILESTORE_PLUGIN_PREFIX=${FILESTORE_PLUGIN_PREFIX:-prod/plugins}

filestore_plugin_key() {
  plugin_id=$1
  echo "${FILESTORE_PLUGIN_PREFIX%/}/${plugin_id}.tar.gz"
}

# List/copy plugin bundles via the on-VM rclone S3 proxy (Compose network).
filestore_s3() {
  load_env
  : "${MM_FILESETTINGS_AMAZONS3ACCESSKEYID:?MM_FILESETTINGS_AMAZONS3ACCESSKEYID missing in $ENV_FILE}"
  : "${MM_FILESETTINGS_AMAZONS3SECRETACCESSKEY:?MM_FILESETTINGS_AMAZONS3SECRETACCESSKEY missing in $ENV_FILE}"
  : "${MM_FILESETTINGS_AMAZONS3BUCKET:?MM_FILESETTINGS_AMAZONS3BUCKET missing in $ENV_FILE}"
  region=${MM_FILESETTINGS_AMAZONS3REGION:-us-phoenix-1}
  network=${COMPOSE_PROJECT_NAME}_default
  docker run --rm --network "$network" \
    -e AWS_ACCESS_KEY_ID="$MM_FILESETTINGS_AMAZONS3ACCESSKEYID" \
    -e AWS_SECRET_ACCESS_KEY="$MM_FILESETTINGS_AMAZONS3SECRETACCESSKEY" \
    -e AWS_DEFAULT_REGION="$region" \
    amazon/aws-cli \
    --endpoint-url http://filestore-s3:9000 \
    "$@"
}

filestore_has_plugin_bundle() {
  plugin_id=$1
  key=$(filestore_plugin_key "$plugin_id")
  load_env
  filestore_s3 s3 ls "s3://${MM_FILESETTINGS_AMAZONS3BUCKET}/${key}" >/dev/null 2>&1
}

# Upload plugins/<id>.tar.gz to Object Storage (required for amazons3 restart sync).
# Set FORCE_UPLOAD=true to overwrite an existing key (plugin upgrades).
ensure_filestore_plugin_bundle() {
  plugin_id=$1
  host_tar=$2
  [ -f "$host_tar" ] || die "plugin tarball not found for filestore upload: $host_tar"
  key=$(filestore_plugin_key "$plugin_id")
  load_env
  if [ "${FORCE_UPLOAD:-false}" != "true" ] && filestore_has_plugin_bundle "$plugin_id"; then
    echo "$LOG_PREFIX filestore already has s3://${MM_FILESETTINGS_AMAZONS3BUCKET}/${key}"
    return 0
  fi
  echo "$LOG_PREFIX uploading ${host_tar} -> s3://${MM_FILESETTINGS_AMAZONS3BUCKET}/${key}"
  network=${COMPOSE_PROJECT_NAME}_default
  region=${MM_FILESETTINGS_AMAZONS3REGION:-us-phoenix-1}
  docker run --rm --network "$network" \
    -v "${host_tar}:/plugin.tar.gz:ro" \
    -e AWS_ACCESS_KEY_ID="$MM_FILESETTINGS_AMAZONS3ACCESSKEYID" \
    -e AWS_SECRET_ACCESS_KEY="$MM_FILESETTINGS_AMAZONS3SECRETACCESSKEY" \
    -e AWS_DEFAULT_REGION="$region" \
    amazon/aws-cli \
    s3 cp /plugin.tar.gz "s3://${MM_FILESETTINGS_AMAZONS3BUCKET}/${key}" \
    --endpoint-url http://filestore-s3:9000
}

# mmctl plugin add; tolerate rclone NoSuchUpload if the plugin still appears in list
# or can be recovered via filestore sync after recreate.
mmctl_plugin_add_tolerant() {
  plugin_id=$1
  container_tar=$2
  if mmctl_local plugin add "$container_tar"; then
    return 0
  fi
  echo "$LOG_PREFIX WARN: mmctl plugin add failed (often rclone NoSuchUpload on large bundles); checking recovery paths" >&2
  sleep 2
  if plugin_is_installed "$plugin_id"; then
    echo "$LOG_PREFIX plugin present after failed add (local extract likely succeeded)"
    return 0
  fi
  # Pre-seeded filestore + recreate often recovers managed plugins.
  echo "$LOG_PREFIX attempting filestore sync recovery via recreate"
  compose up -d --force-recreate mattermost-prod >/dev/null
  wait_for_local_mmctl 120
  if plugin_is_installed "$plugin_id" || plugin_is_enabled "$plugin_id"; then
    return 0
  fi
  die "mmctl plugin add failed and ${plugin_id} is still missing after filestore sync recovery"
}

# Recreate prod and confirm plugin is still enabled after filestore sync.
verify_plugin_survives_restart() {
  plugin_id=$1
  echo "$LOG_PREFIX verifying ${plugin_id} survives mattermost-prod recreate (filestore sync)"
  compose up -d --force-recreate mattermost-prod >/dev/null
  wait_for_local_mmctl 120
  if ! plugin_is_enabled "$plugin_id"; then
    # Enable may be needed if sync installed as disabled.
    mmctl_local plugin enable "$plugin_id" >/dev/null 2>&1 || true
    sleep 2
  fi
  if ! plugin_is_enabled "$plugin_id"; then
    die "${plugin_id} missing after restart — filestore bundle likely missing (see ensure_filestore_plugin_bundle / server logs)"
  fi
  echo "$LOG_PREFIX ${plugin_id} present after restart"
}

# Temporarily enable plugin uploads and raise MaxFileSize if needed for large bundles.
# Restores previous .env values and recreates mattermost-prod on EXIT.
# Usage: with_plugin_install_env [min_max_file_size_bytes]
# Legacy alias: with_plugin_uploads_enabled
with_plugin_install_env() {
  min_max=${1:-0}
  _mm_uploads_prev=$(_env_get MM_PLUGINSETTINGS_ENABLEUPLOADS)
  _mm_maxfile_prev=$(_env_get MM_FILESETTINGS_MAXFILESIZE)
  _mm_maxfile_default=52428800
  _mm_maxfile_changed=false

  _mm_restore_plugin_install_env() {
    _env_restore_or_unset MM_PLUGINSETTINGS_ENABLEUPLOADS "${_mm_uploads_prev}"
    if [ "${_mm_maxfile_changed}" = "true" ]; then
      _env_restore_or_unset MM_FILESETTINGS_MAXFILESIZE "${_mm_maxfile_prev}"
    fi
    compose up -d mattermost-prod >/dev/null || true
  }
  trap _mm_restore_plugin_install_env EXIT

  _env_set MM_PLUGINSETTINGS_ENABLEUPLOADS true

  current_max=${_mm_maxfile_prev:-$_mm_maxfile_default}
  if [ "$min_max" -gt "$current_max" ]; then
    echo "$LOG_PREFIX raising MM_FILESETTINGS_MAXFILESIZE ${current_max} -> ${min_max} for plugin install"
    _env_set MM_FILESETTINGS_MAXFILESIZE "$min_max"
    _mm_maxfile_changed=true
  fi

  compose up -d mattermost-prod >/dev/null
  wait_for_local_mmctl 90
}

with_plugin_uploads_enabled() {
  with_plugin_install_env "${1:-0}"
}
