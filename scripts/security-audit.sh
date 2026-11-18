#!/usr/bin/env bash
# Dependency-free static security audit for this repository.
# Docs are intentionally excluded: they describe insecure patterns as examples.

set -Eeuo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

findings=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  findings=$((findings + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

scan_code() {
  local pattern="$1" label="$2"
  local matches
  matches="$(grep -rEnI --binary-files=without-match \
    --include='Vagrantfile' --include='*.rb' --include='*.sh' --include='*.yaml' --include='*.yml' \
    --exclude-dir=.git --exclude-dir=docs --exclude-dir=.vagrant --exclude-dir=.venv \
    --exclude='security-audit.sh' \
    -- "$pattern" vagrant scripts .github 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    fail "${label}: ${matches//$'\n'/; }"
  else
    pass "${label}: no matches"
  fi
}

printf '== Static insecure-pattern checks ==\n'

scan_code 'YAML\.load(_file)?[[:space:]]*\(' 'unsafe YAML deserialization'
scan_code 'ssh\.password[[:space:]]*=' 'SSH password authentication'
scan_code 'forward_agent[[:space:]]*=[[:space:]]*true' 'SSH agent forwarding'
scan_code 'box_download_insecure[[:space:]]*=[[:space:]]*true' 'insecure box download'
scan_code 'ssh-keyscan.*>.*known_hosts' 'blind ssh-keyscan trust'
scan_code 'StrictHostKeyChecking[=[:space:]]+no' 'disabled host key verification'
scan_code 'debian/(jessie|wheezy|stretch|buster)' 'end-of-life Debian box'
scan_code 'password[[:space:]]*=[[:space:]]*.*vagrant' 'hardcoded vagrant password'
scan_code 'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' 'embedded private key material'
scan_code 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?bash' 'pipe-to-shell download'
scan_code 'chmod[[:space:]]+777' 'world-writable permissions'

printf '\n== Repository structure checks ==\n'

tracked_secrets="$(git ls-files | grep -Ei '(^|/)(secrets/|.*\.pem$|.*deploy_?key|.*id_rsa|.*\.pkcs7)' || true)"
if [[ -n "$tracked_secrets" ]]; then
  fail "secret-like files are tracked by git: ${tracked_secrets//$'\n'/; }"
else
  pass 'no secret-like files tracked by git'
fi

loose_files="$(find . \
  \( -name .git -o -name .venv -o -name venv -o -name .vagrant -o -name vendor -o -name __pycache__ \) -prune -o \
  -type f \( -name '*.pem' -o -name '*deploy*key*' -o -name 'id_rsa*' \) -print 2>/dev/null || true)"
if [[ -n "$loose_files" ]]; then
  fail "secret-like files present in worktree: ${loose_files//$'\n'/; }"
else
  pass 'no secret-like files in worktree'
fi

for entry in '.vagrant/' 'secrets/' '*.pem' 'id_rsa'; do
  if grep -qF -- "$entry" .gitignore; then
    pass ".gitignore covers ${entry}"
  else
    fail ".gitignore is missing ${entry}"
  fi
done

if grep -qF 'YAML.safe_load' vagrant/Vagrantfile; then
  pass 'Vagrantfile uses YAML.safe_load'
else
  fail 'Vagrantfile does not use YAML.safe_load'
fi

if grep -qF 'box_version' vagrant/Vagrantfile; then
  pass 'Vagrantfile pins box_version'
else
  fail 'Vagrantfile does not pin box_version'
fi

if grep -qE '(^|[^0-9.])(10|172|192)\.[0-9]+\.[0-9]+\.[0-9]+' vagrant/Vagrantfile; then
  fail 'Vagrantfile contains a hardcoded private IPv4 address'
else
  pass 'Vagrantfile derives addresses from configuration'
fi

while IFS= read -r script; do
  if grep -qE 'set -[^[:space:]]*e' "$script" && grep -q 'pipefail' "$script"; then
    pass "${script} uses strict mode"
  else
    fail "${script} is missing 'set -euo pipefail'"
  fi
done < <(find vagrant/scripts scripts -maxdepth 3 -type f -name '*.sh' -print)

printf '\n'
if ((findings > 0)); then
  printf '%d security finding(s) detected.\n' "$findings" >&2
  exit 1
fi

printf 'Security audit passed: no insecure patterns detected.\n'
