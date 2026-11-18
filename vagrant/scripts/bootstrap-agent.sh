#!/usr/bin/env bash
# Bootstrap a Puppet agent node. Idempotent and lintable.
set -Eeuo pipefail
IFS=$'\n\t'

PUPPETDEV_LIB="${PUPPETDEV_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh}"
# shellcheck disable=SC1090
source "$PUPPETDEV_LIB"

require_env PUPPETDEV_HOSTNAME
require_env PUPPETDEV_IP
require_env PUPPET_SERVER_HOSTNAME
require_env PUPPET_SERVER_IP
require_env PUPPET_VERSION
require_env PUPPET_ENVIRONMENT

log "Bootstrapping puppet agent ${PUPPETDEV_HOSTNAME} (Puppet ${PUPPET_VERSION})"

add_host_alias "$PUPPETDEV_IP" "$PUPPETDEV_HOSTNAME"
add_host_alias "$PUPPET_SERVER_IP" "$PUPPET_SERVER_HOSTNAME"
add_host_alias "$PUPPET_SERVER_IP" "puppet"

apt_refresh
apt_install ca-certificates curl

codename="$(debian_codename)"
release_deb="puppet${PUPPET_VERSION}-release-${codename}.deb"
curl --fail --silent --show-error --location \
  "https://apt.puppet.com/${release_deb}" \
  --output "/tmp/${release_deb}"
apt_install "/tmp/${release_deb}"
rm -f "/tmp/${release_deb}"
apt_refresh
apt_install puppet-agent

write_if_changed /etc/puppetlabs/puppet/puppet.conf "[main]
    server = ${PUPPET_SERVER_HOSTNAME}
    certname = ${PUPPETDEV_HOSTNAME}
    environment = ${PUPPET_ENVIRONMENT}

    [agent]
    onetime = true
    daemonize = false
    splay = true
    splaylimit = 60s
" 0644

# The agent is intentionally onetime: no unwanted background daemon in dev.
systemctl disable --now puppet 2>/dev/null || true

if [[ "${PUPPET_ENROLL:-false}" == "true" ]]; then
  log "Requesting a certificate from ${PUPPET_SERVER_HOSTNAME}"
  /opt/puppetlabs/bin/puppet agent --test --waitforcert 30 ||
    log "Enrollment pending; sign it on the server, then run: puppet agent -t"
else
  log "Enrollment skipped (set PUPPET_ENROLL=true to request a certificate)"
fi
