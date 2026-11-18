#!/usr/bin/env bash
# Bootstrap the Puppet Server (compiler/master) node. Idempotent and lintable.
set -Eeuo pipefail
IFS=$'\n\t'

# Vagrant stages the shared library; running locally uses the sibling copy.
PUPPETDEV_LIB="${PUPPETDEV_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh}"
# shellcheck disable=SC1090
source "$PUPPETDEV_LIB"

require_env PUPPETDEV_HOSTNAME
require_env PUPPETDEV_IP
require_env PUPPET_VERSION
require_env PUPPET_SERVER_HOSTNAME
require_env PUPPET_ENVIRONMENT
require_env PUPPET_AUTOSIGN
require_env PUPPET_CONTROL_HTTPS
require_env PUPPET_CONTROL_SSH
require_env PUPPET_CONTROL_BRANCH

log "Bootstrapping puppetserver (Puppet ${PUPPET_VERSION})"

# Certificates are generated from the FQDN, so it must resolve locally first.
add_host_alias "$PUPPETDEV_IP" "$PUPPETDEV_HOSTNAME"
add_host_alias "$PUPPETDEV_IP" "$PUPPET_SERVER_HOSTNAME"
add_host_alias "$PUPPETDEV_IP" "puppet"

apt_refresh
apt_install ca-certificates curl git

# The official release package configures Puppet's signed apt repository.
codename="$(debian_codename)"
release_deb="puppet${PUPPET_VERSION}-release-${codename}.deb"
curl --fail --silent --show-error --location \
  "https://apt.puppet.com/${release_deb}" \
  --output "/tmp/${release_deb}"
apt_install "/tmp/${release_deb}"
rm -f "/tmp/${release_deb}"
apt_refresh
apt_install puppetserver

confdir=/etc/puppetlabs/puppet
# The control repo clone creates environments/production itself.
install -d -m 0755 \
  "${confdir}/environments" \
  "${confdir}/eyaml"

write_if_changed "${confdir}/puppet.conf" "[main]
    server = ${PUPPET_SERVER_HOSTNAME}
    environment = ${PUPPET_ENVIRONMENT}
    environmentpath = ${confdir}/environments
    basemodulepath = ${confdir}/modules
    hiera_config = ${confdir}/hiera.yaml
    dns_alt_names = ${PUPPET_SERVER_HOSTNAME},${PUPPETDEV_HOSTNAME},puppet

    [master]
    autosign = ${confdir}/autosign.conf
    vardir = /opt/puppetlabs/server/data/puppetserver
    logdir = /var/log/puppetlabs/puppetserver
    rundir = /var/run/puppetlabs/puppetserver
    pidfile = /var/run/puppetlabs/puppetserver/puppetserver.pid
    codename = ${PUPPET_ENVIRONMENT}
" 0644

write_if_changed "${confdir}/autosign.conf" "$PUPPET_AUTOSIGN" 0640

# eyaml keys are optional; skip cleanly when the control repo uses plain hiera.
install_secret eyaml_private_key "${confdir}/eyaml/private_key.pkcs7.pem" 0400
install_secret eyaml_public_key "${confdir}/eyaml/public_key.pkcs7.pem" 0444

if [[ ! -f "${confdir}/hiera.yaml" ]]; then
  write_if_changed "${confdir}/hiera.yaml" "---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data
hierarchy:
  - name: Common
    path: common.yaml
  - name: Environment (${PUPPET_ENVIRONMENT})
    path: ${PUPPET_ENVIRONMENT}.yaml
" 0644
fi

install -d -m 0700 /root/.ssh
if [[ -f "${PUPPETDEV_SECRETS_DIR:-/nonexistent}/puppet_control_deploy_key" ]]; then
  log "Deploy key supplied; cloning control repo over SSH"
  install_secret puppet_control_deploy_key /root/.ssh/puppet_control_deploy_key 0600
  repo="$PUPPET_CONTROL_SSH"
  # No ssh-keyscan blind trust: accept-new records the host key on first use.
  export GIT_SSH_COMMAND="ssh -i /root/.ssh/puppet_control_deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
else
  log "No deploy key supplied; cloning control repo over HTTPS"
  repo="$PUPPET_CONTROL_HTTPS"
fi

if [[ ! -d "${confdir}/environments/production/.git" ]]; then
  git clone --depth 1 --branch "$PUPPET_CONTROL_BRANCH" \
    "$repo" "${confdir}/environments/production"
else
  log "Control repo already present; skipping clone"
fi

systemctl enable puppetserver
systemctl restart puppetserver
log "puppetserver started; follow logs with: journalctl -u puppetserver -f"
