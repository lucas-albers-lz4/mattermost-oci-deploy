#!/usr/bin/env bash
# Provision Mattermost users, teams, and channels for invite-only communities.
# Passwords and TEXT_TO_PARENT lines go to stdout only — never commit exports.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

EMAIL_DOMAIN=${EMAIL_DOMAIN:-community.local}
NO_PARENT_TEXT=false
CREDENTIALS_OUT=""
DRY_RUN=false
SITE_URL_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: manage-community-users.sh <command> [options]

Commands:
  user create       Create a user (password generated unless --password)
  user reset-password  Reset password for an existing user
  user list         List users
  team create       Create a team
  team add-user     Add a user to a team
  channel create    Create a channel on a team
  channel add-user  Add a user to a channel (team:channel)
  batch import      Import users from CSV

Global options (where supported):
  --email-domain DOMAIN   Default email domain (default: community.local)
  --site-url URL          Override https://PROD_HOSTNAME from .env
  --no-parent-text        Skip TEXT_TO_PARENT lines
  --dry-run               Print actions only (batch import)
  --credentials-out FILE  Write username,password,parent_text (chmod 600)

Examples:
  manage-community-users.sh user create --username alice.parent --firstname Alice \
    --lastname Parent --team parents --channel parents:announcements

  manage-community-users.sh user reset-password alice.parent --generate

  manage-community-users.sh batch import --file community-users.csv

See docs/06-operations.md for CSV format and security notes.
EOF
}

mmctl_local() {
  compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local "$@"
}

ensure_stack_running() {
  cd "$APP_DIR"
  load_env
  id=$(compose ps -q mattermost-prod 2>/dev/null || true)
  [ -n "$id" ] || die "mattermost-prod is not running"
  state=$(docker inspect -f '{{.State.Status}}' "$id")
  [ "$state" = "running" ] || die "mattermost-prod is not running (state=$state)"
}

site_url() {
  if [ -n "$SITE_URL_OVERRIDE" ]; then
    echo "$SITE_URL_OVERRIDE"
    return
  fi
  [ -n "${PROD_HOSTNAME:-}" ] || die "PROD_HOSTNAME not set in $ENV_FILE (use --site-url)"
  echo "https://${PROD_HOSTNAME}"
}

