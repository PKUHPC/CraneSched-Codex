#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_path="${script_dir}/codex.lock.json"
cache_dir="${CODEX_CACHE_DIR:-${repo_dir}/dist/cache}"

usage() {
    cat <<'EOF'
Usage: fetch-codex.sh [--lock PATH]

Download, verify, and extract the Codex artifact described by the Source Lock.
The path to the cached native executable is written to stdout.
EOF
}

die() {
    printf 'fetch-codex.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --lock)
            (($# >= 2)) || die "--lock requires a path"
            lock_path="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

for command_name in curl jq sha256sum tar; do
    command -v "${command_name}" >/dev/null || die "${command_name} is required"
done
[[ -f "${lock_path}" ]] || die "Source Lock not found: ${lock_path}"

jq -e '
    type == "object" and
    (.version | type == "string" and length > 0) and
    (.tag | type == "string" and length > 0) and
    (.commit | type == "string" and test("^[0-9a-f]{40}$")) and
    (.target | type == "string" and length > 0) and
    (.asset | type == "string" and test("^[A-Za-z0-9._-]+$")) and
    (.asset_url | type == "string" and length > 0) and
    (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.rpm_release | type == "number" and . >= 1 and floor == .)
' "${lock_path}" >/dev/null || die "invalid Source Lock: ${lock_path}"

version="$(jq -r .version "${lock_path}")"
target="$(jq -r .target "${lock_path}")"
asset="$(jq -r .asset "${lock_path}")"
asset_url="$(jq -r .asset_url "${lock_path}")"
asset_sha256="$(jq -r .sha256 "${lock_path}")"

case "$(uname -m)" in
    x86_64) host_target="x86_64-unknown-linux-musl" ;;
    *) die "unsupported build architecture: $(uname -m)" ;;
esac
[[ "${target}" == "${host_target}" ]] ||
    die "Source Lock target ${target} does not match host ${host_target}"

install -d -m 0755 -- "${cache_dir}"
asset_path="${cache_dir}/${asset}"
binary_path="${cache_dir}/codex-${version}-${target}-${asset_sha256:0:16}"

is_elf() {
    [[ -f "$1" ]] &&
        [[ "$(od -An -tx1 -N4 -- "$1" | tr -d '[:space:]')" == "7f454c46" ]]
}

asset_is_valid() {
    [[ -f "${asset_path}" ]] &&
        [[ "$(sha256sum "${asset_path}" | awk '{ print $1 }')" == "${asset_sha256}" ]]
}

temporary_download=""
temporary_binary=""
cleanup() {
    [[ -z "${temporary_download}" ]] || rm -f -- "${temporary_download}"
    [[ -z "${temporary_binary}" ]] || rm -f -- "${temporary_binary}"
}
trap cleanup EXIT

if ! asset_is_valid; then
    temporary_download="$(mktemp "${cache_dir}/.${asset}.download.XXXXXX")"
    curl --fail --location --retry 3 --silent --show-error \
        --output "${temporary_download}" "${asset_url}"
    [[ "$(sha256sum "${temporary_download}" | awk '{ print $1 }')" == \
        "${asset_sha256}" ]] || die "downloaded asset digest does not match Source Lock"
    mv -f -- "${temporary_download}" "${asset_path}"
    temporary_download=""
fi

members=()
while IFS= read -r member; do
    [[ -n "${member}" ]] || continue
    case "${member}" in
        /*|../*|*/../*) die "unsafe path in Codex archive: ${member}" ;;
    esac
    case "${member##*/}" in
        codex|"codex-${target}") members+=("${member}") ;;
    esac
done < <(tar -tzf "${asset_path}")
[[ "${#members[@]}" -eq 1 ]] ||
    die "expected one Codex executable in ${asset}, found ${#members[@]}"

temporary_binary="$(mktemp "${cache_dir}/.codex.extract.XXXXXX")"
tar -xOzf "${asset_path}" -- "${members[0]}" >"${temporary_binary}"
is_elf "${temporary_binary}" || die "extracted Codex executable is not an ELF binary"
chmod 0755 "${temporary_binary}"
mv -f -- "${temporary_binary}" "${binary_path}"
temporary_binary=""

printf '%s\n' "${binary_path}"
