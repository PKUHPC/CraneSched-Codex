#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-fetch-test.XXXXXX")"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT

install -d -m 0755 -- "${test_dir}/asset"
fixture_elf="$(readlink -f -- "$(command -v bash)")"
install -m 0755 -- "${fixture_elf}" \
    "${test_dir}/asset/codex-x86_64-unknown-linux-musl"
tar -C "${test_dir}/asset" -czf "${test_dir}/codex.tar.gz" \
    codex-x86_64-unknown-linux-musl
asset_sha256="$(sha256sum "${test_dir}/codex.tar.gz" | awk '{ print $1 }')"

jq -n \
    --arg asset_url "file://${test_dir}/codex.tar.gz" \
    --arg sha256 "${asset_sha256}" \
    '{
        version: "test",
        tag: "rust-vtest",
        commit: "0000000000000000000000000000000000000000",
        target: "x86_64-unknown-linux-musl",
        asset: "codex-x86_64-unknown-linux-musl.tar.gz",
        asset_url: $asset_url,
        sha256: $sha256,
        rpm_release: 1
    }' >"${test_dir}/codex.lock.json"

codex_path="$(CODEX_CACHE_DIR="${test_dir}/cache" \
    "${repo_dir}/packaging/fetch-codex.sh" \
    --lock "${test_dir}/codex.lock.json")"
[[ -x "${codex_path}" ]]
cmp --silent "${fixture_elf}" "${codex_path}"

# A corrupt cached archive must be replaced and verified before extraction.
printf 'corrupt cache\n' >"${test_dir}/cache/codex-x86_64-unknown-linux-musl.tar.gz"
refetched_path="$(CODEX_CACHE_DIR="${test_dir}/cache" \
    "${repo_dir}/packaging/fetch-codex.sh" \
    --lock "${test_dir}/codex.lock.json")"
[[ "${refetched_path}" == "${codex_path}" ]]
[[ "$(sha256sum "${test_dir}/cache/codex-x86_64-unknown-linux-musl.tar.gz" | \
    awk '{ print $1 }')" == "${asset_sha256}" ]]

# A valid cache must work after its source URL disappears.
rm -f -- "${test_dir}/codex.tar.gz"
cached_path="$(CODEX_CACHE_DIR="${test_dir}/cache" \
    "${repo_dir}/packaging/fetch-codex.sh" \
    --lock "${test_dir}/codex.lock.json")"
[[ "${cached_path}" == "${codex_path}" ]]

printf 'Codex source fetch contract passed.\n'
