#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: test-rpm.sh RPM_PATH\n' >&2
    exit 2
fi

rpm_path="$(readlink -f -- "$1")"
[[ -f "${rpm_path}" ]] || { printf 'RPM not found: %s\n' "${rpm_path}" >&2; exit 1; }
[[ "${EUID}" -eq 0 ]] || {
    printf 'test-rpm.sh must run as root for isolated RPM transactions.\n' >&2
    exit 1
}
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
source_lock="${repo_dir}/packaging/codex.lock.json"
skills_source="${repo_dir}/submodules/CraneSched/docs/skills"
codex_version="$(jq -r .version "${source_lock}")"
package_release="$(jq -r .rpm_release "${source_lock}")"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-rpm-test.XXXXXX")"
cleanup() {
    rm -rf -- "${test_root}"
}
trap cleanup EXIT

"${repo_dir}/packaging/validate-skills.sh" "${skills_source}"

[[ "$(rpm -qp --queryformat '%{NAME}' "${rpm_path}")" == "cranesched-codex" ]]
[[ "$(rpm -qp --queryformat '%{VERSION}' "${rpm_path}")" == "${codex_version}" ]]
[[ "$(rpm -qp --queryformat '%{RELEASE}' "${rpm_path}")" == \
    "${package_release}.el9" ]]
[[ "$(rpm -qp --queryformat '%{ARCH}' "${rpm_path}")" == "x86_64" ]]
rpm -K --nosignature "${rpm_path}" >/dev/null
package_requires="$(rpm -qp --requires "${rpm_path}")"
for dependency in bubblewrap ripgrep; do
    rg -Fxq -- "${dependency}" <<<"${package_requires}"
done
! rg -Fxq -- "python3-tomli" <<<"${package_requires}"
! rg -Fxq -- "bash" <<<"${package_requires}"

required_paths=(
    /etc/codex/config.toml
    /etc/codex/proxy-upstream.conf
    /etc/codex/skills/cranesched-skill/SKILL.md
    /usr/bin/codex
    /usr/lib/systemd/system/cranesched-codex-proxy.service
    /usr/libexec/cranesched-codex/codex
    /usr/libexec/cranesched-codex/cranesched-codex-proxy
    /usr/share/doc/cranesched-codex/PROVENANCE
    /usr/share/doc/cranesched-codex/installation-and-configuration.md
    /usr/share/doc/cranesched-codex/architecture-and-security.md
    /usr/share/licenses/cranesched-codex/CODEX-LICENSE
    /usr/share/licenses/cranesched-codex/CODEX-NOTICE
)
package_files="$(rpm -qlp "${rpm_path}")"
for path in "${required_paths[@]}"; do
    rg -Fxq -- "${path}" <<<"${package_files}"
done
while IFS= read -r -d '' source_path; do
    relative_path="${source_path#"${skills_source}/"}"
    rg -Fxq -- "/etc/codex/skills/${relative_path}" <<<"${package_files}"
done < <(find "${skills_source}" -mindepth 1 -type f -print0)
[[ "$(rpm -qp --queryformat \
    '[%{FILENAMES}\t%{FILEFLAGS:fflags}\n]' "${rpm_path}" | \
    awk -F '\t' '$1 == "/etc/codex/proxy-upstream.conf" { print $2 }')" == *g* ]]

payload_paths="$(rpm2cpio "${rpm_path}" | cpio -it --quiet)"
! rg -q 'proxy-upstream\.conf|cranesched-codex-provision|extract_provider_credential' \
    <<<"${payload_paths}"

extract_root="${test_root}/extract"
install -d -m 0755 -- "${extract_root}"
(
    cd -- "${extract_root}"
    rpm2cpio "${rpm_path}" | cpio -idm --quiet
)
[[ "$(stat -c '%a' "${extract_root}/etc/codex/config.toml")" == "644" ]]
[[ "$(stat -c '%a' "${extract_root}/usr/libexec/cranesched-codex/codex")" == "755" ]]
[[ "$(readlink "${extract_root}/usr/bin/codex")" == "../libexec/cranesched-codex/codex" ]]
[[ "$("${extract_root}/usr/bin/codex" --version)" == "codex-cli ${codex_version}" ]]
diff --recursive --no-dereference --brief \
    "${skills_source}" "${extract_root}/etc/codex/skills"
diff --brief --no-dereference \
    "${repo_dir}/docs/installation-and-configuration.md" \
    "${extract_root}/usr/share/doc/cranesched-codex/installation-and-configuration.md"
diff --brief --no-dereference \
    "${repo_dir}/docs/architecture-and-security.md" \
    "${extract_root}/usr/share/doc/cranesched-codex/architecture-and-security.md"
packaged_readme="${extract_root}/usr/share/doc/cranesched-codex/README.md"
for documented_page in \
    installation-and-configuration.md \
    architecture-and-security.md; do
    rg -Fq \
        "https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/${documented_page}" \
        "${packaged_readme}"
done
! rg -q '\]\(docs/' "${packaged_readme}"
systemd-analyze --recursive-errors=no --root="${extract_root}" \
    verify cranesched-codex-proxy.service

provenance_sha="$(awk '/^Binary-SHA256:/ { print $2 }' \
    "${extract_root}/usr/share/doc/cranesched-codex/PROVENANCE")"
[[ "${provenance_sha}" == \
    "$(sha256sum "${extract_root}/usr/libexec/cranesched-codex/codex" | awk '{ print $1 }')" ]]
[[ "$(awk '/^Asset-SHA256:/ { print $2 }' \
    "${extract_root}/usr/share/doc/cranesched-codex/PROVENANCE")" == \
    "$(jq -r .sha256 "${source_lock}")" ]]

install_root="${test_root}/install-root"
install -d -m 0755 -- "${install_root}/var/lib/rpm"
if [[ "$(getenforce 2>/dev/null || true)" == "Enforcing" ]] &&
    chcon -t rpm_var_lib_t -- "${test_root}" 2>/dev/null; then
    chcon -R -t rpm_var_lib_t -- "${install_root}"
fi
rpm --root "${install_root}" --initdb
rpm --root "${install_root}" -ivh --nodeps --noscripts "${rpm_path}" >/dev/null
diff --recursive --no-dereference --brief \
    "${skills_source}" "${install_root}/etc/codex/skills"
printf '%s\n%s\n' \
    'https://gateway.example.invalid/v1/responses' 'fixture-secret' \
    >"${install_root}/etc/codex/proxy-upstream.conf"
chmod 0600 "${install_root}/etc/codex/proxy-upstream.conf"
rpm --root "${install_root}" -e --nodeps --noscripts cranesched-codex
[[ ! -e "${install_root}/etc/codex/proxy-upstream.conf" ]]
[[ ! -e "${install_root}/etc/codex/skills" ]]
[[ ! -e "${install_root}/usr/bin/codex" ]]
[[ ! -e "${install_root}/usr/libexec/cranesched-codex/codex" ]]

printf 'CraneSched-Codex RPM tests passed.\n'
