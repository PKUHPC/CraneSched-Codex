#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    printf 'Usage: test-codex-compatibility.sh CODEX_BIN\n' >&2
    exit 2
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
codex_bin="$(readlink -f -- "$1")"
source_lock="${repo_dir}/packaging/codex.lock.json"
expected_version="$(jq -r .version "${source_lock}")"
expected_target="$(jq -r .target "${source_lock}")"

die() {
    printf 'test-codex-compatibility.sh: %s\n' "$*" >&2
    exit 1
}

[[ -x "${codex_bin}" ]] || die "Codex binary is not executable: ${codex_bin}"
[[ "$(od -An -tx1 -N4 -- "${codex_bin}" | tr -d '[:space:]')" == "7f454c46" ]] ||
    die "Codex binary is not ELF"
case "${expected_target}" in
    x86_64-unknown-linux-musl)
        [[ "$(od -An -tu2 -j18 -N2 -- "${codex_bin}" | tr -d '[:space:]')" == "62" ]] ||
            die "Codex ELF machine is not x86_64"
        ;;
    *) die "unsupported compatibility target: ${expected_target}" ;;
esac

[[ "$("${codex_bin}" --version)" == "codex-cli ${expected_version}" ]] ||
    die "Codex version does not match Source Lock ${expected_version}"
proxy_help="$("${codex_bin}" responses-api-proxy --help)"
rg -q -- '--port' <<<"${proxy_help}" || die "responses-api-proxy lost --port"
rg -q -- '--upstream-url' <<<"${proxy_help}" ||
    die "responses-api-proxy lost --upstream-url"
app_server_help="$("${codex_bin}" app-server --help)"
rg -q -- '--listen' <<<"${app_server_help}" || die "app-server lost --listen"
rg -q -- '--strict-config' <<<"${app_server_help}" ||
    die "app-server lost --strict-config"

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-compat.XXXXXX")"
cleanup() {
    rm -rf -- "${test_dir}"
}
trap cleanup EXIT
install -d -m 0700 -- "${test_dir}/codex-home"
install -m 0600 -- "${repo_dir}/config.toml" "${test_dir}/codex-home/config.toml"
"${repo_dir}/packaging/stage-cranesched-skills.sh" \
    "${test_dir}/codex-home/skills"
chmod 0700 "${test_dir}/codex-home/skills"

CODEX_HOME="${test_dir}/codex-home" \
    "${codex_bin}" --strict-config doctor --json >"${test_dir}/doctor.json" || true
jq -e '
    .checks["config.load"].status == "ok" and
    .checks["config.load"].details.model == "gpt-5.6-sol" and
    .checks["config.load"].details["model provider"] == "cluster_shared" and
    .checks["auth.credentials"].status == "ok" and
    .checks["auth.credentials"].details["model provider requires OpenAI auth"] == "false"
' "${test_dir}/doctor.json" >/dev/null || die "system default config is incompatible"

CODEX_HOME="${test_dir}/codex-home" python3 - \
    "${codex_bin}" "${repo_dir}" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

codex_bin, cwd = sys.argv[1:]
process = subprocess.Popen(
    [codex_bin, "app-server", "--listen", "stdio://", "--strict-config"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
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
        line = process.stdout.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message["result"]
    stderr = process.stderr.read() if process.poll() is not None else ""
    raise RuntimeError(f"timed out waiting for response {request_id}: {stderr}")


try:
    send(
        {
            "method": "initialize",
            "id": 0,
            "params": {
                "clientInfo": {
                    "name": "cranesched_codex_compat",
                    "title": "CraneSched-Codex Compatibility",
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
            "params": {"cwds": [cwd], "forceReload": True},
        }
    )
    skills_result = receive(1)
    entries = skills_result.get("data", [])
    if not entries or entries[0].get("errors"):
        raise RuntimeError(f"skills/list returned errors: {skills_result}")
    if not any(skill.get("name") == "cranesched-skill" for skill in entries[0]["skills"]):
        raise RuntimeError("skills/list did not discover cranesched-skill")
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
PY

printf 'Codex %s compatibility contract passed.\n' "${expected_version}"
