# 01 - OCI Account And CLI

## Account Setup

1. Sign up for Oracle Cloud Free Tier.
2. Choose the home region carefully. Always Free compute must run in the home region.
3. Enable MFA on the main/admin Oracle account.
4. Create a compartment named `mattermost`.
5. Create a deploy user or use your admin user only for initial bootstrap.
6. Configure an OCI API signing key locally.

Do not share Oracle passwords, MFA codes, payment details, private API keys, or SSH private keys.

## Local CLI Setup

On macOS:

```sh
brew install oci-cli
```

Expected local config path:

```text
~/.oci/config
```

Expected config shape:

```ini
[DEFAULT]
user=ocid1.user.oc1..example
fingerprint=xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..example
region=us-phoenix-1
key_file=~/.oci/oci_api_key.pem
```

Repair config permissions if needed:

```sh
oci setup repair-file-permissions --file ~/.oci/config
```

Verify access:

```sh
oci os ns get
oci iam region-subscription list
```

Use your OCI home region for Always Free compute. The examples use `us-phoenix-1`.

## Credentials Needed For Automation

You need these values locally:

- Tenancy OCID
- Mattermost compartment OCID
- Region
- SSH public key
- OCI API key configured in `~/.oci/config`

Keep these out of source control:

- `~/.oci/oci_api_key.pem`
- `.env`
- Database dumps
- Backup archives
