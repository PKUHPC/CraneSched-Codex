#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: test-dnf-transaction.sh RPM_PATH\n' >&2
    exit 2
fi

[[ "${EUID}" -eq 0 ]] || {
    printf 'test-dnf-transaction.sh must run as root.\n' >&2
    exit 1
}
rpm_path="$(readlink -f -- "$1")"
[[ -f "${rpm_path}" ]] || {
    printf 'RPM not found: %s\n' "${rpm_path}" >&2
    exit 1
}
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
codex_version="$(jq -r .version "${repo_dir}/packaging/codex.lock.json")"
if rpm -q cranesched-codex >/dev/null 2>&1; then
    printf 'test-dnf-transaction.sh requires cranesched-codex to be absent.\n' >&2
    exit 1
fi

cleanup_package() {
    if rpm -q cranesched-codex >/dev/null 2>&1; then
        dnf --assumeyes remove cranesched-codex >/dev/null
    fi
}
trap cleanup_package EXIT

dnf --assumeyes install "${rpm_path}"
rpm -q cranesched-codex >/dev/null
[[ "$(/usr/bin/codex --version)" == "codex-cli ${codex_version}" ]]
[[ -f /etc/codex/config.toml ]]
[[ -f /etc/codex/skills/cranesched-skill/SKILL.md ]]
[[ ! -e /etc/codex/proxy-api-key ]]
dnf --assumeyes remove cranesched-codex
! rpm -q cranesched-codex >/dev/null 2>&1
[[ ! -e /usr/bin/codex ]]
[[ ! -e /etc/codex/skills ]]
trap - EXIT

printf 'CraneSched-Codex DNF transaction test passed.\n'
