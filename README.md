# CraneSched-Codex

CraneSched-Codex packages a pinned Codex CLI, a loopback Responses API proxy,
cluster defaults, and CraneSched Admin Skills as one RPM for shared HPC nodes.
Users receive a working Managed Default without seeing the upstream credential,
while retaining the ability to configure BYOK in their own Codex home.

The package targets x86_64 Rocky Linux, AlmaLinux, and RHEL 9. DNF is the only
supported installation and removal path.

## Runtime model

```text
user Codex
    |
    | http://127.0.0.1:617/v1/responses
    v
cranesched-codex-proxy.service
    |
    | replaces Authorization with a systemd credential
    v
https://chat.pku.edu.cn/deployer/coding_tatu/v1/responses
```

The proxy listens only on loopback and accepts only the Responses path. The
upstream bearer token is stored at `/etc/codex/proxy-api-key`, mode `0400`, and
is opened by systemd as a service credential. It is never included in the RPM,
repository, process arguments, or process environment.

This is credential concealment, not multi-user authentication. Any local user
can consume the shared upstream allocation. The service applies process,
memory, CPU, file-descriptor, capability, and systemd sandbox limits, but it
does not implement per-user identity, quota, or accounting.

## Install the latest RPM

Download the RPM from the
[latest GitHub Release](https://github.com/Nativu5/CraneSched-Codex/releases/latest).
The repository is private, so the downloading account must have repository
access. On a workstation with an authenticated GitHub CLI, download it into a
clean directory:

```bash
release_dir="$(mktemp -d)"
gh release download \
  --repo Nativu5/CraneSched-Codex \
  --pattern 'cranesched-codex-*.el9.x86_64.rpm' \
  --dir "${release_dir}"
cd "${release_dir}"
```

Transfer the RPM to the target node if the node cannot access
GitHub. Install from a clean directory containing exactly one downloaded RPM:

```bash
sudo dnf install ./cranesched-codex-*.el9.x86_64.rpm
```

The RPM requires `bubblewrap`, `ripgrep`, and `python3-tomli`. Ensure those
packages are available from the node's enabled EL9 repositories or internal
mirror; DNF resolves them automatically.

Installation deliberately leaves the proxy stopped because no credential is
stored in the package.

## Provision the Managed Default

Prepare a root-owned Codex configuration that contains provider `pku`, the
expected PKU endpoint, and its administrator-held token. Do not commit this
file or expose its contents in logs:

```toml
[model_providers.pku]
base_url = "https://chat.pku.edu.cn/deployer/coding_tatu/v1"
experimental_bearer_token = "<administrator-held-token>"
```

The source must be a regular file owned by root and must not be readable by its
group or other users:

```bash
sudo chown root:root /root/.codex/config.toml
sudo chmod 600 /root/.codex/config.toml
sudo cranesched-codex-provision \
  --source-config /root/.codex/config.toml \
  --verify-upstream
```

The provisioner extracts only provider `pku`, validates its endpoint, rotates
the root-only service credential atomically, enables the proxy, and sends one
minimal real request. If validation fails, it restores the previous credential
and service state.

For an offline rollout, omit `--verify-upstream`, but run the verified command
before declaring the node ready.

## Verify and use

Administrators can verify the installed package, service, listener, and Codex
configuration without reading the credential:

```bash
rpm -q cranesched-codex
codex --version
sudo systemctl is-enabled cranesched-codex-proxy.service
sudo systemctl is-active cranesched-codex-proxy.service
sudo ss -ltnp '( sport = :617 )'
codex --strict-config doctor --json
```

The listener must be bound only to `127.0.0.1:617`. A readiness probe returns
HTTP 403 because every non-Responses path is intentionally rejected:

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  http://127.0.0.1:617/__cranesched_codex_ready
```

After provisioning, ordinary users start Codex without setting a shared API
key:

```bash
codex
```

The RPM installs `/etc/codex/config.toml` as a low-priority system default. It
selects provider `cluster_shared`, which points to the loopback proxy and does
not require OpenAI authentication.

Admin Skills are installed under `/etc/codex/skills` and discovered with Admin
scope. They are enabled by default. A user can disable an individual Skill in
`~/.codex/config.toml`:

```toml
[[skills.config]]
name = "cranesched-skill"
enabled = false
```

## Upgrade

Download the latest RPM into a new directory and run the same DNF command used
for installation:

```bash
sudo dnf install ./cranesched-codex-*.el9.x86_64.rpm
```

If the proxy is active and already has a credential, the RPM upgrade restarts
it with the new package. Run `cranesched-codex-provision` again when rotating
the administrator credential or when a real upstream verification is needed.

Keep the prior RPM available until the upgraded node passes the verification
commands and a normal user can start Codex successfully.

## User BYOK

System configuration is a default, not an enforced policy. A user can select a
different provider in `~/.codex/config.toml`, a profile, or CLI `-c` options.
For example:

```toml
model = "user-selected-model"
model_provider = "my_provider"

[model_providers.my_provider]
name = "My provider"
base_url = "https://user-provider.example/v1"
wire_api = "responses"
env_key = "MY_PROVIDER_API_KEY"
```

The user supplies `MY_PROVIDER_API_KEY` in their own environment. The shared
proxy does not intercept traffic sent to a user-selected endpoint.

## Troubleshooting

### The latest Release cannot be downloaded

Confirm that GitHub authentication can read the private repository and that a
Release exists:

```bash
gh auth status
gh release view --repo Nativu5/CraneSched-Codex
```

Download into a new directory. Reusing a directory with older RPMs can make a
shell wildcard select more than one package.

### DNF reports missing dependencies

The target node or internal mirror must provide `bubblewrap`, `ripgrep`, and
`python3-tomli` for EL9. Inspect enabled repositories before retrying:

```bash
sudo dnf repolist
sudo dnf install bubblewrap ripgrep python3-tomli
```

### Provisioning rejects the source configuration

Check metadata without printing the file. It must be a root-owned regular file
with no group or world access:

```bash
sudo stat --format='%F %a %U:%G' /root/.codex/config.toml
```

The file must contain `[model_providers.pku]`, the exact expected `base_url`,
and a non-empty `experimental_bearer_token`. Do not paste the token into an
Issue, terminal transcript, or support message.

### The proxy does not start

Inspect systemd state and recent logs, then check whether another process owns
the loopback port:

```bash
sudo systemctl status cranesched-codex-proxy.service --no-pager
sudo journalctl -u cranesched-codex-proxy.service -n 100 --no-pager
sudo ss -ltnp '( sport = :617 )'
```

The service requires systemd 247 or newer and expects port 617 to remain a
privileged port. Provisioning reports an actionable error when either contract
is not met.

### Codex does not use the Managed Default

Run the strict configuration doctor and inspect user overrides:

```bash
codex --strict-config doctor --json
test ! -f ~/.codex/config.toml || \
  rg -n '^(model|model_provider|profile)[[:space:]]*=' ~/.codex/config.toml
```

The effective provider should be `cluster_shared` when no user override is
present. Never include credentials when sharing diagnostic output.

### Local checks pass but real requests fail

Re-run provisioning with the real upstream check. It sends one minimal request
and restores the previous working state if verification fails:

```bash
sudo cranesched-codex-provision \
  --source-config /root/.codex/config.toml \
  --verify-upstream
```

## Remove

An administrator who has only the RPM removes it through DNF:

```bash
sudo dnf remove cranesched-codex
```

Removal stops and disables the unit and removes the generated credential,
Codex binary, system config, and Admin Skills. A locally modified
`/etc/codex/config.toml` may remain as an RPM `.rpmsave` file.

## Build from source

Clone with both upstream references:

```bash
git clone --recurse-submodules \
  https://github.com/Nativu5/CraneSched-Codex.git
cd CraneSched-Codex
```

For an existing clone:

```bash
git submodule update --init --recursive
```

On an x86_64 EL9 build host, install the build tools and build the locked RPM:

```bash
sudo dnf install rpm-build rpm-build-libs rpm cpio curl jq tar gzip git ripgrep
./cranesched-codex.sh build
```

The build reads `packaging/codex.lock.json`, downloads the named official Codex
release asset, verifies its SHA-256 digest, and writes a versioned RPM under
`dist/`. Downloaded assets are cached under `dist/cache/`; neither the cache nor
RPMs are tracked by Git. Run `tests/ci.sh` for the complete compatibility suite.

`submodules/codex` is pinned to the source commit matching the packaged Codex
release. `submodules/CraneSched` is pinned independently and is never moved by a
Codex update.

## Tests

Run the complete local suite:

```bash
tests/ci.sh
```

Runtime or packaging work also uses the documented root-only checks:

```bash
SYSTEM_CONFIG_RUNTIME_TEST=1 proxy/tests/test.sh
SYSTEMD_RUNTIME_TEST=1 proxy/tests/test.sh
sudo tests/test-installed-node.sh
```

Normal CI uses fixture credentials and a mock upstream. It never receives a
real administrator key. A real request is an explicit, administrator-controlled
deployment test only.

## Release process

The Codex Source Lock is the sole packaging version source. An administrator
starts the `Upgrade Codex` workflow with a Codex version and RPM release number.
Keeping the Codex version unchanged while incrementing the RPM release produces
a packaging-only release.

The workflow verifies the official artifact without building an RPM, then
creates a Draft `codex-upgrade` PR. A human marks it ready, waits for
Compatibility CI to build and test the RPM, approves it, and squash-merges it.
The guarded Release workflow rebuilds from the merged commit, validates the
release artifact, and publishes the RPM to GitHub Releases.
Manual asset publication and releases from uncommitted workflow state are not
supported.
