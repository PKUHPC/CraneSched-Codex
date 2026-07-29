#!/usr/bin/env bash
set -euo pipefail

die() {
    printf 'compatibility-scope.sh: %s\n' "$*" >&2
    exit 2
}

if (($# > 0)) && [[ "$1" == "--git-diff" ]]; then
    (($# == 3)) || die "--git-diff requires BASE_SHA and HEAD_SHA"
    command -v git >/dev/null || die "git is required for --git-diff"
    diff_file="$(mktemp "${TMPDIR:-/tmp}/compatibility-diff.XXXXXX")"
    cleanup() {
        rm -f -- "${diff_file}"
    }
    trap cleanup EXIT
    git diff --name-only --no-renames -z "$2...$3" >"${diff_file}"
    mapfile -d '' changed_paths <"${diff_file}"
    set -- "${changed_paths[@]}"
fi

# Empty and unrecognized diffs fail safe by requiring the full EL9 suite.
if (($# == 0)); then
    printf 'true\n'
    exit 0
fi

for changed_path in "$@"; do
    case "${changed_path}" in
        AGENTS.md|CLAUDE.md|CONTEXT.md|docs/*|.github/pull_request_template.md)
            ;;
        *)
            printf 'true\n'
            exit 0
            ;;
    esac
done

printf 'false\n'
