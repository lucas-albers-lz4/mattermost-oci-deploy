# 11 - Reproducible Deployment

This is the target primary workflow for creating a complete Mattermost deployment from an existing OCI CLI configuration.

DNS updates intentionally remain manual. DuckDNS works well for a small free-tier deployment, but any DNS provider that can point hostnames at the VM public IP is fine.

## Preconditions

Local workstation:

- OCI CLI configured and able to run `oci os ns get`.
- OpenTofu installed as `tofu`.
- SSH public key available.
- Admin public IP/CIDR known.
- DNS provider access for the production and test hostnames.

Create local OpenTofu variables:

```sh
cp infra/opentofu/terraform.tfvars.example infra/opentofu/terraform.tfvars
nano infra/opentofu/terraform.tfvars
```

Set `TEST_ALLOWED_CIDR` for generated app config:

```sh
export TEST_ALLOWED_CIDR=<your-admin-ip>/32
```

If your workstation has stale SSH host keys for a rebuilt public IP, use an isolated known-hosts file for the run:

```sh
export SSH_REMOTE_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/mattermost-repro-known-hosts"
```

## Fresh Deployment

```sh
scripts/deploy-from-zero.sh --fresh
```

The script will:

1. Run OpenTofu for OCI infrastructure.
2. Render a complete `.env` from OpenTofu outputs and local secrets.
3. Print the required DNS update.
4. Wait for manual confirmation after DNS is updated.
5. Sync repo assets to the VM.
6. Bootstrap host packages and timers.
7. Apply host hardening with UFW, Fail2ban, and SSH hardening.
8. Build the local ARM64 Mattermost image.
9. Start the production stack (test instance stays idle by default).
10. Validate production, run test once, stop test, and run security checks.

## Restore Deployment

```sh
scripts/deploy-from-zero.sh --restore <backup-timestamp>
```

Restore mode provisions the VM, downloads the selected Object Storage backup, validates checksums, and runs the guarded production restore path.
It restores both production and test data; the test app may be started briefly for validation before returning to idle. See [`docs/14-performance.md`](14-performance.md).

## Manual DNS Checkpoint

After OpenTofu creates the VM, update your DNS records:

```text
<prod-hostname> -> <public-ip>
<test-hostname> -> <public-ip>
```

Continue only after both records resolve to the VM public IP:

```sh
dig +short <prod-hostname>
dig +short <test-hostname>
```

For unattended reruns after DNS has already been verified, set:

```sh
export AUTO_CONFIRM_DNS=true
```

## Validation

On the VM:

```sh
/opt/mattermost/ops/health-check.sh
/opt/mattermost/ops/security-audit.sh --host-only
systemctl list-timers 'mattermost-*'
```

From the repo:

```sh
scripts/security-audit.sh --repo-only
```

## Implementation Notes

- `availability_domain_index` is configurable because A1 Flex capacity can vary by availability domain.
- An existing backup bucket can be preserved by importing `oci_objectstorage_bucket.backups` before `tofu apply`.
- Object Storage lifecycle rules need a tenancy policy for `service objectstorage-<region>` to manage objects in the backup compartment.
- Restore-from-zero skips the pre-restore production backup because a fresh VM has no prior running stack to back up.
- Restore scripts create/update Mattermost database roles before recreating databases so fresh Postgres volumes restore cleanly.
- Container entrypoint and Postgres init scripts must be executable by non-root container users.

## Break-Glass Manual Path

Manual procedures remain documented for debugging and disaster recovery:

- `docs/02-infrastructure.md`
- `docs/03-mattermost-deployment.md`
- `docs/08-redeploy-from-scratch.md`