gen_password() {
  local upper lower digit symbol charset pw idx
  upper='ABCDEFGHJKLMNPQRSTUVWXYZ'
  lower='abcdefghjkmnpqrstuvwxyz'
  digit='23456789'
  symbol='!@#$%&*'
  charset="${upper}${lower}${digit}${symbol}"
  pw="${upper:$((RANDOM % ${#upper})):1}"
  pw+="${lower:$((RANDOM % ${#lower})):1}"
  pw+="${digit:$((RANDOM % ${#digit})):1}"
  pw+="${symbol:$((RANDOM % ${#symbol})):1}"
  for _ in $(seq 1 12); do
    idx=$((RANDOM % ${#charset}))
    pw+="${charset:idx:1}"
  done
  echo "$pw" | fold -w1 | shuf | tr -d '\n'
}

validate_username() {
  local name=$1
  if [[ ! "$name" =~ ^[a-z0-9._-]+$ ]]; then
    die "invalid username (use lowercase letters, digits, . _ -): $name"
  fi
}

validate_team_channel() {
  local spec=$1
  if [[ ! "$spec" =~ ^[a-z0-9._-]+:[a-z0-9._-]+$ ]]; then
    die "invalid channel spec (want team:channel): $spec"
  fi
}

parent_text_line() {
  local username=$1
  local password=$2
  local url
  url=$(site_url)
  printf 'TEXT_TO_PARENT: Your community chat login — %s — username: %s — password: %s — save this message; contact the admin if you need a reset.' \
    "$url" "$username" "$password"
}

emit_user_result() {
  local action=$1
  local username=$2
  local password=$3
  local team=${4:-}
  local channels=${5:-}
  local parent_line

  if [ -n "$team" ] || [ -n "$channels" ]; then
    echo "${action} user=${username} team=${team} channels=${channels} password=${password}"
  else
    echo "${action} user=${username} password=${password}"
  fi

  if [ "$NO_PARENT_TEXT" = false ]; then
    parent_line=$(parent_text_line "$username" "$password")
    echo "$parent_line"
  fi

  if [ -n "$CREDENTIALS_OUT" ]; then
    if [ ! -s "$CREDENTIALS_OUT" ]; then
      printf 'username,password,parent_text\n' >>"$CREDENTIALS_OUT"
      chmod 600 "$CREDENTIALS_OUT"
    fi
    if [ "$NO_PARENT_TEXT" = false ]; then
      parent_line=$(parent_text_line "$username" "$password")
    else
      parent_line=""
    fi
    escaped=${parent_line//\"/\"\"}
    printf '%s,%s,"%s"\n' "$username" "$password" "$escaped" >>"$CREDENTIALS_OUT"
  fi
}

user_exists() {
  local username=$1
  mmctl_local user search "$username" 2>/dev/null | grep -q "^username: ${username}$"
}

add_user_to_team() {
  local team=$1
  local username=$2
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: team users add ${team} ${username}"
    return 0
  fi
  mmctl_local team users add "$team" "$username"
}

add_user_to_channel() {
  local spec=$1
  local username=$2
  validate_team_channel "$spec"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: channel users add ${spec} ${username}"
    return 0
  fi
  mmctl_local channel users add "$spec" "$username"
}

create_user_internal() {
  local username=$1
  local firstname=$2
  local lastname=$3
  local email=$4
  local password=$5
  local system_admin=$6

  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: user create ${username} (${firstname} ${lastname})"
    return 0
  fi

  local -a args=(
    user create
    --email "$email"
    --username "$username"
    --password "$password"
    --firstname "$firstname"
    --lastname "$lastname"
    --disable-welcome-email
    --email-verified
  )
  if [ "$system_admin" = true ]; then
    args+=(--system-admin)
  fi
  mmctl_local "${args[@]}"
}

apply_mobile_push_defaults() {
  local username=$1
  if [ "$DRY_RUN" = true ]; then
    return 0
  fi
  "$SCRIPT_DIR/configure-push-notifications.sh" --user "$username"
}

cmd_user_create() {
  local username="" firstname="" lastname="" email="" password="" team=""
  local system_admin=false
  local -a channels=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --username) username=$2; shift 2 ;;
      --firstname) firstname=$2; shift 2 ;;
      --lastname) lastname=$2; shift 2 ;;
      --email) email=$2; shift 2 ;;
      --password) password=$2; shift 2 ;;
      --team) team=$2; shift 2 ;;
      --channel) channels+=("$2"); shift 2 ;;
      --system-admin) system_admin=true; shift ;;
      --email-domain) EMAIL_DOMAIN=$2; shift 2 ;;
      --site-url) SITE_URL_OVERRIDE=$2; shift 2 ;;
      --no-parent-text) NO_PARENT_TEXT=true; shift ;;
      --credentials-out) CREDENTIALS_OUT=$2; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help)
        echo "Usage: $0 user create --username U --firstname F --lastname L [options]"
        exit 0
        ;;
      *) die "unknown option for user create: $1" ;;
    esac
  done

  [ -n "$username" ] || die "user create requires --username"
  [ -n "$firstname" ] || die "user create requires --firstname"
  [ -n "$lastname" ] || die "user create requires --lastname"
  validate_username "$username"

  ensure_stack_running

  if user_exists "$username"; then
    die "user already exists: $username (use team add-user / channel add-user, or batch import)"
  fi

  email=${email:-${username}@${EMAIL_DOMAIN}}
  password=${password:-$(gen_password)}

  create_user_internal "$username" "$firstname" "$lastname" "$email" "$password" "$system_admin"
  apply_mobile_push_defaults "$username"

  if [ -n "$team" ]; then
    add_user_to_team "$team" "$username"
  fi

  local ch channel_list=""
  for ch in "${channels[@]}"; do
    validate_team_channel "$ch"
    add_user_to_channel "$ch" "$username"
    if [ -z "$channel_list" ]; then
      channel_list=$ch
    else
      channel_list="${channel_list};${ch}"
    fi
  done

  if [ "$DRY_RUN" = false ]; then
    local channel_field=${channel_list:-}
    emit_user_result "created" "$username" "$password" "$team" "$channel_field"
  fi
}

cmd_user_reset_password() {
  local username="" password=""

  if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    username=$1
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --password) password=$2; shift 2 ;;
      --generate) shift ;;
      --site-url) SITE_URL_OVERRIDE=$2; shift 2 ;;
      --no-parent-text) NO_PARENT_TEXT=true; shift ;;
      --credentials-out) CREDENTIALS_OUT=$2; shift 2 ;;
      -h|--help)
        echo "Usage: $0 user reset-password USERNAME [--password P | --generate]"
        exit 0
        ;;
      *) die "unknown option for user reset-password: $1" ;;
    esac
  done

  [ -n "$username" ] || die "user reset-password requires USERNAME"
  validate_username "$username"

  ensure_stack_running
  user_exists "$username" || die "user not found: $username"

  if [ -z "$password" ]; then
    password=$(gen_password)
  fi

  mmctl_local user change-password "$username" --password "$password"
  emit_user_result "reset" "$username" "$password"
}

