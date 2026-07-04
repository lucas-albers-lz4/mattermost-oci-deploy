# OpenTofu OCI Infrastructure

This directory provisions the OCI resources needed by the Mattermost Free Tier deployment.

## Resources

- VCN, public subnet, internet gateway, route table, and NSG.
- A1 Flex VM with Ubuntu 24.04 ARM64.
- Object Storage bucket for backups.
- Object Storage lifecycle rule for `daily/` backup retention.
- Dynamic group and IAM policy for instance-principal backup uploads.
- IAM policy allowing the regional Object Storage service principal to run lifecycle expiration.
- Cloud-init bootstrap directories under `/opt/mattermost`.

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
