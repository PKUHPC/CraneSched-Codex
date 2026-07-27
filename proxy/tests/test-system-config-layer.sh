#!/usr/bin/env bash
set -euo pipefail

if (($# != 9)); then
    printf 'Usage: test-system-config-layer.sh SYSTEM_CONFIG ADMIN_SKILLS USER_CONFIG CODEX_HOME CODEX SYSTEM_REPORT USER_REPORT ADMIN_SKILLS_REPORT USER_SKILLS_REPORT\n' >&2
    exit 2
fi

system_config="$1"
admin_skills="$2"
user_config="$3"
test_codex_home="$4"
codex_bin="$5"
system_report="$6"
user_report="$7"
admin_skills_report="$8"
user_skills_report="$9"

mount -t tmpfs -o mode=0755 cranesched-codex-test-etc /etc
install -d -m 0755 /etc/codex
install -m 0644 -- "${system_config}" /etc/codex/config.toml
install -d -m 0755 /etc/codex/skills
cp -a -- "${admin_skills}/." /etc/codex/skills/
install -d -m 0700 -- "${test_codex_home}"

list_skills() {
    local report="$1"
    CODEX_HOME="${test_codex_home}" python3 - \
        "${codex_bin}" "${report}" "${test_codex_home}" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

codex_bin, report, cwd = sys.argv[1:]
process = subprocess.Popen(
    [codex_bin, "app-server", "--listen", "stdio://", "--strict-config"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    env=os.environ.copy(),
)


def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()


def response(request_id):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.5)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message["result"]
    raise RuntimeError(f"timed out waiting for app-server response {request_id}")


try:
    send(
        {
            "method": "initialize",
            "id": 0,
            "params": {
                "clientInfo": {
                    "name": "cranesched_codex_test",
                    "title": "CraneSched-Codex Test",
                    "version": "1",
                }
            },
        }
    )
    response(0)
    send({"method": "initialized", "params": {}})
    send(
        {
            "method": "skills/list",
            "id": 1,
            "params": {"cwds": [cwd], "forceReload": True},
        }
    )
    result = response(1)
    with open(report, "w", encoding="utf-8") as handle:
        json.dump(result, handle)
        handle.write("\n")
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
PY
}

CODEX_HOME="${test_codex_home}" "${codex_bin}" --strict-config doctor --json \
    >"${system_report}" || true
list_skills "${admin_skills_report}"
install -m 0600 -- "${user_config}" "${test_codex_home}/config.toml"
CODEX_HOME="${test_codex_home}" "${codex_bin}" --strict-config doctor --json \
    >"${user_report}" || true
list_skills "${user_skills_report}"
