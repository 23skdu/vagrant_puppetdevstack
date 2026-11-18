#!/usr/bin/env bash
# Runs before any file provisioner so staged paths exist with safe permissions.
set -Eeuo pipefail

install -d -m 0700 /tmp/puppetdev
install -d -m 0700 /tmp/puppetdev/lib
install -d -m 0700 /tmp/puppetdev/secrets
