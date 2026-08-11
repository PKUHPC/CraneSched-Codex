# CraneSched-Codex

CraneSched-Codex packages a pinned Codex CLI, a loopback Responses API proxy,
cluster defaults, and a CraneSched user Skill as one RPM for shared HPC nodes.
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
    | wrapper reads root-only endpoint and token configuration
    v
administrator-selected Responses endpoint
```

The proxy listens only on loopback and accepts only the Responses path. The
upstream endpoint and bearer token are stored in
`/etc/codex/proxy-upstream.conf`, owned by `root:root` with mode `0600`. The
wrapper reads the endpoint and passes the token to the proxy through stdin. The
token is never included in the RPM, repository, process arguments, or process
environment.

This is credential concealment, not multi-user authentication. Any local user
can consume the shared upstream allocation. The proxy runs as root so it can
read the root-only configuration directly. The unit retains process, memory,
CPU, file-descriptor, capability, and systemd sandbox limits, but it does not
implement per-user identity, quota, or accounting.

## Install the latest RPM

Download the RPM from the
[latest GitHub Release](https://github.com/Nativu5/CraneSched-Codex/releases/latest).
On a workstation with GitHub CLI, download it into a clean directory:

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

The RPM requires `bubblewrap` and `ripgrep`. Ensure those packages are
available from the node's enabled EL9 repositories or internal mirror; DNF
resolves them automatically.

Installation deliberately leaves the proxy stopped because no upstream
configuration is stored in the package.

## Configure the Managed Default

Create the fixed proxy upstream configuration as root. It has exactly two
lines: the first line is the complete Responses endpoint, including
`/responses`; the second line is the bearer token. Use HTTPS for any
non-loopback endpoint. Do not commit this file or expose its contents in logs,
Issues, or shell history.

```text
https://gateway.example.edu/v1/responses
<administrator-held-token>
```

Create an empty file with the required ownership and mode, then edit it with
`sudoedit` so the token is not passed as a command-line argument:

```bash
sudo install -d -m 0755 -o root -g root /etc/codex
sudo install -m 0600 -o root -g root /dev/null \
  /etc/codex/proxy-upstream.conf
sudoedit /etc/codex/proxy-upstream.conf
sudo chown root:root /etc/codex/proxy-upstream.conf
sudo chmod 0600 /etc/codex/proxy-upstream.conf
```

The wrapper rejects symbolic links, non-regular files, any owner other than
root, and any mode other than `0600`. It requires exactly two newline-terminated
lines, a complete `http` or `https` endpoint whose parsed path ends in
`/responses` and has no fragment, and a non-empty token of at most 1016 ASCII
letters, numbers, `-`, or `_`. An upstream query string is allowed.

Inspect only the metadata and endpoint before starting; do not print the second
line:

```bash
sudo stat --format='%F %a %U:%G' /etc/codex/proxy-upstream.conf
sudo sed -n '1p' /etc/codex/proxy-upstream.conf
sudo systemctl enable --now cranesched-codex-proxy.service
```

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

After the local checks pass, send one minimal real request before declaring the
node ready:

```bash
curl --fail --silent --show-error --output /dev/null \
  --max-time 120 \
  -H 'content-type: application/json' \
  --data '{"model":"gpt-5.6-sol","input":"Reply exactly: OK","max_output_tokens":16,"stream":false,"store":false}' \
  http://127.0.0.1:617/v1/responses
