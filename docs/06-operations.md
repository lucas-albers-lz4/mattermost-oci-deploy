# 06 - Operations

## SSH

```sh
ssh ubuntu@<vm-public-ip>
```

## Status

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml ps
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/security-audit.sh --host-only
```

## Logs

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 mattermost-prod
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 mattermost-test
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 postgres
docker compose --env-file .env -p mattermost -f compose.yml logs --tail=200 caddy
```

Follow logs:

```sh
docker compose --env-file .env -p mattermost -f compose.yml logs -f mattermost-prod
docker compose --env-file .env -p mattermost -f compose.yml logs -f mattermost-test
```

## Restart

```sh
cd /opt/mattermost
docker compose --env-file .env -p mattermost -f compose.yml restart mattermost-prod caddy
```

Restart test only when it is running for upgrade validation:

```sh
/opt/mattermost/ops/manage-test-instance.sh status
docker compose --env-file .env -p mattermost -f compose.yml --profile upgrade-test restart mattermost-test
```

## Health Check

Systemd timer:

```text
mattermost-health.timer
```

`scripts/bootstrap-host.sh` installs and enables this timer from `templates/systemd/`. It runs the health check 5 minutes after timer activation, then every 15 minutes.

Check it:

```sh
systemctl status mattermost-health.timer --no-pager
journalctl -u mattermost-health.service --no-pager -n 100
```

Manual run:

```sh
/opt/mattermost/ops/health-check.sh
```

The health check validates:

- Root disk usage
- Available memory
- Container running state for production path (`postgres`, `mattermost-prod`, `caddy`)
- Production public HTTPS
- Production internal app HTTP
- Test internal app HTTP **only when** `mattermost-test` is running (skipped when idle)

Test public HTTPS is not checked from the VM because Caddy intentionally restricts test by client IP.

See [`docs/14-performance.md`](14-performance.md) for why the test instance is stopped during normal operation and how to start it for upgrades.

If `ALERT_WEBHOOK_URL` is set in `/opt/mattermost/.env`, health check failures send a JSON webhook:

```json
{"text":"Mattermost health check failed on <host> with exit <status>"}
```

Check failed systemd units:

```sh
systemctl --failed --no-pager
```

## Host Updates

Unattended security updates are enabled:

```sh
systemctl is-enabled unattended-upgrades.service
grep -E 'APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades
```

On OCI Ubuntu, Ksplice is installed during bootstrap when available:

```sh
command -v uptrack-upgrade
grep -E '^autoinstall[[:space:]]*=[[:space:]]*yes' /etc/uptrack/uptrack.conf
```

Ksplice covers supported kernel live patches. Continue to review userspace package, Docker/containerd, image, and Mattermost updates separately.

See [`docs/15-unattended-updates.md`](docs/15-unattended-updates.md) for the full unattended update schedule (Sunday reboot window, Caddy auto-update, Monday update report).

Check pending package updates:

```sh
sudo apt-get update
apt list --upgradable
```

## Firewall

OCI NSG should expose:

- `22/tcp` from admin public IP only
- `80/tcp` from everywhere
- `443/tcp` from everywhere
- `8443/udp` from everywhere if Mattermost Calls is enabled
- Egress to everywhere

No Docker host port should expose Mattermost directly. Only Caddy publishes public ports.

After confirming key-based SSH in a second terminal, apply host firewall rules:

```sh
sudo ADMIN_ALLOWED_CIDR=<your-admin-ip>/32 /opt/mattermost/ops/harden-host.sh
```

For optional SSH hardening, see `docs/09-security-hardening.md`.

## No-Email Operating Mode

SMTP is intentionally disabled.

Operational impact:

- Password reset emails do not work.
- Email invitations do not work.
- Admin intervention is required for account recovery.
- Keep at least one admin account accessible.

If email is enabled later, configure and test SMTP separately for production and test.
