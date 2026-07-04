# Mattermost OCI Free Tier Deployment

This repository is a reproducible example for running a small self-hosted Mattermost deployment on Oracle Cloud Infrastructure (OCI) Free Tier resources.

It provisions OCI infrastructure with OpenTofu, configures an Ubuntu ARM64 VM, builds a local Mattermost ARM64 image from official release tarballs, and runs Mattermost behind Caddy with PostgreSQL, backups, restore drills, health checks, and host hardening.

## What It Deploys

- OCI `VM.Standard.A1.Flex` compute instance.
- VCN, public subnet, route table, internet gateway, and network security group.
- Private OCI Object Storage bucket for backups.
- Docker Compose stack with:
  - PostgreSQL 16.
  - Mattermost production instance.
  - Mattermost test instance.
  - Caddy reverse proxy with automatic TLS.
- Integrated Mattermost Calls over UDP `8443`.
- Systemd timers for backups and health checks.
- Host hardening with UFW, Fail2ban, SSH hardening, unattended security updates, and optional OCI Ksplice.

## Non-Goals

- This is not a high-availability deployment.
- DNS updates are intentionally manual.
- Email and SSO are intentionally left as later integrations.
- This repo does not commit live secrets, generated environments, OpenTofu state, database dumps, or backup archives.

## Requirements

- macOS or Linux workstation with:
  - OCI CLI configured.
  - OpenTofu installed as `tofu`.
  - SSH key pair for VM access.
  - `rsync`, `ssh`, `python3`, and Docker for local validation.
- OCI tenancy and compartment with permission to manage compute, networking, Object Storage, IAM policy, and dynamic groups.
- Two DNS hostnames, for example:
  - `chat.example.com`
  - `chat-test.example.com`

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

The deploy script prints the VM public IP and pauses for the manual DNS update. After DNS points to the new VM, continue the script to bootstrap the host, build the image, start or restore Mattermost, and run validation.

Start with [`docs/11-reproducible-deployment.md`](docs/11-reproducible-deployment.md) for the full workflow.

## Security Posture

The default deployment keeps the public surface small:

- OCI NSG allows SSH only from the admin CIDR.
- UFW denies inbound traffic except SSH, HTTP, HTTPS, and Calls UDP.
- PostgreSQL is not published on the host.
- Mattermost app ports stay internal to Docker.
- Caddy is the only public HTTP/TLS entry point.
- Long-running containers use `no-new-privileges`; Mattermost and Caddy drop default capabilities.
- Backups use OCI instance principals rather than static API keys on the VM.

See [`docs/09-security-hardening.md`](docs/09-security-hardening.md) and [`docs/12-security-audits.md`](docs/12-security-audits.md).

## Backups And Restore

Backups include Mattermost databases, Mattermost volumes, Caddy volumes, and deployment config snapshots. They are stored locally and uploaded to OCI Object Storage under `daily/<timestamp>/`.

Restore paths:

- Test restore drill: `restore-test-from-backup.sh`.
- Guarded production restore: `restore-production-from-backup.sh`.
- Full rebuild from backup: `deploy-from-zero.sh --restore <backup-timestamp>`.

See [`docs/05-backups-and-restore.md`](docs/05-backups-and-restore.md).

## Repository Layout

```text
.
├── docs/                 # Architecture, operations, hardening, and recovery guides
├── infra/opentofu/       # OCI infrastructure as code
├── scripts/              # Deployment, backup, restore, audit, and host helpers
└── templates/            # Docker Compose, Caddy, systemd, sshd, and image templates
```

## Local Files Not Committed

The following are intentionally ignored:

- `.env`
- `.mattermost-secrets.env`
- `generated.env`
- `infra/opentofu/terraform.tfvars`
- `infra/opentofu/*.tfstate*`
- `infra/opentofu/tfplan`
- `.terraform/`
- backup archives, dumps, private keys, and certificates

## Validation

Run local checks before publishing changes:

```sh
scripts/security-audit.sh --repo-only
tofu -chdir=infra/opentofu validate
```

Run host checks on a deployed VM:

```sh
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/security-audit.sh --host-only
```
