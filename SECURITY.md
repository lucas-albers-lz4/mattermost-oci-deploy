# Security Policy

## Supported versions

Security fixes apply to the `main` branch of this deployment repository. There is no long-term release branch.

Application security (Mattermost, PostgreSQL, Caddy) depends on upstream projects and your upgrade process. See [`docs/07-upgrades.md`](docs/07-upgrades.md) and [`docs/15-unattended-updates.md`](docs/15-unattended-updates.md).

## Reporting a vulnerability

If you believe you found a security issue in **this repository** (scripts, OpenTofu, Compose templates, documentation that leads to unsafe defaults):

1. **Do not** open a public GitHub issue with exploit details.
2. Use [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) for this repository if enabled, or contact the repository maintainer directly.

Include:

- Description and impact
- Steps to reproduce
- Suggested fix if you have one

We aim to acknowledge reports within a reasonable time. There is no bug bounty program.

## Out of scope

- Vulnerabilities in Mattermost Server, PostgreSQL, Caddy, or OCI themselves — report to those projects or your operator.
- Misconfigurations on a live deployment (weak passwords, exposed secrets, open SSH) — operator responsibility.
- Social engineering or account compromise on a private community instance.

## Safe deployment reminders

- Never commit `.env`, `terraform.tfvars`, OpenTofu state, or webhook URLs.
- Run `scripts/security-audit.sh --repo-only` before publishing changes.
- Run `scripts/security-audit.sh --host-only` on the VM after deploy.

See [`docs/09-security-hardening.md`](docs/09-security-hardening.md) and [`docs/12-security-audits.md`](docs/12-security-audits.md).
