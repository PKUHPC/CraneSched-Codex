#!/usr/bin/env bash
set -euo pipefail

tests_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
proxy_dir="$(cd -- "${tests_dir}/.." && pwd)"
repo_dir="$(cd -- "${proxy_dir}/.." && pwd)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cranesched-codex-proxy-test.XXXXXX")"
codex_bin="${CODEX_BIN:-$("${repo_dir}/packaging/fetch-codex.sh")}"
mock_pid=""
proxy_pid=""
runtime_unit=""
runtime_unit_file=""
runtime_bin=""
runtime_wrapper=""
runtime_key=""

cleanup() {
    if [[ -n "${runtime_unit}" ]]; then
        systemctl stop "${runtime_unit}" 2>/dev/null || true
        systemctl reset-failed "${runtime_unit}" 2>/dev/null || true
    fi
    [[ -z "${proxy_pid}" ]] || kill "${proxy_pid}" 2>/dev/null || true
    [[ -z "${mock_pid}" ]] || kill "${mock_pid}" 2>/dev/null || true
    [[ -z "${proxy_pid}" ]] || wait "${proxy_pid}" 2>/dev/null || true
    [[ -z "${mock_pid}" ]] || wait "${mock_pid}" 2>/dev/null || true
    if [[ -n "${runtime_unit_file}" ]]; then
        rm -f -- "${runtime_unit_file}"
        systemctl daemon-reload 2>/dev/null || true
    fi
    [[ -z "${runtime_bin}" ]] || rm -f -- "${runtime_bin}"
    [[ -z "${runtime_wrapper}" ]] || rm -f -- "${runtime_wrapper}"
    [[ -z "${runtime_key}" ]] || rm -f -- "${runtime_key}"
    rm -rf -- "${temp_dir}"
}
trap cleanup EXIT

python3 - \
    "${repo_dir}/config.toml" \
    "${proxy_dir}/cranesched-codex-proxy.service" \
    "${proxy_dir}/cranesched-codex-proxy" \
    "${repo_dir}/cranesched-codex.sh" <<'PY'
import pathlib
import sys

config_path, unit_path, wrapper_path, manager_path = map(pathlib.Path, sys.argv[1:])
config_text = config_path.read_text(encoding="utf-8")
required_lines = {
    'model = "gpt-5.6-sol"',
    'model_provider = "cluster_shared"',
    '[model_providers.cluster_shared]',
    'name = "PKU CraneSched-Codex Proxy"',
    'base_url = "http://127.0.0.1:617/v1"',
    'wire_api = "responses"',
    'requires_openai_auth = false',
}
assert required_lines <= {line.strip() for line in config_text.splitlines()}
assert "/etc/codex/skills" in config_text
for forbidden in ("bearer", "api_key", "api-key", "experimental_bearer_token"):
    assert forbidden not in config_text.lower()

unit = unit_path.read_text(encoding="utf-8")
assert "Description=CraneSched-Codex Responses API proxy" in unit
assert "ExecStart=/usr/libexec/cranesched-codex/cranesched-codex-proxy --port 617" in unit
assert "--upstream-url=https://chat.pku.edu.cn/deployer/coding_tatu/v1/responses" in unit
assert "LoadCredential=api-key:/etc/codex/proxy-api-key" in unit
assert "SELinuxContext=system_u:system_r:unconfined_service_t:s0" in unit
assert "CapabilityBoundingSet=CAP_NET_BIND_SERVICE" in unit
assert "AmbientCapabilities=CAP_NET_BIND_SERVICE" in unit
assert "StandardInput=" not in unit
for resource_limit in (
    "LimitNOFILE=8192",
    "MemoryHigh=1G",
    "MemoryMax=2G",
    "TasksMax=256",
    "CPUQuota=400%",
):
    assert resource_limit in unit

wrapper = wrapper_path.read_text(encoding="utf-8")
assert '${CREDENTIALS_DIRECTORY}/api-key' in wrapper
assert 'exec /usr/libexec/cranesched-codex/codex responses-api-proxy "$@" <' in wrapper

