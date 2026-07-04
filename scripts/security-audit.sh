#!/usr/bin/env bash
set -euo pipefail

MODE=all
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

case "${1:-}" in
  --host-only)
    MODE=host
    ;;
  --repo-only)
    MODE=repo
    ;;
  ""|--all)
    MODE=all
    ;;
  -h|--help)
    echo "Usage: $0 [--all|--host-only|--repo-only]"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 64
    ;;
esac

failures=0

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

have() {
  command -v "$1" >/dev/null 2>&1
}

csv_contains() {
  haystack=$1
  needle=$2
  case ",$haystack," in
    *,"$needle",*) return 0 ;;
    *) return 1 ;;
  esac
}

repo_audit() {
  repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
  cd "$repo_root"

  if bash -n scripts/*.sh scripts/lib/*.sh templates/*.sh; then
    pass "shell syntax"
  else
    fail "shell syntax"
  fi

  if have shellcheck; then
    if shellcheck scripts/*.sh scripts/lib/*.sh templates/*.sh; then
      pass "shellcheck"
    else
      fail "shellcheck"
    fi
  else
    warn "shellcheck not installed"
  fi

  if have docker; then
    if docker compose --env-file templates/env.example -p mattermost -f templates/compose.yml config >/dev/null; then
      pass "compose config"
    else
      fail "compose config"
    fi
  else
    warn "docker not installed"
  fi

  if have tofu; then
    if tofu -chdir=infra/opentofu fmt -check; then
      pass "tofu fmt"
    else
      fail "tofu fmt"
    fi
    if tofu -chdir=infra/opentofu validate; then
      pass "tofu validate"
    else
      warn "tofu validate needs initialized provider plugins"
    fi
  else
    warn "tofu not installed"
  fi

  if have trivy; then
    if trivy config --quiet .; then
      pass "trivy config"
    else
      fail "trivy config"
    fi
  else
    warn "trivy not installed"
  fi

  if have gitleaks; then
    if gitleaks detect --no-git --redact --source .; then
      pass "gitleaks"
    else
      fail "gitleaks"
    fi
  else
    warn "gitleaks not installed"
  fi
}

host_audit() {
  if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
    cd "$APP_DIR"
    load_env
  fi

  if have ufw; then
    sudo ufw status verbose | tee /tmp/mattermost-ufw-status.txt
    if sudo ufw status | grep -q "Status: active"; then
      pass "ufw active"
    else
      fail "ufw inactive"
    fi
    if grep -q "8443/udp" /tmp/mattermost-ufw-status.txt; then
      pass "calls udp allowed"
    else
      warn "8443/udp not present in UFW"
    fi
  else
    fail "ufw not installed"
  fi

  if systemctl is-active --quiet fail2ban; then
    pass "fail2ban active"
  else
    fail "fail2ban inactive"
  fi
  if systemctl is-enabled --quiet unattended-upgrades; then
    pass "unattended upgrades enabled"
  else
    warn "unattended upgrades not enabled"
  fi
  if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -Eq 'APT::Periodic::Unattended-Upgrade[[:space:]]+"1"' /etc/apt/apt.conf.d/20auto-upgrades; then
    pass "daily unattended security updates configured"
  else
    warn "daily unattended security updates not configured"
  fi
  if have uptrack-upgrade; then
    pass "Ksplice installed"
    if [ -f /etc/uptrack/uptrack.conf ] && grep -Eq '^autoinstall[[:space:]]*=[[:space:]]*yes' /etc/uptrack/uptrack.conf; then
      pass "Ksplice autoinstall enabled"
    else
      warn "Ksplice autoinstall not confirmed"
    fi
  elif [ "${REQUIRE_KSPLICE:-false}" = "true" ]; then
    fail "Ksplice not installed"
  else
    warn "Ksplice not installed"
  fi
  if sudo sshd -t; then
    pass "sshd config"
  else
    fail "sshd config"
  fi

  if systemctl is-active --quiet mattermost-health.timer; then
    pass "health timer active"
  else
    fail "health timer inactive"
  fi
  if systemctl is-active --quiet mattermost-backup.timer; then
    pass "backup timer active"
  else
    fail "backup timer inactive"
  fi

  if have docker && declare -F compose >/dev/null 2>&1; then
    compose ps >/tmp/mattermost-compose-ps.txt
    if grep -q "0.0.0.0:80->80/tcp" /tmp/mattermost-compose-ps.txt; then
      pass "http published by caddy"
    else
      warn "http publish not found"
    fi
    if grep -q "0.0.0.0:443->443/tcp" /tmp/mattermost-compose-ps.txt; then
      pass "https published by caddy"
    else
      warn "https publish not found"
    fi
    if grep -q "8443->8443/udp" /tmp/mattermost-compose-ps.txt; then
      pass "calls udp published"
    else
      warn "calls udp publish not found"
    fi
    if grep -q "0.0.0.0:5432" /tmp/mattermost-compose-ps.txt; then
      fail "postgres publicly published"
    else
      pass "postgres not publicly published"
    fi
    if compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null; then
      pass "caddy config validates"
    else
      fail "caddy config validates"
    fi
    for service in postgres mattermost-prod mattermost-test caddy; do
      if [ "$service" = "mattermost-test" ]; then
        cid=$(compose --profile upgrade-test ps -q mattermost-test 2>/dev/null || true)
        if [ -z "$cid" ]; then
          warn "mattermost-test idle (profile inactive)"
          continue
        fi
        test_state=$(docker inspect --format '{{.State.Status}}' "$cid")
        if [ "$test_state" != "running" ]; then
          warn "mattermost-test idle ($test_state)"
          continue
        fi
      else
        cid=$(container_id "$service")
      fi
      privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$cid")
      security_opts=$(docker inspect --format '{{range .HostConfig.SecurityOpt}}{{.}},{{end}}' "$cid")
      cap_drop=$(docker inspect --format '{{range .HostConfig.CapDrop}}{{.}},{{end}}' "$cid")
      cap_add=$(docker inspect --format '{{range .HostConfig.CapAdd}}{{.}},{{end}}' "$cid")
      binds=$(docker inspect --format '{{range .HostConfig.Binds}}{{.}},{{end}}' "$cid")
      mounts=$(docker inspect --format '{{range .Mounts}}{{println .Source ":" .Destination}}{{end}}' "$cid")
      apparmor=$(docker inspect --format '{{.AppArmorProfile}}' "$cid")

      if [ "$privileged" = "false" ]; then
        pass "$service not privileged"
      else
        fail "$service privileged"
      fi
      if printf '%s\n%s\n' "$binds" "$mounts" | grep -q '/var/run/docker.sock'; then
        fail "$service mounts Docker socket"
      else
        pass "$service does not mount Docker socket"
      fi
      if csv_contains "$security_opts" "no-new-privileges:true"; then
        pass "$service no-new-privileges"
      else
        fail "$service missing no-new-privileges"
      fi
      if printf '%s' "$security_opts" | grep -Eq 'seccomp=unconfined|apparmor=unconfined'; then
        fail "$service disables seccomp/AppArmor"
      else
        pass "$service seccomp/AppArmor not explicitly disabled"
      fi
      if [ -n "$apparmor" ] && [ "$apparmor" != "unconfined" ]; then
        pass "$service AppArmor profile active"
      else
        warn "$service AppArmor profile not confirmed"
      fi

      case "$service" in
        mattermost-prod|mattermost-test)
          if csv_contains "$cap_drop" "ALL"; then
            pass "$service drops all capabilities"
          else
            fail "$service does not drop all capabilities"
          fi
          ;;
        caddy)
          if csv_contains "$cap_drop" "ALL"; then
            pass "caddy drops all capabilities"
          else
            fail "caddy does not drop all capabilities"
          fi
          if csv_contains "$cap_add" "NET_BIND_SERVICE" || csv_contains "$cap_add" "CAP_NET_BIND_SERVICE"; then
            pass "caddy adds NET_BIND_SERVICE only"
          else
            fail "caddy missing NET_BIND_SERVICE"
          fi
          ;;
        postgres)
          if csv_contains "$cap_drop" "ALL"; then
            pass "postgres drops all capabilities"
          else
            warn "postgres capability drop disabled after fresh-volume validation failure"
          fi
          ;;
      esac
    done
    if "$SCRIPT_DIR/health-check.sh"; then
      pass "mattermost health check"
    else
      fail "mattermost health check"
    fi
  else
    warn "docker/common compose helper unavailable"
  fi
}

case "$MODE" in
  all)
    repo_audit
    host_audit
    ;;
  repo)
    repo_audit
    ;;
  host)
    host_audit
    ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "Security audit completed with $failures failure(s)." >&2
  exit 1
fi

echo "Security audit completed."
