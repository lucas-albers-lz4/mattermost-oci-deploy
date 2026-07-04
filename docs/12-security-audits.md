# 12 - Security Audits

Use `scripts/security-audit.sh` for repeatable security checks.

## Repo Audit

Run from the repo root:

```sh
scripts/security-audit.sh --repo-only
```

Checks:

- Shell syntax.
- `shellcheck` if installed.
- Docker Compose rendering.
- OpenTofu formatting and validation when initialized.
- `trivy config` if installed.
- `gitleaks` if installed.

Missing optional tools are warnings. Syntax and Compose failures are errors.

## Host Audit

Run on the VM:

```sh
/opt/mattermost/ops/security-audit.sh --host-only
```

Checks:

- UFW active.
- Calls UDP `8443` allowed.
- Fail2ban active.
- SSH config validates.
- Unattended upgrades enabled.
- Daily unattended security updates configured.
- Ksplice installed and autoinstall enabled when available on OCI.
- Health and backup timers active.
- Docker published ports do not expose PostgreSQL.
- Caddy config validates.
- Containers are not privileged.
- Containers do not mount `/var/run/docker.sock`.
- Containers keep `no-new-privileges`.
- Mattermost and Caddy use the expected capability drops/additions.
- PostgreSQL capability dropping is reported as a warning, not a failure, because fresh-volume initialization failed with `cap_drop: [ALL]`.
- Docker seccomp/AppArmor are not explicitly disabled.
- Mattermost health check passes.

## Manual App Audit

Mattermost app settings still require admin UI/API verification:

- Open signup disabled.
- Email signup disabled unless intentionally enabled.
- Team creation restricted.
- Strong password policy.
- MFA enabled and enforced after admin enrollment.
- Calls plugin enabled with correct ICE Host Override.

Record the date and outcome of each manual app audit in operational notes.
