# vagrant_puppetdevstack

A reproducible, DevSecOps-oriented Vagrant setup for developing Puppet control
repos. It boots two Debian 12 VMs on an isolated internal network: a Puppet
Server and a Puppet agent.

The stack was rewritten from an inherited root-level Vagrantfile that used an
end-of-life box, unsafe YAML loading, a hardcoded SSH password, blind SSH host
trust, and referenced secrets that had already been removed from git history.
Everything now lives under [`vagrant/`](vagrant/) with validated configuration,
pinned dependencies, lint/security gates and automated dependency updates.

## Quick start

```bash
# Run the full validation, lint and security gate
make check

# Start both VMs
make up

# Inspect
make status
make ssh-server
make ssh-agent
```

Vagrant commands can also be run directly from `vagrant/`:

```bash
cd vagrant && vagrant up
```

## Repository layout

```text
vagrant/       the Vagrant stack: Vagrantfile, config, bootstrap scripts
docs/          usage, architecture analysis and security guidance
scripts/       config validation, security audit and box update tooling
.github/       Dependabot config and GitHub Actions workflows
Makefile       validation, lint (including YAML), security and lifecycle targets
```

## Documentation

- [Usage guide](docs/README.md) - prerequisites, configuration reference,
  secrets, Make targets and troubleshooting.
- [Architecture and modernization decisions](docs/ARCHITECTURE.md) - deep
  analysis of the original stack, threat model and design rationale.

## Dependency maintenance

- Dependabot updates Python (`requirements-dev.txt`), Ruby/Vagrant tooling
  (`vagrant/Gemfile`) and GitHub Actions weekly.
- A scheduled workflow checks Vagrant Cloud and opens a PR when a newer
  VirtualBox-capable box is available.
- Every update is validated by `make STRICT=1 check` in CI.

## Security

No private keys are stored in this repository. Secrets are optional files under
`vagrant/secrets/` (ignored by git), and `make security` scans the worktree and
history for anything sensitive. See [docs/README.md](docs/README.md#secrets).
