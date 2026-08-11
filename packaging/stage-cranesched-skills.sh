#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: stage-cranesched-skills.sh DESTINATION\n' >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
submodule_dir="${repo_dir}/submodules/CraneSched"
skills_source="${submodule_dir}/docs/skills"
destination="$1"
destination_parent="$(dirname -- "${destination}")"
staging_dir=""

die() {
    printf 'stage-cranesched-skills.sh: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    [[ -z "${staging_dir}" ]] || rm -rf -- "${staging_dir}"
}
trap cleanup EXIT

command -v git >/dev/null || die "git is required"

expected_commit="$(git -C "${repo_dir}" rev-parse 'HEAD:submodules/CraneSched')" ||
    die "the parent commit does not contain a CraneSched submodule gitlink"

if [[ ! -e "${submodule_dir}/.git" ]]; then
    git -C "${repo_dir}" submodule update --init --checkout -- \
        submodules/CraneSched >&2
fi

actual_commit="$(git -C "${submodule_dir}" rev-parse HEAD)" ||
    die "could not read the CraneSched submodule commit"
[[ "${actual_commit}" == "${expected_commit}" ]] ||
    die "CraneSched submodule ${actual_commit} does not match parent gitlink ${expected_commit}"
[[ -z "$(git -C "${submodule_dir}" status --porcelain)" ]] ||
    die "CraneSched submodule has uncommitted changes"
[[ -d "${skills_source}" && ! -L "${skills_source}" ]] ||
    die "CraneSched docs/skills is unavailable: ${skills_source}"

"${repo_dir}/packaging/validate-skills.sh" "${skills_source}"

[[ ! -e "${destination}" && ! -L "${destination}" ]] ||
    die "destination already exists: ${destination}"
[[ -d "${destination_parent}" ]] ||
    install -d -m 0755 -- "${destination_parent}"
staging_dir="$(mktemp -d -- "${destination}.tmp.XXXXXX")"
cp -a -- "${skills_source}/." "${staging_dir}/"
chmod 0755 -- "${staging_dir}"
mv -- "${staging_dir}" "${destination}"
staging_dir=""

printf 'Staged CraneSched Skills from %s at %s.\n' \
    "${actual_commit}" "${destination}" >&2
