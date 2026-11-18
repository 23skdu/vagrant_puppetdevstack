#!/usr/bin/env bash
# Shared helpers for the Puppet dev stack. Source this file; never execute it.

set -Eeuo pipefail

log() {
  printf '\n[==>] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required environment variable: ${name}"
}

apt_refresh() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends "$@"
}

# Idempotent file writer: only replaces the destination when content changes.
write_if_changed() {
  local destination="$1" content="$2" mode="${3:-0644}" tmp
  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  if [[ -f "$destination" ]] && cmp -s "$tmp" "$destination"; then
    log "Unchanged ${destination}"
  else
    install -d -m 0755 "$(dirname "$destination")"
    install -m "$mode" "$tmp" "$destination"
    log "Wrote ${destination}"
  fi
  rm -f "$tmp"
}

# Append an /etc/hosts entry once, without duplicating it on re-provision.
add_host_alias() {
  local ip="$1" host="$2"
  grep -qF "${ip} ${host}" /etc/hosts || printf '%s %s\n' "$ip" "$host" >>/etc/hosts
}

# Optional secrets are staged by Vagrant only when the file exists locally.
install_secret() {
  local name="$1" destination="$2" mode="${3:-0600}" owner="${4:-root:root}"
  local source="${PUPPETDEV_SECRETS_DIR:?}/${name}"

  if [[ ! -f "$source" ]]; then
    log "Optional secret '${name}' not supplied; skipping"
    return 0
  fi

  install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$source" "$destination"
  log "Installed secret ${name} -> ${destination}"
}

# Resolve the Debian codename instead of hardcoding it in multiple places.
debian_codename() {
  local codename
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  [[ "$codename" == "bookworm" ]] || die "Expected Debian 12 (bookworm), got '${codename}'"
  printf '%s' "$codename"
}
