#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly package_name="cranesched-codex"

usage() {
    cat <<'EOF'
Usage:
  ./cranesched-codex.sh build
  sudo ./cranesched-codex.sh install [--source-config PATH] [--rpm PATH]
                                  [--skip-upstream-check]
  sudo ./cranesched-codex.sh uninstall --yes
  ./cranesched-codex.sh status

Commands:
  build      Build an RPM with the pinned Codex binary and runtime dependencies.
  install    Install an RPM with DNF, provision the Key, start and verify service.
  uninstall  Remove the package with DNF, including the RPM-owned Key.
  status     Show package and systemd status.
EOF
}

die() {
    printf 'cranesched-codex.sh: %s\n' "$*" >&2
    exit 1
}

(($# > 0)) || {
    usage
    exit 2
}
command_name="$1"
shift

case "${command_name}" in
    build)
        exec "${script_dir}/packaging/rpm/build-rpm.sh" "$@"
        ;;
    install)
        [[ "${EUID}" -eq 0 ]] || die "install must run as root"
        command -v dnf >/dev/null || die "dnf is required for installation"
        source_config="/root/.codex/config.toml"
        rpm_path=""
        verify_upstream=1
        while (($# > 0)); do
            case "$1" in
                --source-config)
                    (($# >= 2)) || die "--source-config requires a path"
                    source_config="$2"
                    shift 2
                    ;;
                --rpm)
                    (($# >= 2)) || die "--rpm requires a path"
                    rpm_path="$2"
                    shift 2
                    ;;
                --skip-upstream-check)
                    verify_upstream=0
                    shift
                    ;;
                *) die "unknown install argument: $1" ;;
            esac
        done
        [[ -f "${source_config}" ]] || die "source config not found: ${source_config}"
        if [[ -z "${rpm_path}" ]]; then
            rpm_path="$("${script_dir}/packaging/rpm/build-rpm.sh")"
        fi
        [[ -f "${rpm_path}" ]] || die "RPM not found: ${rpm_path}"
        rpm_path="$(readlink -f -- "${rpm_path}")"
        [[ "$(rpm -qp --queryformat '%{NAME}' "${rpm_path}")" == "${package_name}" ]] ||
            die "not a ${package_name} RPM: ${rpm_path}"
        dnf --assumeyes install "${rpm_path}"
        installed_version="$(rpm -q --queryformat '%{VERSION}' "${package_name}")"
        [[ -x /usr/bin/codex ]] || die "installed package did not provide /usr/bin/codex"
        [[ "$(/usr/bin/codex --version)" == "codex-cli ${installed_version}" ]] ||
            die "installed Codex binary does not match RPM version ${installed_version}"
        [[ -n "$(find /etc/codex/skills -mindepth 2 -maxdepth 2 \
            -type f -name SKILL.md -print -quit 2>/dev/null)" ]] ||
            die "installed package did not provide any administrator Skills"
        provision_args=(--source-config "${source_config}")
        ((verify_upstream == 0)) || provision_args+=(--verify-upstream)
        /usr/sbin/cranesched-codex-provision "${provision_args[@]}"
        ;;
    uninstall)
        [[ "${EUID}" -eq 0 ]] || die "uninstall must run as root"
        command -v dnf >/dev/null || die "dnf is required for uninstallation"
        [[ "${1:-}" == "--yes" && $# -eq 1 ]] ||
            die "uninstall is destructive; rerun with: uninstall --yes"
        rpm -q "${package_name}" >/dev/null || die "${package_name} is not installed"
        dnf --assumeyes remove "${package_name}"
        [[ ! -e /etc/codex/proxy-api-key ]] ||
            die "RPM was removed but the credential still exists"
        printf '%s uninstalled. Modified config may remain as an RPM .rpmsave file.\n' \
            "${package_name}"
        ;;
    status)
        (($# == 0)) || die "status takes no arguments"
        rpm -q "${package_name}" || true
        if [[ -x /usr/bin/codex ]]; then
            /usr/bin/codex --version || true
        fi
        if [[ -d /etc/codex/skills ]]; then
            printf 'Administrator Skills:\n'
            find /etc/codex/skills -mindepth 2 -maxdepth 2 \
                -type f -name SKILL.md -printf '  %h\n' | sort
        fi
        systemctl status cranesched-codex-proxy.service --no-pager || true
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        die "unknown command: ${command_name}"
        ;;
esac
