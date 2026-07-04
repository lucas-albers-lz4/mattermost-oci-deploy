# 08 - Redeploy From Scratch

This is the manual disaster recovery path for a blank replacement VM. Prefer `docs/11-reproducible-deployment.md` for the OpenTofu-driven path.

## Preconditions

You need:

- OCI CLI configured locally.
- Access to the `mattermost` compartment.
- SSH public key for the replacement VM.
- Object Storage bucket `mattermost-backups` with backups.
- DNS access for the production and test hostnames.
- This repo cloned locally or copied to the new VM.

## 1. Provision OCI Infrastructure

Create or reuse:

- Compartment: `mattermost`
- VCN: `mattermost-vcn`
- Public subnet
- Internet gateway
- Route table
- NSG allowing SSH from admin IP and `80/443` from the internet
- A1 VM: `VM.Standard.A1.Flex`, `2 OCPU / 12 GB RAM`
- Object Storage bucket: `mattermost-backups`
- Dynamic group for the VM instance
- Policy allowing that dynamic group to manage object-family in the `mattermost` compartment

See `docs/02-infrastructure.md`.

## 2. Bootstrap The Host

SSH to the new VM:

```sh
ssh ubuntu@<new-public-ip>
```

Clone or copy this repo to the VM, then run:

```sh
cd mattermost-oci-deploy
./scripts/bootstrap-host.sh
```

Edit the generated live env file:

```sh
nano /opt/mattermost/.env
```

Use fresh random passwords for new deployments, or use the restored backup-matching values if restoring existing database state.

Generate random values:

```sh
openssl rand -hex 24
```

## 3. Render Live Configs

Copy templates into live locations if bootstrap did not already do it:

```sh
cp templates/compose.yml /opt/mattermost/compose.yml
cp templates/Caddyfile /opt/mattermost/caddy/Caddyfile
cp templates/mattermost-arm64.Dockerfile /opt/mattermost/mattermost-arm64/Dockerfile
cp templates/mattermost-entrypoint.sh /opt/mattermost/mattermost-arm64/entrypoint.sh
cp templates/postgres-init.sh /opt/mattermost/postgres/init/001-create-mattermost-dbs.sh
cp scripts/backup-mattermost.sh /opt/mattermost/ops/backup-mattermost.sh
cp scripts/download-backup.sh /opt/mattermost/ops/download-backup.sh
cp scripts/restore-test-from-backup.sh /opt/mattermost/ops/restore-test-from-backup.sh
cp scripts/restore-production-from-backup.sh /opt/mattermost/ops/restore-production-from-backup.sh
cp scripts/health-check.sh /opt/mattermost/ops/health-check.sh
cp scripts/harden-host.sh /opt/mattermost/ops/harden-host.sh
cp scripts/build-mattermost-image.sh /opt/mattermost/ops/build-mattermost-image.sh
cp scripts/security-audit.sh /opt/mattermost/ops/security-audit.sh
mkdir -p /opt/mattermost/ops/lib
cp scripts/lib/common.sh /opt/mattermost/ops/lib/common.sh
cp templates/sshd/99-mattermost-hardening.conf /opt/mattermost/ops/99-mattermost-hardening.conf
chmod 755 /opt/mattermost/mattermost-arm64/entrypoint.sh /opt/mattermost/postgres/init/001-create-mattermost-dbs.sh
chmod 750 /opt/mattermost/ops/*.sh
```

Install timers if bootstrap did not already do it:

```sh
sudo install -m 0644 templates/systemd/mattermost-backup.service /etc/systemd/system/mattermost-backup.service
sudo install -m 0644 templates/systemd/mattermost-backup.timer /etc/systemd/system/mattermost-backup.timer
sudo install -m 0644 templates/systemd/mattermost-health.service /etc/systemd/system/mattermost-health.service
sudo install -m 0644 templates/systemd/mattermost-health.timer /etc/systemd/system/mattermost-health.timer
sudo systemctl daemon-reload
sudo systemctl enable --now mattermost-backup.timer mattermost-health.timer
```

Replace Caddy placeholders with real values if Caddy is not reading them from environment:

```text
PROD_HOSTNAME=<prod-hostname>
TEST_HOSTNAME=<test-hostname>
TEST_ALLOWED_CIDR=<your-admin-ip>/32
```

## 4. Restore Or Start Fresh

For a fresh deployment:

```sh
cd /opt/mattermost
/opt/mattermost/ops/build-mattermost-image.sh
docker compose --env-file .env -p mattermost -f compose.yml up -d
```

For disaster recovery, download the desired backup timestamp from Object Storage, place it under:

```text
/opt/mattermost/backups/<timestamp>/
```

Then restore database and volumes. The current repo includes a tested script for test restores:

```sh
/opt/mattermost/ops/restore-test-from-backup.sh <timestamp>
```

Production restore uses a guarded script and must be done deliberately after confirming the backup timestamp and checksums:

```sh
CONFIRM_PRODUCTION_RESTORE=<timestamp> /opt/mattermost/ops/restore-production-from-backup.sh <timestamp>
```

## 5. Update DNS

Point both DNS records at the replacement VM public IP:

- `<prod-hostname>`
- `<test-hostname>`

Verify:

```sh
dig +short <prod-hostname>
dig +short <test-hostname>
```

## 6. Verify

```sh
curl -I https://<prod-hostname>/
curl -I https://<test-hostname>/
/opt/mattermost/ops/health-check.sh
```

Check timers:

```sh
systemctl status mattermost-backup.timer --no-pager
systemctl status mattermost-health.timer --no-pager
```

Apply host and application hardening only after the replacement VM is verified and key-based SSH works from a second session. See `docs/09-security-hardening.md`.

## Current Reproducibility Level

This repo now includes an OpenTofu path for infrastructure and orchestration. DNS updates remain an intentional manual checkpoint.
