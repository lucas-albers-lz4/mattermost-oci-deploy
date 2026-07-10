# 09 - Security Hardening

This guide adds defense in depth for the OCI Mattermost VM. Apply it after the base deployment works and you can open a second SSH session for verification.

## Baseline Order

1. Confirm OCI NSG allows only `22/tcp` from your admin public IP and `80/443` from the internet.
2. Confirm SSH key login works from a second terminal.
3. Enable host firewall rules with `/opt/mattermost/ops/harden-host.sh`.
4. Optionally install the SSH hardening drop-in and reload SSH only after `sshd -t` passes.
5. Lock down Mattermost signup, team creation, password policy, and MFA from the System Console.
6. Verify backups, health checks, and alerting.

Do not close your working SSH session until a new SSH session succeeds after firewall and SSH changes.

## Host Firewall

`scripts/bootstrap-host.sh` installs `ufw` and `fail2ban`, then copies `scripts/harden-host.sh` to `/opt/mattermost/ops/harden-host.sh`. It does not enable UFW automatically.

Run this from the VM after replacing the CIDR with your current admin public IP:

```sh
sudo ADMIN_ALLOWED_CIDR=<your-admin-ip>/32 /opt/mattermost/ops/harden-host.sh
```

The helper configures:

- Default deny inbound.
- Default allow outbound.
- SSH only from `ADMIN_ALLOWED_CIDR`.
- HTTP `80/tcp` for redirect and ACME.
- HTTPS `443/tcp`.
- Mattermost Calls UDP `8443` when `ENABLE_CALLS_PORT=true`.
- `fail2ban` service enabled if installed.

OCI NSGs remain the primary perimeter control. Docker manages its own published-port rules, so do not publish PostgreSQL or Mattermost app ports directly.

Verify:

```sh
sudo ufw status verbose
sudo systemctl status fail2ban --no-pager
ssh ubuntu@<vm-public-ip>
```

## SSH Hardening

The optional drop-in template is copied to:

```text
/opt/mattermost/ops/99-mattermost-hardening.conf
```

It disables password login, keyboard-interactive login, empty passwords, and root SSH login while keeping public key auth enabled.

Apply it only after you have confirmed key-based SSH works:

```sh
sudo install -m 0644 /opt/mattermost/ops/99-mattermost-hardening.conf /etc/ssh/sshd_config.d/99-mattermost-hardening.conf
sudo sshd -t
sudo systemctl reload ssh
```

Then open a second SSH session before closing the current one.

You can also let the helper apply the SSH drop-in:

```sh
sudo ADMIN_ALLOWED_CIDR=<your-admin-ip>/32 APPLY_SSHD_HARDENING=true /opt/mattermost/ops/harden-host.sh
```

## Mattermost Account Controls

Apply these after the first admin account exists.

Recommended System Console settings:

- `Authentication > Signup > Enable account creation`: `false`
- `Authentication > Email > Enable account creation with email`: `false`
- `Users and Teams > Teams > Enable team creation`: use **Advanced Permissions** (`create_team`) if needed; the legacy `EnableTeamCreation` config is deprecated in Mattermost 11
- `Authentication > Password > Minimum password length`: at least `14`
- `Authentication > Password > Require at least one lowercase letter`: `true`
- `Authentication > Password > Require at least one uppercase letter`: `true`
- `Authentication > Password > Require at least one number`: `true`
- `Authentication > Password > Require at least one symbol`: `true`
- `Authentication > MFA > Enable Multi-factor Authentication`: `true`
- `Authentication > MFA > Enforce Multi-factor Authentication`: enable after admins have enrolled

Equivalent config keys for automation:

```text
MM_TEAMSETTINGS_ENABLEUSERCREATION=false
MM_EMAILSETTINGS_ENABLESIGNUPWITHEMAIL=false
MM_TEAMSETTINGS_ENABLEOPENSERVER=false
MM_SERVICESETTINGS_ENABLEMULTIFACTORAUTHENTICATION=true
MM_SERVICESETTINGS_ENFORCEMULTIFACTORAUTHENTICATION=true
```

Do not force these before initial setup unless you already have an admin account path.

