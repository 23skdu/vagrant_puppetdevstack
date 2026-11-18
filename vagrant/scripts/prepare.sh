#!/usr/bin/env bash
# Runs before any file provisioner so staged paths exist with safe permissions.
#
# Vagrant's file provisioner uploads over SCP as the unprivileged SSH user
# (normally `vagrant`), even when the preceding shell provisioner ran with
# `privileged: true`. The staging tree is therefore created root-owned but
# handed to that user, so uploads succeed while the directory stays private.
set -Eeuo pipefail

STAGE_DIR=/tmp/puppetdev

install -d -m 0700 "${STAGE_DIR}" "${STAGE_DIR}/lib" "${STAGE_DIR}/secrets"

# Vagrant's privileged shell provisioner runs via `sudo -E -H`, which sets
# SUDO_USER to the SSH user. Fall back to the conventional `vagrant` account.
stage_owner="${SUDO_USER:-}"
if [[ -z "$stage_owner" || "$stage_owner" == "root" ]]; then
  stage_owner="vagrant"
fi
if id "$stage_owner" >/dev/null 2>&1; then
  chown -R "${stage_owner}:$(id -gn "$stage_owner")" "$STAGE_DIR"
fi
