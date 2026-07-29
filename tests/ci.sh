#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_dir}"

packaging/tests/test-fetch-codex.sh
packaging/tests/test-update-codex-lock.sh

codex_bin="$(packaging/fetch-codex.sh)"
CODEX_BIN="${codex_bin}" \
SYSTEM_CONFIG_RUNTIME_TEST="${SYSTEM_CONFIG_RUNTIME_TEST:-0}" \
    proxy/tests/test.sh

rpm_path="$(./cranesched-codex.sh build)"
packaging/rpm/tests/test-rpm.sh "${rpm_path}"

if [[ "${DNF_TRANSACTION_TEST:-0}" == "1" ]]; then
    [[ "${EUID}" -eq 0 ]] || {
        printf 'DNF_TRANSACTION_TEST=1 requires root\n' >&2
        exit 1
    }
    cleanup_package() {
        if rpm -q cranesched-codex >/dev/null 2>&1; then
            dnf --assumeyes remove cranesched-codex >/dev/null
        fi
    }
    trap cleanup_package EXIT
    dnf --assumeyes install "${rpm_path}"
    rpm -q cranesched-codex >/dev/null
    [[ "$(/usr/bin/codex --version)" == \
        "codex-cli $(jq -r .version packaging/codex.lock.json)" ]]
    [[ -f /etc/codex/config.toml ]]
    [[ -f /etc/codex/skills/cranesched-skill/SKILL.md ]]
    [[ ! -e /etc/codex/proxy-api-key ]]
    dnf --assumeyes remove cranesched-codex
    ! rpm -q cranesched-codex >/dev/null 2>&1
    [[ ! -e /usr/bin/codex ]]
    [[ ! -e /etc/codex/skills ]]
    trap - EXIT
fi

printf 'CraneSched-Codex CI contract passed.\n'
