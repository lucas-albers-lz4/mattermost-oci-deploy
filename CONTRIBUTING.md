# Contributing

Thank you for improving this deployment. This project targets a small, reproducible Mattermost stack on OCI Free Tier — keep changes focused and operable.

## Before you open a PR

1. Run the repo audit:

```sh
scripts/security-audit.sh --repo-only
```

2. If you changed OpenTofu:

```sh
tofu -chdir=infra/opentofu fmt
tofu -chdir=infra/opentofu init -backend=false
tofu -chdir=infra/opentofu validate
```

3. Do **not** commit secrets, live hostnames, OCIDs, webhook URLs, or state files.

## Pull request expectations

- Describe **why** the change helps operators, security, or documentation readers.
- Note whether you tested on a live VM or only ran repo checks.
- Keep diffs minimal; match existing shell script and doc style.

## Publish checklist (maintainers)

Before pushing to a public GitHub repository:

1. `gitleaks detect --source .` (or rely on CI gitleaks job)
2. `scripts/security-audit.sh --repo-only`
3. Confirm `git status` shows no `.env`, `*.tfvars`, `*.tfstate*`, `.mattermost-secrets.env`
4. Confirm no real IPs, hostnames, or webhook tokens in tracked files
5. Create the GitHub repo, push `main`, enable Actions
6. Set repo description and topics: `mattermost`, `oci`, `opentofu`, `docker-compose`, `self-hosted`

After publish, never paste live webhook URLs or tenancy OCIDs in issues or PRs.

## Security

See [`SECURITY.md`](SECURITY.md).

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
