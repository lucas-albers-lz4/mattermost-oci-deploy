# Mattermost on OCI Free Tier

Private, self-hosted Mattermost on Oracle Cloud Infrastructure Always Free resources — a single VM with OpenTofu, Docker Compose, backups, and security hardening. This is **not** Discord, **not** high-availability enterprise chat, and **not** a managed SaaS product.

## Who this is for

- **Parents and community organizers** — how access works, what is and is not promised: [For parents and families](docs/for-parents.md) · [Community channel policy worksheet](docs/community-channel-policy.md)
- **Operators deploying their own** — Quick Start below and [Reproducible deployment](docs/11-reproducible-deployment.md)
- **Engineers reviewing the project** — [Architecture](docs/00-architecture.md) (includes [design decisions](docs/00-architecture.md#design-decisions)), [Security hardening](docs/09-security-hardening.md), [OpenTofu stack](infra/opentofu/README.md)

## What you get

- OCI `VM.Standard.A1.Flex` compute, VCN, NSG, private Object Storage for backups and Mattermost file attachments (~$0 on Always Free; see OCI terms and your usage; ~20 GB Object Storage shared across buckets).
- Docker Compose: PostgreSQL 16, Mattermost production + test, Caddy with automatic TLS.
- Mattermost Calls over UDP `8443`; Bleve search (no Elasticsearch).
- Daily backups, restore drills, health checks, and security audit scripts.
- Host hardening: UFW, Fail2ban, SSH restrictions, unattended OS security updates, Caddy auto-update, optional alert webhooks.
- Optional [**Community Admin**](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin) plugin (`com.lalbers.community-admin`) for delegated organizer user management — see [Operations § Community Admin](docs/06-operations.md#community-admin-plugin-delegated-organizers).

## Limitations

Tradeoffs:

- **Single VM** — no HA; maintenance and upgrades can cause downtime.
- **No end-to-end encryption** — the operator can read stored messages and backups.
- **Not COPPA-certified** — adults are responsible for age and consent choices.
- **Manual Mattermost/Postgres upgrades** — OS and Caddy patch automatically; app upgrades follow [docs/07-upgrades.md](docs/07-upgrades.md).
- **Community shape is team/channel-based** — DM and call restrictions require deliberate policy and operator configuration; see [for-parents.md](docs/for-parents.md).

## Architecture

Component diagram and data flow: [docs/00-architecture.md](docs/00-architecture.md).

## Quick Start

Create local OpenTofu variables:

```sh
cp infra/opentofu/terraform.tfvars.example infra/opentofu/terraform.tfvars
$EDITOR infra/opentofu/terraform.tfvars
```

Set the admin/test access CIDR:

```sh
export TEST_ALLOWED_CIDR=<your-admin-ip>/32
```

Deploy a fresh stack:

```sh
scripts/deploy-from-zero.sh --fresh
```

Or restore from an existing backup timestamp:

```sh
scripts/deploy-from-zero.sh --restore <backup-timestamp>
```

The deploy script prints the VM public IP and pauses for manual DNS. After DNS points to the new VM, continue to bootstrap, build the image, start or restore Mattermost, and validate.

Full workflow: [docs/11-reproducible-deployment.md](docs/11-reproducible-deployment.md).

After Mattermost is running, install the optional [Community Admin plugin](https://github.com/lucas-albers-lz4/mattermost-plugin-community-admin) if organizers need to create users and reset passwords without System Console access: [docs/06-operations.md](docs/06-operations.md#community-admin-plugin-delegated-organizers).

## Documentation

Complete index by audience: [docs/README.md](docs/README.md).

## Security

Default posture: SSH from admin CIDR only, UFW, internal Postgres, Caddy as sole HTTP/TLS entry, instance-principal backups and filestore (rclone S3 proxy). See [docs/09-security-hardening.md](docs/09-security-hardening.md) and [docs/12-security-audits.md](docs/12-security-audits.md).

## Performance and maintenance

- [docs/14-performance.md](docs/14-performance.md) — Postgres caps, idle test instance, Go limits.
- [docs/15-unattended-updates.md](docs/15-unattended-updates.md) — OS patching, Caddy updates, update alerts.

## Backups and restore

See [docs/05-backups-and-restore.md](docs/05-backups-and-restore.md).

## Repository layout

```text
.
├── docs/                 # Architecture, operations, parent/community guides
├── infra/opentofu/       # OCI infrastructure as code
├── scripts/              # Deploy, backup, restore, audit, host helpers
└── templates/            # Compose, Caddy, systemd, sshd, image templates
```

## Local files not committed

`.env`, `.mattermost-secrets.env`, `generated.env`, `terraform.tfvars`, `*.tfstate*`, backup archives, keys, and certificates — see [`.gitignore`](.gitignore).

## Validation

```sh
scripts/security-audit.sh --repo-only
tofu -chdir=infra/opentofu init -backend=false && tofu -chdir=infra/opentofu validate
```

On a deployed VM:

```sh
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/security-audit.sh --host-only
```

## Contributing and security

- [CONTRIBUTING.md](CONTRIBUTING.md) — PR expectations and publish checklist
- [SECURITY.md](SECURITY.md) — vulnerability reporting

## License

MIT — see [LICENSE](LICENSE).
