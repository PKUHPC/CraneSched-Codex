#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
    cranesched-codex.sh
    packaging/rpm/cranesched-codex.spec
    packaging/rpm/cranesched-codex-provision
    proxy/cranesched-codex-proxy
    proxy/cranesched-codex-proxy.service
)
for relative_path in "${required_files[@]}"; do
    [[ -f "${repo_dir}/${relative_path}" ]] || {
        printf 'Missing canonical project file: %s\n' "${relative_path}" >&2
        exit 1
    }
done

legacy_paths=(
    managed-codex.sh
    packaging/rpm/managed-codex.spec
    packaging/rpm/managed-codex-provision
    proxy/codex-managed-proxy
    proxy/codex-responses-api-proxy.service
)
for relative_path in "${legacy_paths[@]}"; do
    [[ ! -e "${repo_dir}/${relative_path}" ]] || {
        printf 'Legacy project path remains: %s\n' "${relative_path}" >&2
        exit 1
    }
done
[[ ! -e "${repo_dir}/proxy/install.sh" ]]
[[ ! -e "${repo_dir}/proxy/resolve-native-codex" ]]

rg -Fq 'readonly package_name="cranesched-codex"' \
    "${repo_dir}/cranesched-codex.sh"
rg -Fq 'Name:           cranesched-codex' \
    "${repo_dir}/packaging/rpm/cranesched-codex.spec"
rg -Fq '/usr/libexec/cranesched-codex/' \
    "${repo_dir}/packaging/rpm/cranesched-codex.spec"
rg -Fq 'cranesched-codex-proxy.service' \
    "${repo_dir}/packaging/rpm/cranesched-codex.spec"

[[ -f "${repo_dir}/.gitmodules" ]] || {
    printf 'Missing .gitmodules\n' >&2
    exit 1
}
[[ "$(git config -f "${repo_dir}/.gitmodules" --get submodule.ref/codex.url)" == \
    "https://github.com/openai/codex.git" ]]
[[ "$(git config -f "${repo_dir}/.gitmodules" --get submodule.ref/CraneSched.url)" == \
    "https://github.com/PKUHPC/CraneSched.git" ]]

lock_path="${repo_dir}/packaging/codex.lock.json"
jq -e '
    .version == "0.145.0" and
    .tag == "rust-v0.145.0" and
    .commit == "25af12f7e61572b0bc18ddb1008be543b91519b0" and
    .target == "x86_64-unknown-linux-musl" and
    .asset == "codex-x86_64-unknown-linux-musl.tar.gz" and
    .asset_url == "https://github.com/openai/codex/releases/download/rust-v0.145.0/codex-x86_64-unknown-linux-musl.tar.gz" and
    .sha256 == "bfaf13c9ba34f2ad764e4a916c49cf7177aeba329cf0f719e2227566fc8d662a" and
    .rpm_release == 1 and
    (has("prerelease") | not)
' "${lock_path}" >/dev/null

[[ "$(git -C "${repo_dir}/ref/codex" rev-parse HEAD)" == \
    "$(jq -r .commit "${lock_path}")" ]]
git -C "${repo_dir}/ref/CraneSched" rev-parse --verify HEAD^{commit} >/dev/null
[[ ! -e "${repo_dir}/packaging/CODEX_VERSION" ]]

printf 'Repository identity contract passed.\n'
