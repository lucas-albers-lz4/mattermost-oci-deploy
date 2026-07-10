# 05 - Backups And Restore

## Backup Scope

Back up all state needed to recover Mattermost:

- Production database dump
- Test database dump
- Production config/data/plugin/log/index volumes
- Test config/data/plugin/log/index volumes
- Caddy certificate/config volumes
- Compose file and Caddyfile snapshot
- SHA256 checksums

Live message **attachments** are stored in the private Object Storage bucket `mattermost-files` (S3-compatible Mattermost filestore), not as the critical content of the `prod-data` / `test-data` volume tarballs. Daily backups do **not** duplicate that filestore into `mattermost-backups` (Always Free Object Storage is shared, about 20 GB total). Rely on Object Storage durability for attachments; continue DB + config volume backups as above. Optional later hardening: Object Storage versioning on `mattermost-files`.

## Backup Destination

Local short-term copies:

```text
/opt/mattermost/backups/<timestamp>/
```

Off-VM copies:

```text
OCI Object Storage bucket: mattermost-backups
Object prefix: daily/<timestamp>/
```

Keep the bucket private. Use an Object Storage lifecycle rule to expire `daily/` objects after the retention window you choose, for example 30 or 60 days. If you need direct key control, configure the bucket with an OCI Vault customer-managed encryption key.

Local retention is controlled by:

```env
LOCAL_BACKUP_RETENTION_DAYS=7
```

The backup script uses an instance principal, so no user OCI API private key is required on the VM.

## Backup Schedule

Systemd timer:

```text
mattermost-backup.timer
```

`scripts/bootstrap-host.sh` installs and enables this timer from `templates/systemd/`.

Current schedule:

```text
Daily around 08:15 UTC with randomized delay
```

Check it:

```sh
systemctl status mattermost-backup.timer --no-pager
journalctl -u mattermost-backup.service --no-pager -n 100
```

Re-enable it after manual unit changes:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now mattermost-backup.timer
```

## Manual Backup

```sh
/opt/mattermost/ops/backup-mattermost.sh
```

The backup script briefly stops the Mattermost app containers while dumping databases and archiving volumes. It restarts the app containers afterward.

If `ALERT_WEBHOOK_URL` is set in `/opt/mattermost/.env`, backup failures send a JSON webhook:

```json
{"text":"Mattermost backup failed on <host> with exit <status>"}
```

## Restore Drill

A test restore drill should be run after backup changes and before relying on backups.

Restore test from a local backup:

```sh
/opt/mattermost/ops/restore-test-from-backup.sh <backup-timestamp>
```

Verify:

```sh
curl -I https://<test-hostname>/
/opt/mattermost/ops/health-check.sh
```

## Production Restore

Do not run production restore casually.

Download a backup from Object Storage:

```sh
/opt/mattermost/ops/download-backup.sh <backup-timestamp>
```

Run the guarded production restore:

```sh
CONFIRM_PRODUCTION_RESTORE=<backup-timestamp> /opt/mattermost/ops/restore-production-from-backup.sh <backup-timestamp>
```

The production restore script validates checksums and takes a pre-restore backup unless `SKIP_PRE_RESTORE_BACKUP=true` is set.

Before restoring production:

1. Confirm the exact backup timestamp.
2. Verify `SHA256SUMS`.
3. Preserve the failed state if diagnosis matters.
4. Stop only the affected services.
5. Restore matching database and volumes from the same backup timestamp.
6. Start services and verify logs.

Mattermost database migrations may not be safely reversible, so production rollback usually means restoring the database and volumes, not simply switching image tags.