## Container Hardening

The Compose template uses `no-new-privileges` and `init: true` for the long-running services.

Additional low-risk container hardening:

- `mattermost-prod` and `mattermost-test` run as the non-root `mattermost` user from the custom image.
- `mattermost-prod`, `mattermost-test`, and `caddy` drop all default Linux capabilities.
- `caddy` adds back only `NET_BIND_SERVICE` so it can bind container ports `80` and `443`.
- PostgreSQL capability dropping remains disabled. A fresh-volume initialization test with `cap_drop: [ALL]` failed, so keeping the official image defaults is safer for reproducible deploys and restores.
- No container should mount `/var/run/docker.sock`.
- No container should run with `privileged: true`.

Rejected for this deployment:

- Docker `userns-remap`, because it changes daemon-wide storage and volume behavior and increases restore/deploy complexity.
- `net.ipv4.ip_unprivileged_port_start=80`, because it lets unrelated unprivileged host processes bind standard web ports.

Deferred until tested:

- `read_only: true`, because Mattermost, PostgreSQL, and Caddy all write runtime state.
- Rootless Docker or Podman, because the current scripts assume Docker Compose and Docker named volumes.

## Host Patching

On OCI Ubuntu, `scripts/bootstrap-host.sh` installs Oracle Ksplice with autoinstall enabled when available. Ksplice applies supported kernel security patches without rebooting, but it does not replace userspace package updates, Docker/containerd updates, Mattermost upgrades, or image rebuilds.

If the running OCI kernel is newer than Ksplice currently supports, `uptrack-upgrade -y` may report that no Ksplice metadata is available yet. Keep autoinstall enabled so updates apply when Oracle publishes support for that kernel.

Ubuntu security package updates are handled by `unattended-upgrades` with daily package-list updates and automatic unattended upgrades enabled. Docker CE packages are included via [`templates/apt/50unattended-upgrades-mattermost`](../templates/apt/50unattended-upgrades-mattermost).

Scheduled reboots, Caddy auto-updates, and weekly update notifications are described in [`docs/15-unattended-updates.md`](15-unattended-updates.md).

## Backup Security

Keep Object Storage buckets private. Backups and the filestore proxy use instance principals (no OCI user API private key on the VM for Object Storage). Mattermost talks only to the local rclone S3 proxy; proxy auth keys live in `/opt/mattermost/.env` (mode `0600`).

Recommended OCI bucket settings (both `mattermost-backups` and `mattermost-files`):

- Private visibility only.
- No public pre-authenticated requests unless deliberately created for a restore.
- Lifecycle rule to expire `daily/` objects on the **backups** bucket after your retention window, for example 30 or 60 days. Do **not** put an expire lifecycle on the files bucket.
- Optional customer-managed Vault key if you want direct key control.
- Backup instance-principal policy scoped to `mattermost-backups` only.
- Filestore instance-principal policy scoped to `mattermost-files` object permissions only (inspect/read/create/overwrite/delete).

### Filestore proxy keys

- Generated by `scripts/render-env.sh` into `.mattermost-secrets.env` / `generated.env` (local to the rclone `serve s3 --auth-key` pair).
- Never commit those files. Rotate by regenerating the keys in secrets, re-rendering rclone is unnecessary (keys are only for Mattermost ↔ rclone), restart Compose.

Local backup retention is controlled by:

```env
LOCAL_BACKUP_RETENTION_DAYS=7
```

Verify backup access:

```sh
oci os object list --auth instance_principal --bucket-name mattermost-backups --prefix daily/ --limit 5
```

## Failure Alerting

The deployment always logs backup and health check failures to systemd journals:

```sh
journalctl -u mattermost-backup.service --no-pager -n 100
journalctl -u mattermost-health.service --no-pager -n 100
```

For active alerts, choose one of:

- OCI Notifications alarm on VM metrics or custom log ingestion.
- `ALERT_WEBHOOK_URL` in `/opt/mattermost/.env` for health and backup script failure notifications (see [`templates/env.example`](../templates/env.example)).
- Manual review through `systemctl --failed` and the journal commands above.

Email alerting remains out of scope until SMTP is intentionally enabled.
