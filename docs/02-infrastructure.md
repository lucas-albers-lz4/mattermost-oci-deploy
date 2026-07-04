# 02 - Infrastructure

## Target Architecture

One OCI Always Free ARM VM runs Docker Compose:

- Caddy reverse proxy on `80/443`
- Mattermost production container
- Mattermost test container
- Shared PostgreSQL container with separate prod/test databases
- Docker named volumes for persistent state
- OCI Object Storage bucket for off-VM backups

## OCI Free Tier Guardrails

Current Always Free A1 budget:

- `2 OCPU`
- `12 GB RAM`
- `200 GB` total block volume storage

Recommended VM:

- Shape: `VM.Standard.A1.Flex`
- Size: `2 OCPU / 12 GB RAM`
- OS: Ubuntu 24.04 ARM64
- Boot volume: default around 47-50 GB

## Network

Create in the `mattermost` compartment:

- VCN: `mattermost-vcn`
- CIDR: `10.20.0.0/16`
- Public subnet: `mattermost-public-subnet`
- Subnet CIDR: `10.20.1.0/24`
- Internet gateway: `mattermost-igw`
- Route table with `0.0.0.0/0` to the internet gateway
- NSG: `mattermost-nsg`

NSG ingress rules:

| Port | Source | Purpose |
| --- | --- | --- |
| `22/tcp` | Admin public IP only | SSH |
| `80/tcp` | `0.0.0.0/0` | HTTP redirect / ACME |
| `443/tcp` | `0.0.0.0/0` | HTTPS |
| `8443/udp` | `0.0.0.0/0` | Mattermost Calls media |

NSG egress:

| Destination | Purpose |
| --- | --- |
| `0.0.0.0/0` | Package installs, image pulls, OCI Object Storage uploads |

Do not keep temporary app ports like `8080` open after DNS/TLS is configured. Do not expose PostgreSQL or Mattermost `8000/tcp` directly.

After SSH is verified, apply the host firewall and SSH hardening steps in `docs/09-security-hardening.md`.

## Object Storage

Create bucket:

```text
mattermost-backups
```

Use private access only.

The deployment uses an instance principal:

- Dynamic group: `MattermostBackupWriters`
- Matching rule: target VM instance OCID
- Policy: allow the dynamic group to manage Object Storage objects in the `mattermost` compartment

Policy shape:

```text
Allow dynamic-group MattermostBackupWriters to manage object-family in compartment mattermost
```

This lets the VM upload backups without placing your user API private key on the host.

Also configure lifecycle retention for the `daily/` backup prefix and keep the bucket private. See `docs/09-security-hardening.md` for the security checklist.

## Capacity Notes

If OCI returns `Out of host capacity`, retry the A1 launch in another availability domain in the same region. This is capacity pressure, not a local configuration problem.

If OCI returns A1 limit errors, check for stopped A1 instances. Stopped A1 VMs can still reserve core and memory quota.