cmd_user_list() {
  ensure_stack_running
  mmctl_local user list "$@"
}

cmd_team_create() {
  local name="" display_name="" private=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name=$2; shift 2 ;;
      --display-name) display_name=$2; shift 2 ;;
      --private) private=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help)
        echo "Usage: $0 team create --name NAME --display-name \"Display Name\" [--private]"
        exit 0
        ;;
      *) die "unknown option for team create: $1" ;;
    esac
  done

  [ -n "$name" ] || die "team create requires --name"
  [ -n "$display_name" ] || die "team create requires --display-name"

  ensure_stack_running

  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: team create --name ${name} --display-name ${display_name} private=${private}"
    return 0
  fi

  local -a args=(team create --name "$name" --display-name "$display_name")
  if [ "$private" = true ]; then
    args+=(--private)
  fi
  mmctl_local "${args[@]}"
  echo "created team=${name}"
}

cmd_team_add_user() {
  local team="" username=""

  if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    team=$1
    shift
  fi
  if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    username=$1
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      *) die "unknown option for team add-user: $1" ;;
    esac
  done

  [ -n "$team" ] || die "team add-user requires TEAM"
  [ -n "$username" ] || die "team add-user requires USERNAME"
  validate_username "$username"

  ensure_stack_running
  user_exists "$username" || die "user not found: $username"

  add_user_to_team "$team" "$username"
  echo "added user=${username} team=${team}"
}

cmd_channel_create() {
  local team="" name="" display_name="" private=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --team) team=$2; shift 2 ;;
      --name) name=$2; shift 2 ;;
      --display-name) display_name=$2; shift 2 ;;
      --private) private=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help)
        echo "Usage: $0 channel create --team TEAM --name NAME --display-name \"Display Name\" [--private]"
        exit 0
        ;;
      *) die "unknown option for channel create: $1" ;;
    esac
  done

  [ -n "$team" ] || die "channel create requires --team"
  [ -n "$name" ] || die "channel create requires --name"
  [ -n "$display_name" ] || die "channel create requires --display-name"

  ensure_stack_running

  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: channel create --team ${team} --name ${name} --display-name ${display_name} private=${private}"
    return 0
  fi

  local -a args=(channel create --team "$team" --name "$name" --display-name "$display_name")
  if [ "$private" = true ]; then
    args+=(--private)
  fi
  mmctl_local "${args[@]}"
  echo "created channel=${team}:${name}"
}

cmd_channel_add_user() {
  local spec="" username=""

  if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    spec=$1
    shift
  fi
  if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    username=$1
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      *) die "unknown option for channel add-user: $1" ;;
    esac
  done

  [ -n "$spec" ] || die "channel add-user requires TEAM:CHANNEL"
  [ -n "$username" ] || die "channel add-user requires USERNAME"
  validate_team_channel "$spec"
  validate_username "$username"

  ensure_stack_running
  user_exists "$username" || die "user not found: $username"

  add_user_to_channel "$spec" "$username"
  echo "added user=${username} channel=${spec}"
}

process_batch_row() {
  local username=$1 firstname=$2 lastname=$3 team=$4 channels_col=$5 role=$6
  local password="" email="" system_admin=false
  local -a channel_specs=()
  local ch channel_list="" created=false

  if [[ ! "$username" =~ ^[a-z0-9._-]+$ ]]; then
    echo "invalid username: ${username}" >&2
    return 1
  fi
  if [ -z "$firstname" ] || [ -z "$lastname" ]; then
    echo "row for ${username}: firstname and lastname required" >&2
    return 1
  fi

  case "${role:-member}" in
    member|"") system_admin=false ;;
    admin) system_admin=true ;;
    *)
      echo "row for ${username}: invalid role '${role}' (use member or admin)" >&2
      return 1
      ;;
  esac

  if [ -n "$channels_col" ]; then
    IFS=';' read -r -a channel_specs <<<"$channels_col"
    for ch in "${channel_specs[@]}"; do
      [ -n "$ch" ] || continue
      if [[ ! "$ch" =~ ^[a-z0-9._-]+:[a-z0-9._-]+$ ]]; then
        echo "row for ${username}: invalid channel spec '${ch}'" >&2
        return 1
      fi
    done
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: row username=${username} team=${team} channels=${channels_col} role=${role:-member}"
    return 0
  fi

  email="${username}@${EMAIL_DOMAIN}"
  password=$(gen_password)

  if user_exists "$username"; then
    echo "SKIP: user exists: ${username}"
  else
    create_user_internal "$username" "$firstname" "$lastname" "$email" "$password" "$system_admin"
    apply_mobile_push_defaults "$username"
    echo "CREATE: user=${username}"
    created=true
  fi

  if [ -n "$team" ]; then
    add_user_to_team "$team" "$username"
  fi

  for ch in "${channel_specs[@]}"; do
    [ -n "$ch" ] || continue
    add_user_to_channel "$ch" "$username"
    if [ -z "$channel_list" ]; then
      channel_list=$ch
    else
      channel_list="${channel_list};${ch}"
    fi
  done

  if [ "$created" = true ]; then
    emit_user_result "created" "$username" "$password" "$team" "$channel_list"
  fi
  return 0
}