manager = manager_path.read_text(encoding="utf-8")
assert 'dnf --assumeyes install "${rpm_path}"' in manager
assert 'dnf --assumeyes remove "${package_name}"' in manager
assert "rpm -Uvh" not in manager
assert 'rpm -e "${package_name}"' not in manager
PY

extractor="${proxy_dir}/extract_provider_credential.py"
install -m 0600 -- "${tests_dir}/fixtures/source-config.toml" \
    "${temp_dir}/source-config.toml"
python3 "${extractor}" \
    --source "${temp_dir}/source-config.toml" \
    --provider pku \
    --expected-base-url https://chat.pku.edu.cn/deployer/coding_tatu/v1 \
    --output "${temp_dir}/proxy-api-key" >"${temp_dir}/extract.log"
[[ ! -s "${temp_dir}/extract.log" ]]
[[ "$(stat -c '%a' "${temp_dir}/proxy-api-key")" == "400" ]]
[[ "$(<"${temp_dir}/proxy-api-key")" == "fixture-secret" ]]

install -m 0600 -- "${tests_dir}/fixtures/source-config.toml" \
    "${temp_dir}/wrong-endpoint.toml"
sed -i 's#https://chat.pku.edu.cn/deployer/coding_tatu/v1#https://wrong.invalid/v1#' \
    "${temp_dir}/wrong-endpoint.toml"
if python3 "${extractor}" \
    --source "${temp_dir}/wrong-endpoint.toml" \
    --provider pku \
    --expected-base-url https://chat.pku.edu.cn/deployer/coding_tatu/v1 \
    --output "${temp_dir}/wrong-key" >"${temp_dir}/wrong.log" 2>&1; then
    printf 'Credential extractor accepted a mismatched endpoint\n' >&2
    exit 1
fi
[[ ! -e "${temp_dir}/wrong-key" ]]

install -m 0600 -- "${tests_dir}/fixtures/multiline-decoy.toml" \
    "${temp_dir}/multiline.toml"
if python3 "${extractor}" \
    --source "${temp_dir}/multiline.toml" \
    --provider pku \
    --expected-base-url https://chat.pku.edu.cn/deployer/coding_tatu/v1 \
    --output "${temp_dir}/multiline-key" >"${temp_dir}/multiline.log" 2>&1; then
    printf 'Credential extractor accepted a multiline TOML decoy\n' >&2
    exit 1
fi
[[ ! -e "${temp_dir}/multiline-key" ]]

install -m 0600 -- "${tests_dir}/fixtures/comment-triple-quote.toml" \
    "${temp_dir}/comment.toml"
python3 "${extractor}" \
    --source "${temp_dir}/comment.toml" \
    --provider pku \
    --expected-base-url https://chat.pku.edu.cn/deployer/coding_tatu/v1 \
    --output "${temp_dir}/comment-key"
[[ "$(<"${temp_dir}/comment-key")" == "fixture-secret" ]]

stage="${temp_dir}/stage"
install -d -m 0755 -- \
    "${stage}/etc/codex/skills" \
    "${stage}/usr/bin" \
    "${stage}/usr/libexec/cranesched-codex" \
    "${stage}/usr/lib/systemd/system"
install -m 0644 -- "${repo_dir}/config.toml" "${stage}/etc/codex/config.toml"
cp -a -- "${repo_dir}/skills/." "${stage}/etc/codex/skills/"
install -m 0755 -- "${codex_bin}" "${stage}/usr/libexec/cranesched-codex/codex"
install -m 0755 -- "${proxy_dir}/cranesched-codex-proxy" \
    "${stage}/usr/libexec/cranesched-codex/cranesched-codex-proxy"
install -m 0644 -- "${proxy_dir}/cranesched-codex-proxy.service" \
    "${stage}/usr/lib/systemd/system/cranesched-codex-proxy.service"
ln -s ../libexec/cranesched-codex/codex "${stage}/usr/bin/codex"
systemd-analyze --recursive-errors=no --root="${stage}" \
    verify cranesched-codex-proxy.service

