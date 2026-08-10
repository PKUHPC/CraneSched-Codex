#!/usr/bin/env bash
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || {
    printf 'test-installed-node.sh must run as root\n' >&2
    exit 1
}

package_name="cranesched-codex"
service_name="cranesched-codex-proxy.service"
proxy_config="/etc/codex/proxy-upstream.conf"

rpm -q "${package_name}" >/dev/null
[[ "$(/usr/bin/codex --version)" == \
    "codex-cli $(rpm -q --queryformat '%{VERSION}' "${package_name}")" ]]
systemctl is-active --quiet "${service_name}"
systemctl is-enabled --quiet "${service_name}"
[[ ! -L "${proxy_config}" ]]
[[ "$(stat -c '%a %U:%G' "${proxy_config}")" == "600 root:root" ]]
runuser -u nobody -- test ! -r "${proxy_config}"

# Type=simple becomes active before the Proxy finishes binding its listener.
listeners=""
for _ in {1..100}; do
    listeners="$(ss -ltnH '( sport = :617 )')"
    if rg -q '127\.0\.0\.1:617' <<<"${listeners}"; then
        break
    fi
    sleep 0.1
done
if ! rg -q '127\.0\.0\.1:617' <<<"${listeners}"; then
    systemctl status "${service_name}" --no-pager >&2 || true
    journalctl -u "${service_name}" -n 100 --no-pager >&2 || true
    printf 'Proxy listener did not become ready on 127.0.0.1:617\n' >&2
    exit 1
fi
[[ "$(wc -l <<<"${listeners}")" -eq 1 ]]
! rg -q '0\.0\.0\.0:617|\[::\]:617' <<<"${listeners}"

main_pid="$(systemctl show --property=MainPID --value "${service_name}")"
[[ "${main_pid}" =~ ^[1-9][0-9]*$ ]]
runtime_uid="$(awk '/^Uid:/ { print $2 }' "/proc/${main_pid}/status")"
[[ "${runtime_uid}" == "0" ]]
if [[ "$(getenforce 2>/dev/null || true)" == "Enforcing" ]]; then
    runtime_context="$(tr -d '\0' <"/proc/${main_pid}/attr/current")"
    [[ "${runtime_context}" == *":unconfined_service_t:"* ]]
fi

python3 - "${proxy_config}" "${main_pid}" <<'PY'
import pathlib
import sys

config_path, pid = sys.argv[1:]
lines = pathlib.Path(config_path).read_bytes().splitlines()
if len(lines) != 2 or not lines[0] or not lines[1]:
    raise SystemExit("installed proxy upstream configuration must contain endpoint and token")
endpoint, secret = lines
cmdline = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes()
if endpoint not in cmdline:
    raise SystemExit("configured endpoint is missing from proxy cmdline")
for proc_name in ("cmdline", "environ"):
    process_data = pathlib.Path(f"/proc/{pid}/{proc_name}").read_bytes()
    if secret in process_data:
        raise SystemExit(f"credential leaked through process {proc_name}")
PY

test_dir="$(mktemp -d /var/tmp/cranesched-codex-installed-test.XXXXXX)"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT
install -d -m 0700 -- "${test_dir}/codex-home"

CODEX_HOME="${test_dir}/codex-home" \
    /usr/bin/codex --strict-config doctor --json >"${test_dir}/doctor.json" || true
jq -e '
    .checks["config.load"].status == "ok" and
    .checks["config.load"].details.model == "gpt-5.6-sol" and
    .checks["config.load"].details["model provider"] == "cluster_shared" and
    .checks["auth.credentials"].details["model provider requires OpenAI auth"] == "false"
' "${test_dir}/doctor.json" >/dev/null

CODEX_HOME="${test_dir}/codex-home" python3 - /usr/bin/codex <<'PY'
import json
import os
import select
import subprocess
import sys
import time

process = subprocess.Popen(
    [sys.argv[1], "app-server", "--listen", "stdio://", "--strict-config"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    env=os.environ.copy(),
)


def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()


def receive(request_id):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.5)
        if not ready:
            continue
        message = json.loads(process.stdout.readline())
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
                    "name": "cranesched_codex_canary",
                    "title": "CraneSched-Codex Canary",
                    "version": "1",
                }
            },
        }
    )
    receive(0)
    send({"method": "initialized", "params": {}})
    send(
        {
            "method": "skills/list",
            "id": 1,
            "params": {"cwds": ["/var/tmp"], "forceReload": True},
        }
    )
    result = receive(1)
    entries = result.get("data", [])
    if not entries or entries[0].get("errors"):
        raise RuntimeError(f"skills/list returned errors: {result}")
    expected = {
        "name": "cranesched-skill",
        "scope": "admin",
        "enabled": True,
        "path": "/etc/codex/skills/cranesched-skill/SKILL.md",
    }
    if not any(expected.items() <= skill.items() for skill in entries[0]["skills"]):
        raise RuntimeError("Admin Skill was not discovered with the expected scope")
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
PY

ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    http://127.0.0.1:617/__cranesched_codex_ready)"
[[ "${ready_status}" == "403" ]]

printf 'Installed CraneSched-Codex node contract passed.\n'
