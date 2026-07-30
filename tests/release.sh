#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_dir}"

rpm_path="$(./cranesched-codex.sh build)"
packaging/rpm/tests/test-rpm.sh "${rpm_path}"
packaging/rpm/tests/test-dnf-transaction.sh "${rpm_path}"

printf 'CraneSched-Codex release artifact contract passed.\n'
