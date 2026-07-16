# Documentation Index

Start here based on your role.

## By audience

| Audience | Start here |
|----------|------------|
| Parents and families | [for-parents.md](for-parents.md) |
| Community organizers / admins | [community-channel-policy.md](community-channel-policy.md) · [for-parents.md](for-parents.md) · [Community Admin plugin user guide](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin/blob/main/docs/user-guide.md) (screenshots: [images/community-admin/](images/community-admin/)) · install: [06-operations.md § Community Admin](06-operations.md#community-admin-plugin-delegated-organizers) |
| New deployment | [11-reproducible-deployment.md](11-reproducible-deployment.md) · [01-oci-account-and-cli.md](01-oci-account-and-cli.md) |
| Day-2 operations | [06-operations.md](06-operations.md) (includes [sync ops scripts](06-operations.md#sync-ops-scripts-from-git-day-2)) · [07-upgrades.md](07-upgrades.md) · [15-unattended-updates.md](15-unattended-updates.md) |
| Security review | [09-security-hardening.md](09-security-hardening.md) · [12-security-audits.md](12-security-audits.md) |
| Recovery | [05-backups-and-restore.md](05-backups-and-restore.md) · [08-redeploy-from-scratch.md](08-redeploy-from-scratch.md) |

## Numbered guides

| Doc | Description |
|-----|-------------|
| [00-architecture.md](00-architecture.md) | Components, data flow, design decisions |
| [01-oci-account-and-cli.md](01-oci-account-and-cli.md) | OCI account setup and CLI |
| [02-infrastructure.md](02-infrastructure.md) | Free tier sizing, networking, Object Storage |
| [03-mattermost-deployment.md](03-mattermost-deployment.md) | Mattermost image, Compose, prod/test layout |
| [04-dns-and-tls.md](04-dns-and-tls.md) | DNS and Caddy TLS |
| [05-backups-and-restore.md](05-backups-and-restore.md) | Backup schedule, restore drills |
| [06-operations.md](06-operations.md) | Logs, restarts, health checks, Community Admin plugin |
| [07-upgrades.md](07-upgrades.md) | Mattermost version upgrades (test first) |
| [08-redeploy-from-scratch.md](08-redeploy-from-scratch.md) | Manual redeploy and disaster recovery |
| [09-security-hardening.md](09-security-hardening.md) | Firewall, SSH, Mattermost account controls |
| [10-audio-video-calls.md](10-audio-video-calls.md) | Mattermost Calls plugin and UDP |
| [11-reproducible-deployment.md](11-reproducible-deployment.md) | Primary deploy-from-zero workflow |
| [12-security-audits.md](12-security-audits.md) | Repo and host audit scripts |
| [14-performance.md](14-performance.md) | Free-tier tuning, idle test instance |
| [15-unattended-updates.md](15-unattended-updates.md) | OS patching, Caddy auto-update, alerts |

## Community and parent docs (unnumbered)

| Doc | Description |
|-----|-------------|
| [for-parents.md](for-parents.md) | Plain-language summary for families |
| [community-channel-policy.md](community-channel-policy.md) | Teams, channels, DM/call policy worksheet |

## Infrastructure code

| Path | Description |
|------|-------------|
| [../infra/opentofu/README.md](../infra/opentofu/README.md) | OpenTofu stack for OCI |

## Contributing and security

| Doc | Description |
|-----|-------------|
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute and publish checklist |
| [../SECURITY.md](../SECURITY.md) | Vulnerability reporting |