```

After configuration, ordinary users start Codex without setting a shared API
key:

```bash
codex
```

The RPM installs `/etc/codex/config.toml` as a low-priority system default. It
selects provider `cluster_shared`, which points to the loopback proxy and does
not require OpenAI authentication.

The CraneSched Skill is installed under `/etc/codex/skills` and discovered by
Codex for every user. Codex reports the system-installed copy with `admin`
scope because of its filesystem location; this is a loader classification, not
an administrator-only restriction. The Skill is enabled by default, and a user
can disable it in `~/.codex/config.toml`:

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

The RPM does not restart the proxy automatically. Restart it after every
upgrade, then repeat the listener, readiness, and real upstream checks:

```bash
sudo systemctl restart cranesched-codex-proxy.service
```

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

Confirm that a Release exists and that the node or download workstation can
reach GitHub:

```bash
gh release view --repo Nativu5/CraneSched-Codex
```

Download into a new directory. Reusing a directory with older RPMs can make a
shell wildcard select more than one package.

### DNF reports missing dependencies

The target node or internal mirror must provide `bubblewrap` and `ripgrep` for
EL9. Inspect enabled repositories before retrying:

```bash
sudo dnf repolist
sudo dnf install bubblewrap ripgrep
```

### The wrapper rejects its configuration

Check metadata without printing the token. The file must be a root-owned
regular file, not a symbolic link, with exact mode `0600`:

```bash
sudo test ! -L /etc/codex/proxy-upstream.conf
sudo stat --format='%F %a %U:%G' /etc/codex/proxy-upstream.conf
sudo sed -n '1p' /etc/codex/proxy-upstream.conf
```

The first line must be the complete `http` or `https` Responses URL. The second
line must be a non-empty token containing only ASCII letters, numbers, `-`, or
`_`. Do not paste the token into an Issue, terminal transcript, or support
message.

### The proxy does not start

Inspect systemd state and recent logs, then check whether another process owns
the loopback port:

```bash
sudo systemctl status cranesched-codex-proxy.service --no-pager
sudo journalctl -u cranesched-codex-proxy.service -n 100 --no-pager
sudo ss -ltnp '( sport = :617 )'
```

The service requires systemd 247 or newer. The wrapper reports configuration
metadata and format errors to the journal without printing the token.

### Codex does not use the Managed Default

Run the strict configuration doctor and inspect user overrides:

```bash
codex --strict-config doctor --json
test ! -f ~/.codex/config.toml || \
  rg -n '^(model|model_provider|profile)[[:space:]]*=' ~/.codex/config.toml
```

The effective provider should be `cluster_shared` when no user override is
present. Never include credentials when sharing diagnostic output.

### Rotate the endpoint or token

First create a temporary root-only backup, then edit the same file, restore its
required metadata, restart the proxy, and repeat the verification commands.
This manual workflow does not perform automatic rollback.

```bash
backup_path="$(sudo mktemp /etc/codex/.proxy-upstream.conf.XXXXXX)"
sudo install -m 0600 -o root -g root \
  /etc/codex/proxy-upstream.conf "${backup_path}"
sudoedit /etc/codex/proxy-upstream.conf
sudo chown root:root /etc/codex/proxy-upstream.conf
sudo chmod 0600 /etc/codex/proxy-upstream.conf
sudo systemctl restart cranesched-codex-proxy.service
```

After the listener, readiness, and real upstream checks pass, remove the backup:

```bash
sudo rm -f -- "${backup_path}"
unset backup_path
```

If verification fails, restore the backup and restart the service before
investigating the rejected values:

```bash
sudo install -m 0600 -o root -g root \
  "${backup_path}" /etc/codex/proxy-upstream.conf
sudo systemctl restart cranesched-codex-proxy.service
sudo rm -f -- "${backup_path}"
unset backup_path
```

## Remove

An administrator who has only the RPM removes it through DNF:

```bash
sudo dnf remove cranesched-codex
```

Removal stops and disables the unit and removes the manually created wrapper
configuration, Codex binary, system config, and CraneSched Skill. A locally modified
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
release asset, verifies its SHA-256 digest, initializes the pinned
`submodules/CraneSched` checkout when needed, validates
`submodules/CraneSched/docs/skills`, and copies that tree into the RPM staging
area. It then writes a versioned RPM under `dist/`. Downloaded assets are
cached under `dist/cache/`; neither the cache nor RPMs are tracked by Git. Run
`tests/ci.sh` for the complete compatibility suite.

`submodules/codex` is pinned to the source commit matching the packaged Codex
release. `submodules/CraneSched` is pinned independently and is never moved by a
Codex update. CraneSched is the source owner for the Skill; this repository owns
only the packaging and deployment integration.

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

Normal CI uses a fixture configuration and mock upstream. It never receives a
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
