#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_path="${script_dir}/codex.lock.json"
codex_repo="${repo_dir}/ref/codex"
prerelease=false

usage() {
    cat <<'EOF'
Usage: update-codex-lock.sh VERSION RPM_RELEASE [OPTIONS]

Options:
  --prerelease       Mark the resulting GitHub Release as a prerelease
  --lock PATH        Write an alternate Source Lock (primarily for tests)
  --codex-repo PATH  Use an alternate Codex checkout (primarily for tests)
  -h, --help         Show this help
EOF
}

die() {
    printf 'update-codex-lock.sh: %s\n' "$*" >&2
    exit 1
}

(($# >= 2)) || {
    usage >&2
    exit 2
}
version="$1"
rpm_release="$2"
shift 2

while (($# > 0)); do
    case "$1" in
        --prerelease)
            prerelease=true
            shift
            ;;
        --lock)
            (($# >= 2)) || die "--lock requires a path"
            lock_path="$2"
            shift 2
            ;;
        --codex-repo)
            (($# >= 2)) || die "--codex-repo requires a path"
            codex_repo="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "VERSION must be a stable Codex version such as 0.146.0"
[[ "${rpm_release}" =~ ^[1-9][0-9]*$ ]] ||
    die "RPM_RELEASE must be a positive integer"
command -v git >/dev/null || die "git is required"
command -v jq >/dev/null || die "jq is required"
[[ -d "${codex_repo}/.git" || -f "${codex_repo}/.git" ]] ||
    die "Codex submodule is unavailable: ${codex_repo}"

tag="rust-v${version}"
if ! git -C "${codex_repo}" rev-parse --verify --quiet "refs/tags/${tag}^{commit}" \
    >/dev/null; then
    git -C "${codex_repo}" fetch --no-tags origin \
        "refs/tags/${tag}:refs/tags/${tag}"
fi
commit="$(git -C "${codex_repo}" rev-list -n 1 "${tag}")"
[[ "${commit}" =~ ^[0-9a-f]{40}$ ]] || die "could not resolve ${tag} to a commit"

metadata_path="${CODEX_RELEASE_METADATA:-}"
metadata_temp=""
cleanup() {
    [[ -z "${metadata_temp}" ]] || rm -f -- "${metadata_temp}"
}
trap cleanup EXIT

if [[ -z "${metadata_path}" ]]; then
    command -v gh >/dev/null || die "gh is required to query Codex releases"
    metadata_temp="$(mktemp "${TMPDIR:-/tmp}/codex-release.XXXXXX.json")"
    gh api "repos/openai/codex/releases/tags/${tag}" >"${metadata_temp}"
    metadata_path="${metadata_temp}"
fi
[[ -f "${metadata_path}" ]] || die "release metadata not found: ${metadata_path}"
[[ "$(jq -r .tag_name "${metadata_path}")" == "${tag}" ]] ||
    die "release metadata does not describe ${tag}"

target="x86_64-unknown-linux-musl"
asset="codex-${target}.tar.gz"
asset_url="$(jq -er --arg asset "${asset}" \
    '.assets[] | select(.name == $asset) | .browser_download_url' \
    "${metadata_path}")" || die "release ${tag} has no ${asset}"
asset_digest="$(jq -er --arg asset "${asset}" \
    '.assets[] | select(.name == $asset) | .digest' \
    "${metadata_path}")" || die "release ${tag} has no digest for ${asset}"
[[ "${asset_digest}" =~ ^sha256:([0-9a-f]{64})$ ]] ||
    die "release ${tag} has an invalid SHA-256 digest for ${asset}"
asset_sha256="${BASH_REMATCH[1]}"

git -C "${codex_repo}" checkout --detach "${commit}" >/dev/null

lock_dir="$(dirname -- "${lock_path}")"
[[ -d "${lock_dir}" ]] || die "Source Lock directory does not exist: ${lock_dir}"
lock_temp="$(mktemp "${lock_dir}/.codex.lock.XXXXXX")"
jq -n \
    --arg version "${version}" \
    --arg tag "${tag}" \
    --arg commit "${commit}" \
    --arg target "${target}" \
    --arg asset "${asset}" \
    --arg asset_url "${asset_url}" \
    --arg sha256 "${asset_sha256}" \
    --argjson rpm_release "${rpm_release}" \
    --argjson prerelease "${prerelease}" \
    '{
        version: $version,
        tag: $tag,
        commit: $commit,
        target: $target,
        asset: $asset,
        asset_url: $asset_url,
        sha256: $sha256,
        rpm_release: $rpm_release,
        prerelease: $prerelease
    }' >"${lock_temp}"
mv -f -- "${lock_temp}" "${lock_path}"

printf 'Updated Codex Source Lock to %s (%s).\n' "${version}" "${commit}"