if [[ "${SYSTEM_CONFIG_RUNTIME_TEST:-0}" == "1" ]]; then
    [[ "${EUID}" -eq 0 ]] || {
        printf 'SYSTEM_CONFIG_RUNTIME_TEST=1 requires root\n' >&2
        exit 1
    }
    install -d -m 0700 -- "${temp_dir}/system-layer-codex-home"
    unshare --mount --propagation private \
        "${tests_dir}/test-system-config-layer.sh" \
        "${repo_dir}/config.toml" \
        "${repo_dir}/skills" \
        "${tests_dir}/fixtures/user-override.toml" \
        "${temp_dir}/system-layer-codex-home" \
        "${codex_bin}" \
        "${temp_dir}/system-layer-report.json" \
        "${temp_dir}/user-layer-report.json" \
        "${temp_dir}/admin-skills-report.json" \
        "${temp_dir}/user-skills-report.json"
    jq -e '
        .checks["config.load"].status == "ok" and
        .checks["config.load"].details.model == "gpt-5.6-sol" and
        .checks["config.load"].details["model provider"] == "cluster_shared"
    ' "${temp_dir}/system-layer-report.json" >/dev/null
    jq -e '
        .checks["config.load"].status == "ok" and
        .checks["config.load"].details.model == "user-model" and
        .checks["config.load"].details["model provider"] == "user_byok"
    ' "${temp_dir}/user-layer-report.json" >/dev/null
    jq -e '
        .data | length == 1 and
        .[0].errors == [] and
        any(.[0].skills[];
            .name == "cranesched-skill" and
            .scope == "admin" and
            .enabled == true and
            .path == "/etc/codex/skills/cranesched-skill/SKILL.md")
    ' "${temp_dir}/admin-skills-report.json" >/dev/null
    jq -e '
        .data | length == 1 and
        .[0].errors == [] and
        any(.[0].skills[];
            .name == "cranesched-skill" and
            .scope == "admin" and
            .enabled == false)
    ' "${temp_dir}/user-skills-report.json" >/dev/null
fi

mock_port_args=()
if [[ "${SYSTEMD_RUNTIME_TEST:-0}" == "1" ]]; then
    command -v ss >/dev/null || {
        printf 'SYSTEMD_RUNTIME_TEST=1 requires ss\n' >&2
        exit 1
    }
    if ss -ltn '( sport = :9000 )' | tail -n +2 | rg -q '.'; then
        printf 'SYSTEMD_RUNTIME_TEST requires free local TCP port 9000\n' >&2
        exit 1
    fi
    mock_port_args=(--port 9000)
fi
python3 "${tests_dir}/mock_upstream.py" "${mock_port_args[@]}" \
    --port-file "${temp_dir}/upstream-port" \
    --capture-file "${temp_dir}/capture.json" &
mock_pid=$!
for _ in {1..100}; do
    [[ -s "${temp_dir}/upstream-port" ]] && break
    sleep 0.05
done
[[ -s "${temp_dir}/upstream-port" ]] || {
    printf 'Mock upstream did not start\n' >&2
    exit 1
}
upstream_port="$(<"${temp_dir}/upstream-port")"

