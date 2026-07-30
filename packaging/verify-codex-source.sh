#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
lock_path="${script_dir}/codex.lock.json"
codex_repo="${repo_dir}/submodules/codex"

usage() {
    cat <<'EOF'
Usage: verify-codex-source.sh [OPTIONS]

Options:
  --lock PATH        Verify an alternate Source Lock (primarily for tests)
  --codex-repo PATH  Verify an alternate Codex checkout (primarily for tests)
  -h, --help         Show this help
EOF
}

die() {
    printf 'verify-codex-source.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
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

for command_name in git jq; do
    command -v "${command_name}" >/dev/null || die "${command_name} is required"
done
[[ -f "${lock_path}" ]] || die "Source Lock not found: ${lock_path}"

source_commit="$(jq -er '
    .commit |
    select(type == "string" and test("^[0-9a-f]{40}$"))
' "${lock_path}")" || die "Source Lock has an invalid commit: ${lock_path}"
codex_commit="$(git -C "${codex_repo}" rev-parse HEAD 2>/dev/null)" ||
    die "Codex submodule is unavailable: ${codex_repo}"
[[ "${codex_commit}" == "${source_commit}" ]] ||
    die "Codex submodule ${codex_commit} does not match Source Lock commit ${source_commit}"

codex_binary="$("${script_dir}/fetch-codex.sh" --lock "${lock_path}")"
[[ -x "${codex_binary}" ]] || die "verified Codex artifact is not executable"

printf 'Codex Source Lock, submodule, and artifact verified.\n'
