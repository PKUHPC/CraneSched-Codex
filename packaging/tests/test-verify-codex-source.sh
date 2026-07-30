#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-source-test.XXXXXX")"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT

git init --quiet "${test_dir}/codex"
git -C "${test_dir}/codex" config user.name "Codex Source Test"
git -C "${test_dir}/codex" config user.email "codex-source-test@example.invalid"
printf 'fixture\n' >"${test_dir}/codex/source.txt"
git -C "${test_dir}/codex" add source.txt
git -C "${test_dir}/codex" commit --quiet -m fixture
source_commit="$(git -C "${test_dir}/codex" rev-parse HEAD)"

install -d -m 0755 -- "${test_dir}/asset"
fixture_elf="$(readlink -f -- "$(command -v bash)")"
install -m 0755 -- "${fixture_elf}" \
    "${test_dir}/asset/codex-x86_64-unknown-linux-musl"
tar -C "${test_dir}/asset" -czf "${test_dir}/codex.tar.gz" \
    codex-x86_64-unknown-linux-musl
asset_sha256="$(sha256sum "${test_dir}/codex.tar.gz" | awk '{ print $1 }')"

jq -n \
    --arg commit "${source_commit}" \
    --arg asset_url "file://${test_dir}/codex.tar.gz" \
    --arg sha256 "${asset_sha256}" \
    '{
        version: "test",
        tag: "rust-vtest",
        commit: $commit,
        target: "x86_64-unknown-linux-musl",
        asset: "codex-x86_64-unknown-linux-musl.tar.gz",
        asset_url: $asset_url,
        sha256: $sha256,
        rpm_release: 1
    }' >"${test_dir}/codex.lock.json"

CODEX_CACHE_DIR="${test_dir}/cache" \
    "${repo_dir}/packaging/verify-codex-source.sh" \
    --lock "${test_dir}/codex.lock.json" \
    --codex-repo "${test_dir}/codex"

jq '.commit = "0000000000000000000000000000000000000000"' \
    "${test_dir}/codex.lock.json" >"${test_dir}/mismatched.lock.json"
if CODEX_CACHE_DIR="${test_dir}/cache" \
    "${repo_dir}/packaging/verify-codex-source.sh" \
    --lock "${test_dir}/mismatched.lock.json" \
    --codex-repo "${test_dir}/codex" 2>"${test_dir}/mismatch.stderr"; then
    printf 'mismatched Source Lock and submodule unexpectedly passed\n' >&2
    exit 1
fi
rg -Fq 'does not match Source Lock commit' "${test_dir}/mismatch.stderr"

printf 'Codex source verification contract passed.\n'
