# OpenTofu OCI Infrastructure

This directory provisions the OCI resources needed by the Mattermost Free Tier deployment.

## Resources

- VCN, public subnet, internet gateway, route table, and NSG.
- A1 Flex VM with Ubuntu 24.04 ARM64.
- Object Storage bucket for backups (`mattermost-backups` by default).
- Object Storage bucket for Mattermost file attachments (`mattermost-files` by default).
- Object Storage lifecycle rule for `daily/` backup retention (backups bucket only).
- Dynamic group and bucket-scoped IAM policies for instance-principal access to backups and filestore.
- IAM policy allowing the regional Object Storage service principal to run lifecycle expiration.
- Cloud-init bootstrap directories under `/opt/mattermost`.

Mattermost uses the `amazons3` driver against an on-VM `rclone serve s3` proxy. rclone authenticates to Object Storage with the VM instance principal (no OCI customer secret keys on the host).

## Manual DNS Checkpoint

DNS is intentionally not automated. After `tofu apply`, update these records manually:

```text
<prod_hostname> -> <public_ip>
<test_hostname> -> <public_ip>
```

The outputs include the public IP and expected hostnames.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
tofu init
tofu plan
tofu apply
tofu output
```

Keep `terraform.tfvars` out of source control.

Set `availability_domain_index` if A1 Flex capacity is unavailable in the default availability domain. Existing backup buckets can be preserved by importing `oci_objectstorage_bucket.backups` before apply.
