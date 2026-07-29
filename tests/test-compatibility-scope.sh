#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scope_script="${repo_dir}/.github/scripts/compatibility-scope.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/compatibility-scope-test.XXXXXX")"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT

assert_scope() {
    local expected="$1"
    shift
    local actual
    actual="$("${scope_script}" "$@")"
    [[ "${actual}" == "${expected}" ]] || {
        printf 'Expected compatibility scope %s, got %s for: %s\n' \
            "${expected}" "${actual}" "$*" >&2
        exit 1
    }
}

assert_scope true
assert_scope false \
    AGENTS.md CLAUDE.md CONTEXT.md \
    docs/agents/development-workflow.md \
    'docs/design notes.md' \
    .github/pull_request_template.md
assert_scope true README.md
assert_scope true docs/agents/domain.md proxy/cranesched-codex-proxy
assert_scope true submodules/codex
assert_scope true .github/workflows/compatibility.yml

git -C "${test_dir}" init --quiet
git -C "${test_dir}" config user.name "Compatibility Scope Test"
git -C "${test_dir}" config user.email "compatibility-scope@example.invalid"
install -d -m 0755 -- "${test_dir}/proxy"
printf '#!/bin/sh\n' >"${test_dir}/proxy/runtime-helper.sh"
git -C "${test_dir}" add proxy/runtime-helper.sh
git -C "${test_dir}" commit --quiet -m "test: add runtime helper"
base_sha="$(git -C "${test_dir}" rev-parse HEAD)"
install -d -m 0755 -- "${test_dir}/docs"
git -C "${test_dir}" mv proxy/runtime-helper.sh docs/runtime-helper.sh
git -C "${test_dir}" commit --quiet -m "docs: move runtime helper"
head_sha="$(git -C "${test_dir}" rev-parse HEAD)"
rename_scope="$(
    cd -- "${test_dir}"
    "${scope_script}" --git-diff "${base_sha}" "${head_sha}"
)"
[[ "${rename_scope}" == true ]] || {
    printf 'A code-to-doc rename must run compatibility checks.\n' >&2
    exit 1
}

git -C "${test_dir}" switch --quiet --detach "${base_sha}"
git -C "${test_dir}" switch --quiet -c docs-only
install -d -m 0755 -- "${test_dir}/docs"
printf 'Documentation update.\n' >"${test_dir}/docs/guide.md"
git -C "${test_dir}" add docs/guide.md
git -C "${test_dir}" commit --quiet -m "docs: update guide"
docs_head_sha="$(git -C "${test_dir}" rev-parse HEAD)"
git -C "${test_dir}" switch --quiet --detach "${base_sha}"
printf '#!/bin/sh\nexit 0\n' >"${test_dir}/proxy/base-only-change.sh"
git -C "${test_dir}" add proxy/base-only-change.sh
git -C "${test_dir}" commit --quiet -m "fix: update base runtime"
advanced_base_sha="$(git -C "${test_dir}" rev-parse HEAD)"
behind_scope="$(
    cd -- "${test_dir}"
    "${scope_script}" --git-diff "${advanced_base_sha}" "${docs_head_sha}"
)"
[[ "${behind_scope}" == false ]] || {
    printf 'A docs-only change must stay on the fast path when its branch is behind.\n' >&2
    exit 1
}

printf 'Compatibility scope tests passed.\n'
