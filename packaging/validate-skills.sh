#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: validate-skills.sh SKILLS_ROOT\n' >&2
    exit 2
fi

skills_root="$1"

die() {
    printf 'validate-skills.sh: %s\n' "$*" >&2
    exit 1
}

[[ -d "${skills_root}" && ! -L "${skills_root}" ]] ||
    die "skills root must be a real directory: ${skills_root}"

if invalid_path="$(find "${skills_root}" -mindepth 1 \
        \( -type l -o \( ! -type d ! -type f \) \) -print -quit)" && \
        [[ -n "${invalid_path}" ]]; then
    die "skills tree contains a symlink or special file: ${invalid_path}"
fi

if writable_path="$(find "${skills_root}" -mindepth 1 -perm /022 -print -quit)" && \
        [[ -n "${writable_path}" ]]; then
    die "skills tree contains a group/world-writable path: ${writable_path}"
fi

skill_count=0
while IFS= read -r -d '' skill_dir; do
    [[ -d "${skill_dir}" ]] ||
        die "skills root may contain only skill directories: ${skill_dir}"
    [[ -f "${skill_dir}/SKILL.md" && ! -L "${skill_dir}/SKILL.md" ]] ||
        die "skill is missing a regular SKILL.md: ${skill_dir}"
    ((skill_count += 1))
done < <(find "${skills_root}" -mindepth 1 -maxdepth 1 -print0)

((skill_count > 0)) || die "skills root is empty: ${skills_root}"