if [[ "${SYSTEMD_RUNTIME_TEST:-0}" == "1" ]]; then
    [[ "${EUID}" -eq 0 ]] || {
        printf 'SYSTEMD_RUNTIME_TEST=1 requires root\n' >&2
        exit 1
    }
    runtime_unit="cranesched-codex-proxy-test-${BASHPID}.service"
    runtime_unit_file="/run/systemd/system/${runtime_unit}"
    runtime_bin="/usr/libexec/cranesched-codex-test-${BASHPID}"
    runtime_wrapper="/usr/libexec/cranesched-codex-proxy-test-${BASHPID}"
    runtime_key="/run/cranesched-codex-key-test-${BASHPID}"
    install -m 0755 -- "${codex_bin}" "${runtime_bin}"
    sed "s#/usr/libexec/cranesched-codex/codex#${runtime_bin}#" \
        "${proxy_dir}/cranesched-codex-proxy" >"${runtime_wrapper}"
    chmod 0755 "${runtime_wrapper}"
    install -m 0400 -- "${temp_dir}/proxy-api-key" "${runtime_key}"
    sed \
        -e "s#/usr/libexec/cranesched-codex/cranesched-codex-proxy#${runtime_wrapper}#" \
        -e "s#https://chat.pku.edu.cn/deployer/coding_tatu/v1/responses#http://127.0.0.1:${upstream_port}/deployer/coding_tatu/v1/responses#" \
        -e "s#LoadCredential=api-key:/etc/codex/proxy-api-key#LoadCredential=api-key:${runtime_key}#" \
        "${proxy_dir}/cranesched-codex-proxy.service" >"${runtime_unit_file}"
    systemctl daemon-reload
    systemctl start "${runtime_unit}"
    for _ in {1..100}; do
        if curl --fail --silent --connect-timeout 0.2 --max-time 1 \
            --output "${temp_dir}/systemd-response.json" \
            -X POST -H 'content-type: application/json' \
            --data '{"model":"fixture","input":"systemd-test"}' \
            "http://127.0.0.1:617/v1/responses"; then
            break
        fi
        [[ "$(systemctl show --property=ExecMainStatus --value "${runtime_unit}")" == "0" ]] ||
            break
        sleep 0.05
    done
    [[ "$(<"${temp_dir}/systemd-response.json")" == '{"proxy_test":"ok"}' ]] || {
        systemctl status "${runtime_unit}" --no-pager >&2 || true
        journalctl -u "${runtime_unit}" -n 80 --no-pager >&2 || true
        exit 1
    }
    runtime_pid="$(systemctl show --property=MainPID --value "${runtime_unit}")"
    [[ "$(awk '/^Uid:/ { print $2 }' "/proc/${runtime_pid}/status")" != "0" ]]
    if [[ "$(getenforce 2>/dev/null || true)" == "Enforcing" ]]; then
        runtime_context="$(tr -d '\0' <"/proc/${runtime_pid}/attr/current")"
        [[ "${runtime_context}" == *":unconfined_service_t:"* ]]
    fi
    systemctl stop "${runtime_unit}"
    systemctl reset-failed "${runtime_unit}" 2>/dev/null || true
    runtime_unit=""
    rm -f -- "${runtime_unit_file}" "${runtime_bin}" "${runtime_wrapper}" "${runtime_key}"
    runtime_unit_file=""
    runtime_bin=""
    runtime_wrapper=""
    runtime_key=""
    systemctl daemon-reload
fi

printf '%s\n' 'fixture-secret' | "${codex_bin}" responses-api-proxy \
    --port 0 \
    --server-info "${temp_dir}/proxy-info.json" \
    --upstream-url "http://127.0.0.1:${upstream_port}/deployer/coding_tatu/v1/responses" \
    >"${temp_dir}/proxy.log" 2>&1 &
proxy_pid=$!
for _ in {1..100}; do
    [[ -s "${temp_dir}/proxy-info.json" ]] && break
    sleep 0.05
done
[[ -s "${temp_dir}/proxy-info.json" ]] || {
    sed -n '1,120p' "${temp_dir}/proxy.log" >&2
    printf 'Proxy did not start\n' >&2
    exit 1
}
proxy_port="$(jq -r .port "${temp_dir}/proxy-info.json")"

response="$(curl --fail --silent --show-error \
    -X POST \
    -H 'authorization: Bearer attacker-controlled' \
    -H 'content-type: application/json' \
    --data '{"model":"fixture","input":"test"}' \
    "http://127.0.0.1:${proxy_port}/v1/responses")"
[[ "${response}" == '{"proxy_test":"ok"}' ]]

python3 - "${temp_dir}/capture.json" "${upstream_port}" <<'PY'
import json
import pathlib
import sys

capture = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert capture["path"] == "/deployer/coding_tatu/v1/responses"
assert capture["authorization"] == "Bearer fixture-secret"
assert capture["host"] == f"127.0.0.1:{sys.argv[2]}"
assert json.loads(capture["body"]) == {"model": "fixture", "input": "test"}
PY

for forbidden_path in "/v1/models" "/v1/responses?debug=1" "/shutdown"; do
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
        -X POST "http://127.0.0.1:${proxy_port}${forbidden_path}")"
    [[ "${status}" == "403" ]] || {
        printf 'Expected 403 for %s, got %s\n' "${forbidden_path}" "${status}" >&2
        exit 1
    }
done

printf 'All CraneSched-Codex proxy tests passed.\n'
