#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_dir}"

tests/test-compatibility-scope.sh
packaging/tests/test-fetch-codex.sh
packaging/tests/test-verify-codex-source.sh
packaging/tests/test-update-codex-lock.sh

codex_bin="$(packaging/fetch-codex.sh)"
tests/test-codex-compatibility.sh "${codex_bin}"
CODEX_BIN="${codex_bin}" \
SYSTEM_CONFIG_RUNTIME_TEST="${SYSTEM_CONFIG_RUNTIME_TEST:-0}" \
    proxy/tests/test.sh

rpm_path="$(./cranesched-codex.sh build)"
packaging/rpm/tests/test-rpm.sh "${rpm_path}"

if [[ "${DNF_TRANSACTION_TEST:-0}" == "1" ]]; then
    packaging/rpm/tests/test-dnf-transaction.sh "${rpm_path}"
fi

printf 'CraneSched-Codex CI contract passed.\n'
