# Usage guide

This repository provisions a small, reproducible Puppet development stack with
Vagrant: one Puppet Server (`puppetserver`) and one Puppet agent (`puppetagent`)
on a private internal network.

- [Architecture and modernization decisions](ARCHITECTURE.md)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Secrets](#secrets)
- [Make targets](#make-targets)
- [Keeping dependencies current](#keeping-dependencies-current)
- [Troubleshooting](#troubleshooting)

## Repository layout

```text
.
├── Makefile                     # validation, lint (incl. YAML), security, lifecycle
├── README.md                    # repository overview
├── requirements-dev.txt         # Python tooling (Dependabot-managed)
├── .github/
│   ├── dependabot.yml           # Ruby, Python and Actions dependency updates
│   └── workflows/
│       ├── ci.yml               # STRICT=1 make check on every push/PR
│       └── box-update.yml       # Vagrant Cloud box pin updates via PR
├── docs/                        # this documentation
├── scripts/                     # repository-level validation/security tooling
│   ├── check-box-update.py
│   ├── security-audit.sh
│   └── validate-config.py
└── vagrant/                     # the entire Vagrant stack lives here
    ├── Vagrantfile
    ├── Gemfile                  # Ruby tooling (Dependabot-managed)
    ├── config/
    │   ├── default.yaml         # committed, non-secret defaults
    │   └── default.yaml.example # documented template
    ├── puppet/                  # reference output of generated puppet.conf
    └── scripts/
        ├── prepare.sh
        ├── bootstrap-server.sh
        ├── bootstrap-agent.sh
        └── lib/common.sh
```

The old root-level `Vagrantfile`, `*.conf` and config files were deliberately
moved or removed. Generating the guest config from validated YAML removes the
duplicated `.conf` / `.conf.example` pairs that used to drift apart.

## Prerequisites

| Requirement | Notes |
| --- | --- |
| Vagrant >= 2.4 | https://developer.hashicorp.com/vagrant/downloads |
| VirtualBox 7.x **or** libvirt | both providers are configured; VirtualBox by default |
| >= 4 GB free RAM | 2 GB server + 1 GB agent plus host overhead |
| Python 3 and pip | for config validation and tooling |
| Git | to fetch the Puppet control repository in the guest |

Optional lint/security tools: `shellcheck`, `yamllint`, `rubocop`,
`gitleaks`, `pip-audit`, and `vagrant` itself.

```bash
python3 -m pip install -r requirements-dev.txt
sudo apt-get install -y shellcheck          # or brew install shellcheck
cd vagrant && bundle install                # rubocop + vagrant gems
```

Missing tools are reported as `SKIP` by default. Set `STRICT=1` (as CI does)
to make any missing tool a hard failure.

## Quick start

```bash
# 1. From the repository root, run the offline checks first
make check

# 2. Adjust hostnames / IPs / control repo if needed
$EDITOR vagrant/config/default.yaml

# 3. Optionally add secrets (never commit them)
mkdir -p vagrant/secrets
# cp ~/.ssh/my_deploy_key vagrant/secrets/puppet_control_deploy_key
# cp ~/.ssh/eyaml/private_key.pkcs7.pem vagrant/secrets/eyaml_private_key.pem

# 4. Start both VMs
make up
# or: cd vagrant && vagrant up

# 5. Verify
make status
make ssh-server      # journalctl -u puppetserver -f
make ssh-agent       # /opt/puppetlabs/bin/puppet agent -t --noop
```

To request and sign a certificate during the first agent boot:

```bash
PUPPET_ENROLL=true make up VM=puppetagent
```

Then on the server, inspect and sign the waiting request:

```bash
make ssh-server
sudo /opt/puppetlabs/bin/puppetserver ca list
sudo /opt/puppetlabs/bin/puppetserver ca sign --certname service001.owlsnest
```

`PUPPET_ENROLL=true` is exported by the Vagrantfile into the agent provisioner.
Name-based autosigning (`puppet.autosign`) also accepts matching agent names in
this dev-only stack.

## Configuration reference

All values live in `vagrant/config/default.yaml` (or the file named by
`PUPPETDEV_CONFIG`). Every value is validated before any VM is created.

| Key | Meaning | Default |
| --- | --- | --- |
| `box.name` | Vagrant Cloud box | `debian/bookworm64` |
| `box.version` | Immutable pinned version | `12.20250126.1` |
| `box.checksum` | Optional `sha256`/`sha512` digest | empty |
| `puppet.version` | Puppet major version (`7` or `8`) | `8` |
| `puppet.server_hostname` | FQDN used in certificates and agent config | `puppet.owlsnest` |
| `puppet.environment` | Puppet environment name | `dev` |
| `puppet.autosign` | Dev-only name pattern | `*.owlsnest` |
| `puppet.control_repo.*` | HTTPS/SSH URLs and branch for the control repo | example URLs |
| `network.subnet` | IPv4 CIDR for the host-only network | `10.0.3.0/24` |
| `network.internal_network` | VirtualBox internal network / libvirt network name | `devnetwork` |
| `nodes.<name>.hostname` | Guest hostname (must be a valid FQDN) | see file |
| `nodes.<name>.ip_octet` | Last IP octet, 2-254, unique per node | 42 / 43 |
| `nodes.<name>.memory_mb` | RAM per VM | 2048 / 1024 |
| `nodes.<name>.cpus` | vCPUs per VM | 2 / 1 |
| `gui` | Show VM consoles (or `PUPPETDEV_GUI=true`) | `false` |
| `boot_timeout` | Vagrant boot timeout in seconds | `300` |

The resulting IPs are derived as `network.subnet` host octet +
`nodes.<name>.ip_octet`. There are no hardcoded addresses in the Vagrantfile.

## Secrets

Secrets are optional and live only in the ignored `vagrant/secrets/` directory:

| File | Purpose |
| --- | --- |
| `puppet_control_deploy_key` | Read-only SSH key used to clone the control repo |
| `eyaml_private_key.pem` | hiera-eyaml private key |
| `eyaml_public_key.pem` | hiera-eyaml public key |

If no deploy key is present, the control repo is cloned over HTTPS. If no
eyaml keys are present, hiera simply has no encrypted backend configured.
Missing secrets never break `vagrant up`.

Never commit these files: `vagrant/secrets/` is ignored by git, and the
`security-secrets` Make target scans both the worktree and history.


## Make targets

`make help` prints this list. `STRICT=1` converts skipped tools into failures.

| Target | Purpose |
| --- | --- |
| `check` | Full gate: `validate` + `lint` + `security` |
| `validate` | `vagrant validate` plus YAML config schema validation |
| `lint` | **YAML linting**, shell linting and Ruby linting |
| `lint-yaml` | `yamllint` across every YAML file in the repo |
| `lint-shell` | `shellcheck` across all provisioning scripts |
| `lint-ruby` | `rubocop` on the Vagrantfile and Gemfile |
| `security` | All security checks |
| `security-audit` | Dependency-free scan for insecure patterns and tracked secrets |
| `security-secrets` | `gitleaks` over worktree and history |
| `security-deps` | `pip-audit` on `requirements-dev.txt` |
| `box-check` / `box-update` | Check / apply Vagrant box pin updates |
| `up` / `status` / `provision` / `halt` / `destroy` | Vagrant lifecycle (`VM=...` supported) |
| `ssh-server` / `ssh-agent` | Open a shell on a node |
| `bootstrap-tools` / `clean` | Tool installation help / remove generated state |

## Keeping dependencies current

Three automated paths cover all dependency classes:

1. **Python** (`requirements-dev.txt`) — Dependabot `pip`, weekly.
2. **Ruby / Vagrant tooling** (`vagrant/Gemfile`) — Dependabot `bundler`, weekly.
3. **GitHub Actions** — Dependabot `github-actions`, weekly.
4. **Vagrant box pin** (`box.version`) — not a Dependabot ecosystem; the
   `box-update.yml` workflow queries Vagrant Cloud weekly and opens a PR only
   when a newer release still publishes a VirtualBox provider.

Every Dependabot or box-update PR runs `make STRICT=1 check` before merge.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Configuration file not found` | Run from repo root via `make`, or set `PUPPETDEV_CONFIG` |
| `vagrant validate` fails on a fresh host | Install Vagrant >= 2.4. `make validate-vagrant` uses `--ignore-provider`, so VirtualBox is not required just to validate syntax |
| Puppetserver will not start | `make ssh-server` then `journalctl -u puppetserver -f`; raise `memory_mb` |
| Agent cannot resolve server | Both nodes' `/etc/hosts` aliases are set by bootstrap scripts; check `puppet.server_hostname` |
| Clone fails | Check `puppet.control_repo.*`, network access, and key permissions (`0600`) |
| `make lint` reports SKIP | Install optional tools or run with `STRICT=1` to see exact requirements |