cmd_batch_import() {
  local file=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --file) file=$2; shift 2 ;;
      --email-domain) EMAIL_DOMAIN=$2; shift 2 ;;
      --site-url) SITE_URL_OVERRIDE=$2; shift 2 ;;
      --no-parent-text) NO_PARENT_TEXT=true; shift ;;
      --credentials-out) CREDENTIALS_OUT=$2; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help)
        echo "Usage: $0 batch import --file users.csv [--dry-run] [--credentials-out FILE]"
        exit 0
        ;;
      *) die "unknown option for batch import: $1" ;;
    esac
  done

  [ -n "$file" ] || die "batch import requires --file"
  [ -f "$file" ] || die "CSV file not found: $file"

  ensure_stack_running

  if [ -n "$CREDENTIALS_OUT" ] && [ "$DRY_RUN" = false ]; then
    printf 'username,password,parent_text\n' >"$CREDENTIALS_OUT"
    chmod 600 "$CREDENTIALS_OUT"
  fi

  local line=0 created=0 skipped=0 failed=0
  local username firstname lastname team channels role row_out

  while IFS=, read -r username firstname lastname team channels role || [ -n "${username:-}" ]; do
    line=$((line + 1))
    username=$(echo "$username" | tr -d '\r')
    firstname=$(echo "$firstname" | tr -d '\r')
    lastname=$(echo "$lastname" | tr -d '\r')
    team=$(echo "${team:-}" | tr -d '\r')
    channels=$(echo "${channels:-}" | tr -d '\r')
    role=$(echo "${role:-member}" | tr -d '\r')

    if [ "$line" -eq 1 ] && [ "$username" = "username" ]; then
      continue
    fi
    [ -n "$username" ] || continue

    if row_out=$(process_batch_row "$username" "$firstname" "$lastname" "$team" "$channels" "$role"); then
      echo "$row_out"
      if echo "$row_out" | grep -q '^CREATE:'; then
        created=$((created + 1))
      elif echo "$row_out" | grep -q '^SKIP:'; then
        skipped=$((skipped + 1))
      fi
    else
      echo "FAIL: row ${line} username=${username}" >&2
      failed=$((failed + 1))
    fi
  done <"$file"

  echo "batch summary: created=${created} skipped=${skipped} failed=${failed}"
  [ "$failed" -eq 0 ] || exit 1
}

main() {
  local cmd=${1:-}
  [ -n "$cmd" ] || { usage; exit 0; }

  case "$cmd" in
    user)
      shift
      case "${1:-}" in
        create) shift; cmd_user_create "$@" ;;
        reset-password) shift; cmd_user_reset_password "$@" ;;
        list) shift; cmd_user_list "$@" ;;
        *) die "unknown user subcommand: ${1:-}" ;;
      esac
      ;;
    team)
      shift
      case "${1:-}" in
        create) shift; cmd_team_create "$@" ;;
        add-user) shift; cmd_team_add_user "$@" ;;
        *) die "unknown team subcommand: ${1:-}" ;;
      esac
      ;;
    channel)
      shift
      case "${1:-}" in
        create) shift; cmd_channel_create "$@" ;;
        add-user) shift; cmd_channel_add_user "$@" ;;
        *) die "unknown channel subcommand: ${1:-}" ;;
      esac
      ;;
    batch)
      shift
      case "${1:-}" in
        import) shift; cmd_batch_import "$@" ;;
        *) die "unknown batch subcommand: ${1:-}" ;;
      esac
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"
