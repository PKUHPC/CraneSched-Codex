#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
readonly source_lock="${repo_dir}/packaging/codex.lock.json"
readonly package_release="$(jq -r .rpm_release "${source_lock}")"
readonly codex_version="$(jq -r .version "${source_lock}")"
readonly source_commit="$(jq -r .commit "${source_lock}")"
readonly source_target="$(jq -r .target "${source_lock}")"
readonly source_asset_url="$(jq -r .asset_url "${source_lock}")"
readonly source_asset_sha256="$(jq -r .sha256 "${source_lock}")"
output_dir="${repo_dir}/dist"

usage() {
    cat <<'EOF'
Usage: build-rpm.sh [--output-dir PATH]

Build a cranesched-codex RPM containing the pinned native Codex binary.
EOF
}

die() {
    printf 'build-rpm.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --output-dir)
            (($# >= 2)) || die "--output-dir requires a path"
            output_dir="$2"
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

command -v rpmbuild >/dev/null || die "rpmbuild is required"
command -v rpm >/dev/null || die "rpm is required"
command -v jq >/dev/null || die "jq is required"
[[ "${package_release}" =~ ^[1-9][0-9]*$ ]] ||
    die "Source Lock rpm_release must be a positive integer"
"${repo_dir}/packaging/validate-skills.sh" "${repo_dir}/skills"

case "$(uname -m)" in
    x86_64) rpm_arch="x86_64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac
[[ "${source_target}" == "${rpm_arch}-unknown-linux-musl" ]] ||
    die "Source Lock target ${source_target} does not match ${rpm_arch}"
[[ "$(git -C "${repo_dir}/ref/codex" rev-parse HEAD)" == "${source_commit}" ]] ||
    die "Codex submodule does not match Source Lock commit ${source_commit}"

native_codex="$("${repo_dir}/packaging/fetch-codex.sh" --lock "${source_lock}")"
"${repo_dir}/tests/test-codex-compatibility.sh" "${native_codex}" >&2
binary_sha256="$(sha256sum "${native_codex}" | awk '{ print $1 }')"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-rpm.XXXXXX")"
cleanup() {
    rm -rf -- "${build_root}"
}
trap cleanup EXIT

for directory in BUILD BUILDROOT RPMS SOURCES SPECS SRPMS; do
    install -d -m 0755 -- "${build_root}/${directory}"
done

install -m 0755 -- "${native_codex}" "${build_root}/SOURCES/codex"
install -m 0644 -- "${repo_dir}/config.toml" "${build_root}/SOURCES/config.toml"
install -m 0644 -- \
    "${repo_dir}/proxy/cranesched-codex-proxy.service" \
    "${build_root}/SOURCES/cranesched-codex-proxy.service"
install -m 0755 -- \
    "${repo_dir}/proxy/cranesched-codex-proxy" \
    "${build_root}/SOURCES/cranesched-codex-proxy"
install -m 0755 -- \
    "${repo_dir}/proxy/extract_provider_credential.py" \
    "${build_root}/SOURCES/extract_provider_credential.py"
install -m 0755 -- \
    "${script_dir}/cranesched-codex-provision" \
    "${build_root}/SOURCES/cranesched-codex-provision"
install -m 0644 -- "${repo_dir}/ref/codex/LICENSE" "${build_root}/SOURCES/LICENSE"
install -m 0644 -- "${repo_dir}/ref/codex/NOTICE" "${build_root}/SOURCES/NOTICE"
install -m 0644 -- "${repo_dir}/README.md" "${build_root}/SOURCES/README.md"
cp -a -- "${repo_dir}/skills" "${build_root}/SOURCES/skills"
printf 'Codex-Version: %s\nCodex-Commit: %s\nArchitecture: %s\nAsset-URL: %s\nAsset-SHA256: %s\nBinary-SHA256: %s\n' \
    "${codex_version}" "${source_commit}" "${rpm_arch}" \
    "${source_asset_url}" "${source_asset_sha256}" "${binary_sha256}" \
    >"${build_root}/SOURCES/PROVENANCE"
install -m 0644 -- "${script_dir}/cranesched-codex.spec" \
    "${build_root}/SPECS/cranesched-codex.spec"

rpmbuild -bb \
    --target "${rpm_arch}" \
    --define "_topdir ${build_root}" \
    --define "codex_version ${codex_version}" \
    --define "package_release ${package_release}" \
    "${build_root}/SPECS/cranesched-codex.spec" >&2

built_rpm="$(find "${build_root}/RPMS/${rpm_arch}" -maxdepth 1 -type f \
    -name "cranesched-codex-${codex_version}-${package_release}*.${rpm_arch}.rpm" \
    -print -quit)"
[[ -n "${built_rpm}" ]] || die "rpmbuild did not produce the expected package"
install -d -m 0755 -- "${output_dir}"
output_rpm="${output_dir}/$(basename -- "${built_rpm}")"
install -m 0644 -- "${built_rpm}" "${output_rpm}"
rpm -K --nosignature "${output_rpm}" >&2
printf '%s\n' "${output_rpm}"
