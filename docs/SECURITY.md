# Security posture

## Summary

This repository is a local Puppet development stack. It is designed so a fresh
clone can be provisioned without any private credentials, while still allowing
a developer to opt into a private control repository and hiera-eyaml
encryption. Security is enforced at three points: pre-commit via `make check`,
on every push/PR via CI, and continuously via Dependabot plus the box-update
workflow.

## Controls

| Control | Implementation |
| --- | --- |
| Safe configuration parsing | `YAML.safe_load`; no `YAML.load`/`load_file` anywhere |
| Configuration validation | `scripts/validate-config.py` enforces hostnames, CIDR, octet ranges, Puppet version, URLs, resource values |
| Immutable base image | Pinned `box.version`; optional SHA-256/SHA-512 `box.checksum` |
| Signed package sources | Puppet's official release `.deb` configures a signed apt repository |
| Key-only SSH | `keys_only`, `insert_key`, no password, no agent/X11 forwarding |
| Host key handling | HTTPS by default; SSH uses an explicit identity and `StrictHostKeyChecking=accept-new` (persistent TOFU), never blind `ssh-keyscan` |
| Minimal guest exposure | `/vagrant` synced folder disabled; only required files uploaded |
| Least privilege in provisioning | Scripts run privileged but install only required packages with `--no-install-recommends` |
| Idempotent scripts | `set -Eeuo pipefail`, `write_if_changed`, `add_host_alias`, `install_secret` |
| Secret hygiene | Everything under `vagrant/secrets/` is ignored; broad ignore patterns for keys/certs |
| Static analysis | `shellcheck`, `yamllint`, `rubocop`, `scripts/security-audit.sh` |
| Secret scanning | `gitleaks` on worktree and history; the single known legacy finding is fingerprinted in `.gitleaksignore` so new leaks still fail CI; `pip-audit` for Python dependencies |
| Dependency freshness | Dependabot (pip, bundler, github-actions) and a scheduled Vagrant box PR workflow |

Run all of them with:

```bash
make check
```

## Secret workflow

1. Create the ignored directory: `mkdir -p vagrant/secrets`.
2. Add only the files you need:
   - `puppet_control_deploy_key` (a read-only deploy key), or rely on HTTPS;
   - `eyaml_private_key.pem` and `eyaml_public_key.pem`, if your control repo
     uses hiera-eyaml.
3. Verify nothing sensitive is staged:

   ```bash
   git status --short
   make security-secrets
   ```

4. Use a dedicated, read-only deploy key scoped to the control repository.
   Do not reuse your personal SSH key.
5. Rotate keys on a schedule and immediately if a workstation is lost.

Development-only autosign (`puppet.autosign`, default `*.owlsnest`) must never
be used in production. Sign certificates through `puppetserver ca` there.

## Historical exposure - action required

Earlier commits in this repository added and then deleted private material:

| Commit | Deleted file |
| --- | --- |
| `5b54837` | `puppet_private_key.pkcs7.pem` |
| `041417f` | `puppet_public_key.pkcs7.pem` |
| `ffef0ab` | `puppetdev_deploykey` |
| `6dca21d` | `puppetdev_deploykey.pub` |

Deleting a file in a later commit does **not** remove it from git history.
Anyone with access to the repository (or a clone made while those commits were
present) can recover the private deploy key and the eyaml private key. This
rewrite removes them from the working tree and prevents reintroduction, but it
cannot unpublish history.

Until rotation and history purge happen, the one finding from commit `0cd1194`
is recorded in `.gitleaksignore`. This keeps gitleaks scanning all history and
allows CI to pass; it is an explicit triage record, not a fix. Remove that line
after the purge.

Required follow-up, in order:

1. **Rotate the deploy key.** Generate a new key pair, replace the deploy key on
   the control repository, delete the old one, and store the new private key in
   `vagrant/secrets/`.
2. **Rotate the eyaml keys.** Generate a new pair, re-encrypt every encrypted
   hiera value with the new public key, distribute the new private key to
   consumers, and retire the old pair.
3. **Optionally purge history** once consumers have rotated. This is a
   destructive, coordinated operation and was intentionally not performed as
   part of this rewrite:

   ```bash
   git clone --mirror git@github.com:23skdu/vagrant_puppetdevstack.git /tmp/purge.git
   cd /tmp/purge.git
   git filter-repo --invert-paths \
     --path puppet_private_key.pkcs7.pem \
     --path puppet_public_key.pkcs7.pem \
     --path puppetdev_deploykey \
     --path puppetdev_deploykey.pub
   git push --force --all
   git push --force --tags
   ```

   Coordinate with every collaborator, revoke tokens/keys that reference old
   commits, and assume the old material is still compromised even after the
   purge. Rotation is the control that actually fixes the exposure.

## Reporting

If you find a vulnerability in this stack, open a private security advisory on
the GitHub repository rather than a public issue. Include the affected path,
impact and a reproduction; do not include real secrets in the report.
