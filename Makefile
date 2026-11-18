# Makefile for the Puppet development stack.
# Run `make help` for the target list. STRICT=1 turns missing-tool skips into
# hard failures, which is what CI should use.

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

ROOT        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VAGRANT_DIR := $(ROOT)/vagrant
CONFIG      := $(VAGRANT_DIR)/config/default.yaml
PYTHON      ?= python3
VM          ?=
STRICT      ?= 0

# Emit a SKIP (or a hard error in STRICT mode) when an optional tool is absent.
CHECK_TOOL = if ! command -v $(1) >/dev/null 2>&1; then \
  if [ "$(STRICT)" = "1" ]; then echo "ERROR: $(1) is required. $(2)" >&2; exit 1; fi; \
  echo "SKIP: $(1) not installed ($(2))"; exit 0; \
  fi;

.PHONY: help python-ready validate-config validate-vagrant validate \
        lint-yaml lint-shell lint-ruby lint \
        security-audit security-secrets security-deps box-check box-update security \
        check up status halt destroy provision ssh-server ssh-agent \
        bootstrap-tools clean

.DEFAULT_GOAL := help

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Puppet dev stack\n\nUsage: make \033[36m<target>\033[0m [STRICT=1] [VM=puppetagent]\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

python-ready: ## Verify PyYAML is available (STRICT=1 makes this fatal)
	@if ! $(PYTHON) -c 'import yaml' >/dev/null 2>&1; then \
	  if [ "$(STRICT)" = "1" ]; then echo "ERROR: PyYAML missing. pip install -r requirements-dev.txt" >&2; exit 1; fi; \
	  echo "SKIP: PyYAML not installed (pip install -r requirements-dev.txt)"; exit 0; \
	fi

validate-config: python-ready ## Validate config/default.yaml schema and values
	$(PYTHON) scripts/validate-config.py "$(CONFIG)"

validate-vagrant: ## Run `vagrant validate` on the rewritten Vagrantfile
	$(call CHECK_TOOL,vagrant,install from developer.hashicorp.com/vagrant)
	cd "$(VAGRANT_DIR)" && vagrant validate --ignore-provider

validate: validate-config validate-vagrant ## Run all syntax/config validation

# ---------------------------------------------------------------------------
# Linting (lint includes YAML linting)
# ---------------------------------------------------------------------------

lint-yaml: ## Lint every YAML file (yamllint)
	$(call CHECK_TOOL,yamllint,pip install -r requirements-dev.txt)
	yamllint -c .yamllint.yml .

lint-shell: ## Lint all provisioning and helper shell scripts (shellcheck)
	$(call CHECK_TOOL,shellcheck,apt-get install shellcheck)
	shellcheck --severity=warning vagrant/scripts/*.sh vagrant/scripts/lib/*.sh scripts/*.sh

lint-ruby: ## Lint the Vagrantfile and Gemfile (rubocop)
	$(call CHECK_TOOL,rubocop,cd vagrant && bundle install)
	cd "$(VAGRANT_DIR)" && rubocop --config "$(ROOT)/.rubocop.yml" Vagrantfile Gemfile

lint: lint-yaml lint-shell lint-ruby ## Run all linters (YAML, shell, Ruby)

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------

security-audit: ## Run the dependency-free insecure-pattern audit
	bash scripts/security-audit.sh

security-secrets: ## Scan worktree and history for secrets (gitleaks)
	$(call CHECK_TOOL,gitleaks,install from github.com/gitleaks/gitleaks/releases)
	gitleaks detect --source "$(ROOT)" --redact --no-banner

security-deps: ## Scan Python dependencies for known vulnerabilities (pip-audit)
	$(call CHECK_TOOL,pip-audit,pip install -r requirements-dev.txt)
	pip-audit -r requirements-dev.txt

box-check: python-ready ## Fail if a newer VirtualBox-capable Vagrant box exists
	$(PYTHON) scripts/check-box-update.py --check

box-update: python-ready ## Rewrite config/default.yaml to the latest box version
	$(PYTHON) scripts/check-box-update.py --update

security: security-audit security-secrets security-deps box-check ## Run all security checks

check: validate lint security ## Full gate: validation + lint + security

# ---------------------------------------------------------------------------
# Vagrant lifecycle
# ---------------------------------------------------------------------------

up: ## Start the stack (optionally VM=puppetserver|puppetagent)
	cd "$(VAGRANT_DIR)" && vagrant up $(VM)

status: ## Show VM status
	cd "$(VAGRANT_DIR)" && vagrant status

provision: ## Re-run provisioning scripts
	cd "$(VAGRANT_DIR)" && vagrant provision $(VM)

halt: ## Stop the VMs
	cd "$(VAGRANT_DIR)" && vagrant halt $(VM)

destroy: ## Destroy the VMs (prompts per VM)
	cd "$(VAGRANT_DIR)" && vagrant destroy $(VM)

ssh-server: ## SSH into the Puppet Server node
	cd "$(VAGRANT_DIR)" && vagrant ssh puppetserver

ssh-agent: ## SSH into the Puppet agent node
	cd "$(VAGRANT_DIR)" && vagrant ssh puppetagent

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

bootstrap-tools: ## Print/ install the local lint and security toolchain
	$(PYTHON) -m pip install -r requirements-dev.txt
	@echo "Also install: shellcheck, vagrant, rubocop (cd vagrant && bundle install), gitleaks"

clean: ## Remove Vagrant state and Python caches
	rm -rf "$(VAGRANT_DIR)/.vagrant"
	find "$(ROOT)" -type d -name '__pycache__' -prune -exec rm -rf {} +
