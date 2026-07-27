#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-lock-test.XXXXXX")"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT

git clone --quiet --shared --no-checkout \
    "${repo_dir}/ref/codex" "${test_dir}/codex"

jq -n '{
    tag_name: "rust-v0.145.0",
    assets: [
        {
            name: "codex-x86_64-unknown-linux-musl.tar.gz",
            browser_download_url: "https://github.com/openai/codex/releases/download/rust-v0.145.0/codex-x86_64-unknown-linux-musl.tar.gz",
            digest: "sha256:bfaf13c9ba34f2ad764e4a916c49cf7177aeba329cf0f719e2227566fc8d662a"
        }
    ]
}' >"${test_dir}/release.json"

CODEX_RELEASE_METADATA="${test_dir}/release.json" \
    "${repo_dir}/packaging/update-codex-lock.sh" \
    0.145.0 7 --prerelease \
    --lock "${test_dir}/codex.lock.json" \
    --codex-repo "${test_dir}/codex"

jq -e '
    .version == "0.145.0" and
    .tag == "rust-v0.145.0" and
    .commit == "25af12f7e61572b0bc18ddb1008be543b91519b0" and
    .target == "x86_64-unknown-linux-musl" and
    .asset == "codex-x86_64-unknown-linux-musl.tar.gz" and
    .sha256 == "bfaf13c9ba34f2ad764e4a916c49cf7177aeba329cf0f719e2227566fc8d662a" and
    .rpm_release == 7 and
    .prerelease == true
' "${test_dir}/codex.lock.json" >/dev/null

printf 'Codex Source Lock update contract passed.\n'
