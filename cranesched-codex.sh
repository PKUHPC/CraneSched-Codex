#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly package_name="cranesched-codex"

usage() {
    cat <<'EOF'
Usage:
  ./cranesched-codex.sh build
  sudo ./cranesched-codex.sh install [--rpm PATH]
  sudo ./cranesched-codex.sh uninstall --yes
  ./cranesched-codex.sh status

Commands:
  build      Build an RPM with the pinned Codex binary and runtime dependencies.
  install    Install an RPM with DNF; configure and start the proxy manually.
  uninstall  Remove the package with DNF, including its proxy configuration.
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
        rpm_path=""
        while (($# > 0)); do
            case "$1" in
                --rpm)
                    (($# >= 2)) || die "--rpm requires a path"
                    rpm_path="$2"
                    shift 2
                    ;;
                *) die "unknown install argument: $1" ;;
            esac
        done
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
            die "installed package did not provide the CraneSched Skill"
        printf '%s\n' \
            'Package installed. Configure /etc/codex/proxy-upstream.conf as documented before starting the proxy.'
        ;;
    uninstall)
        [[ "${EUID}" -eq 0 ]] || die "uninstall must run as root"
        command -v dnf >/dev/null || die "dnf is required for uninstallation"
        [[ "${1:-}" == "--yes" && $# -eq 1 ]] ||
            die "uninstall is destructive; rerun with: uninstall --yes"
        rpm -q "${package_name}" >/dev/null || die "${package_name} is not installed"
        dnf --assumeyes remove "${package_name}"
        [[ ! -e /etc/codex/proxy-upstream.conf ]] ||
            die "RPM was removed but the proxy configuration still exists"
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
            printf 'CraneSched Skills:\n'
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
