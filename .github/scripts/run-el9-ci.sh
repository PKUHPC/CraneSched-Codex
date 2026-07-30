#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    compatibility) suite="tests/ci.sh" ;;
    release) suite="tests/release.sh" ;;
    *)
        printf 'Usage: run-el9-ci.sh {compatibility|release}\n' >&2
        exit 2
        ;;
esac

dnf --assumeyes install dnf-plugins-core epel-release
dnf config-manager --set-enabled crb || true
dnf --assumeyes install \
    bubblewrap cpio findutils git gzip iproute jq \
    procps-ng python3 python3-tomli ripgrep rpm rpm-build \
    systemd tar util-linux
git config --global --add safe.directory /workspace
git config --global --add safe.directory /workspace/submodules/codex
git config --global --add safe.directory /workspace/submodules/CraneSched
"${suite}"
