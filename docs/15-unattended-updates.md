# 15 - Unattended Updates

This deployment minimizes routine patching work while keeping high-risk application upgrades manual and test-gated.

## Policy summary

| Component | Automation | Notes |
| --- | --- | --- |
| Ubuntu security packages | Automatic | `unattended-upgrades` daily |
| Kernel (Ksplice) | Automatic when supported | OCI live patches without reboot |
| Kernel reboot | **Sunday 09:00 UTC** if required | Only when `/var/run/reboot-required` exists |
| Docker Engine (`docker-ce`, `containerd`) | Automatic via apt | Docker apt Origin (`Docker:noble`) allowed in unattended-upgrades |
| **Caddy** container | **Automatic** | Sunday 10:00 UTC pull + recreate |
| **Postgres** container | **Manual** | Weekly notify-only check |
| **Mattermost** app image | **Manual** | Weekly notify-only check; follow [`07-upgrades.md`](07-upgrades.md) |
| Custom `local/mattermost-arm64` build | **Manual** | Never auto-rebuilt |

Bleve search and Postgres major/minor upgrades stay manual to avoid surprise schema or index changes.

## Weekly schedule (UTC)

All timer times are **UTC**, not local time. Aimed at **~3–4 AM US Mountain Daylight (MDT, UTC-6)**: Sunday 09:00 UTC = Sunday 3:00 AM MDT. In Mountain Standard (UTC-7) that is 2:00 AM.

| When | Action | MDT (UTC-6) |
| --- | --- | --- |
| Daily | `unattended-upgrades`, Ksplice autoinstall | — |
| Daily 08:15 (+ jitter) | Backup timer | ~2:15 AM |
| Every 15 min | Health check | — |
| **Sun 09:00 UTC** | Reboot if kernel update requires it | Sun 3:00 AM |
| **Sun 10:00 UTC** | Auto-update **Caddy** only | Sun 4:00 AM |
| **Sun 11:00 UTC** | Post-maintenance summary webhook (optional; `ALERT_WEBHOOK_MAINTENANCE=true`) | Sun 5:00 AM |
| **Mon 09:00 UTC** | Update report (stdout + optional webhook) | Mon 3:00 AM |

## Ops scripts

On the VM under `/opt/mattermost/ops/`:

```sh
/opt/mattermost/ops/scheduled-reboot.sh   # normally run by timer only
/opt/mattermost/ops/upgrade-caddy.sh      # pull, validate, recreate caddy
/opt/mattermost/ops/check-updates.sh      # notify-only summary
/opt/mattermost/ops/post-maintenance-report.sh  # Sunday summary after reboot + Caddy
```

## Systemd timers

```sh
systemctl list-timers 'mattermost-*'
```

| Timer | Purpose |
| --- | --- |
| `mattermost-reboot.timer` | Scheduled reboot window |
| `mattermost-caddy-update.timer` | Caddy image refresh |
| `mattermost-update-check.timer` | Weekly pending-update report |
| `mattermost-post-maintenance.timer` | Sunday post-reboot/Caddy summary |
| `mattermost-backup.timer` | Daily backups |
| `mattermost-health.timer` | Health checks |

Install or refresh ops scripts, apt allowlists, and timers from your laptop (preferred day-2 path):

```sh
scripts/sync-ops-to-host.sh matterhost
```

See [`06-operations.md`](06-operations.md#sync-ops-scripts-from-git-day-2). On the VM itself (after the repo is already under `/opt/mattermost/deploy`):

```sh
APP_DIR=/opt/mattermost REPO_DIR=/opt/mattermost/deploy \
  INSTALL_PACKAGES=false COPY_ASSETS=true COPY_STACK_TEMPLATES=false \
  /opt/mattermost/deploy/scripts/bootstrap-host.sh
```

## Alerting

Set `ALERT_WEBHOOK_URL` in `/opt/mattermost/.env` to receive JSON webhooks when:

- Caddy auto-update fails
- Weekly update check finds pending reboot, Docker, Postgres, or Mattermost updates

Set `ALERT_WEBHOOK_MAINTENANCE=true` (with `ALERT_WEBHOOK_URL`) for optional **success** webhooks after Sunday maintenance:

- Scheduled reboot skipped or initiating
- Caddy auto-update unchanged or updated
- Post-maintenance summary (Sunday 11:00 UTC)

Health and backup failures use the same webhook (see [`06-operations.md`](06-operations.md)).

### Mattermost incoming webhook setup

1. In Mattermost (prod): **Integrations → Incoming Webhooks → Add Incoming Webhook**.
2. Choose an ops channel (e.g. `#alerts`) and copy the URL — it must contain `/hooks/`, not a channel browse link.
3. On the VM, set in `/opt/mattermost/.env`:

   ```sh
   ALERT_WEBHOOK_URL=https://chat.example.com/hooks/xxxxxxxxxxxxxxxxxx
   ```

4. Test:

   ```sh
   curl -sS -X POST -H 'Content-Type: application/json' \
     -d '{"text":"Test alert from mattermost-oci-deploy"}' \
     "$ALERT_WEBHOOK_URL"
   ```

See [`templates/env.example`](../templates/env.example) for the placeholder format.

## Pause automation

```sh
sudo systemctl disable --now mattermost-caddy-update.timer
sudo systemctl disable --now mattermost-reboot.timer
sudo systemctl disable --now mattermost-update-check.timer
sudo systemctl disable --now mattermost-post-maintenance.timer
```

Re-enable with `sudo systemctl enable --now <timer>`.

## Manual Mattermost / Postgres upgrades

When `check-updates.sh` or the Monday webhook reports a newer version:

1. Back up ([`05-backups-and-restore.md`](05-backups-and-restore.md))
2. Follow [`07-upgrades.md`](07-upgrades.md) for Mattermost
3. For Postgres: pull image, test on `upgrade-test` profile if needed, recreate during a maintenance window

## Apt configuration

- [`templates/apt/50unattended-upgrades-mattermost`](../templates/apt/50unattended-upgrades-mattermost) — allows Ubuntu security + Docker apt Origin (`o=Docker`, not the Label “Docker CE”)
- `52mattermost-security-upgrades` — disables apt auto-reboot (timer handles reboots) and includes phased security updates

## Verification

```sh
/opt/mattermost/ops/security-audit.sh --host-only
/opt/mattermost/ops/check-updates.sh
/opt/mattermost/ops/upgrade-caddy.sh
grep -F 'Docker:${distro_codename}' /etc/apt/apt.conf.d/50unattended-upgrades-mattermost
apt-cache policy containerd.io | head -20
```

Confirm Docker Origin with `apt-cache policy` (`o=Docker,a=noble,…`). Wrong `Allowed-Origins` (`Docker CE:…`) leaves `containerd.io` / compose plugin pending forever.
## Non-goals

- Watchtower or auto-recreate for Postgres / Mattermost
- Email notifications
- OCI OS Management Hub
