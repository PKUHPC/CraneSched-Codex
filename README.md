# CraneSched-Codex

CraneSched-Codex packages a fixed Codex CLI, a loopback Responses API proxy,
cluster defaults, and CraneSched Admin Skills as one EL9 RPM for shared HPC
nodes. Users receive a working Managed Default without seeing the upstream Key,
while retaining the ability to configure BYOK in their own Codex home.

The repository currently targets x86_64 Rocky Linux, AlmaLinux, and RHEL 9.

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

The proxy listens only on loopback and accepts only the exact Responses path.
Its bearer token is stored at `/etc/codex/proxy-api-key`, mode `0400`, and is
opened by systemd as a service credential. It is never included in the RPM,
repository, process arguments, or process environment.

This is credential concealment, not multi-user authentication. Any local user
can consume the shared upstream allocation. The service applies process,
memory, CPU, file-descriptor, capability, and systemd sandbox limits, but it
does not implement per-user identity, quota, or accounting.

## Clone

The two upstream source references are Git submodules:

```bash
git clone --recurse-submodules \
  https://github.com/Nativu5/CraneSched-Codex.git
cd CraneSched-Codex
```

For an existing clone:

```bash
git submodule update --init --recursive
```

`submodules/codex` is pinned to the source commit matching the packaged Codex release.
`submodules/CraneSched` is pinned independently and is not moved by Codex upgrades.

## Build

On an x86_64 EL9 build host, install the build tools:

```bash
sudo dnf install rpm-build rpm-build-libs rpm cpio curl jq tar gzip git ripgrep
```

Build the locked RPM:

```bash
./cranesched-codex.sh build
```

The build reads `packaging/codex.lock.json`, downloads the named official Codex
release asset, verifies its SHA-256 digest, runs the compatibility contract,
and writes:

```text
dist/cranesched-codex-0.145.0-1.el9.x86_64.rpm
```

Downloaded assets are cached under `dist/cache/`. Neither the cache nor RPMs
are tracked by Git.

## Install

DNF is the only supported package installation path. An administrator who has
only the RPM can install all software and runtime dependencies directly:

```bash
sudo dnf install ./cranesched-codex-0.145.0-1.el9.x86_64.rpm
```

The RPM requires `bubblewrap`, `ripgrep`, and the EL9 `python3-tomli` package.
Ensure those packages are available from the node's enabled repositories or
internal mirror; DNF resolves them automatically.

Installation deliberately leaves the service stopped because the Key is not in
the package. Provision it from a root-readable Codex provider configuration:

```bash
sudo cranesched-codex-provision \
  --source-config /root/.codex/config.toml \
  --verify-upstream
```

The source configuration must contain provider `pku`, the expected PKU endpoint,
and its `experimental_bearer_token`. The provisioner validates ownership and
mode, extracts only that provider, checks the endpoint, rotates the root-only
credential atomically, enables the service, and optionally sends one minimal
real request. It restores the prior credential and service state on failure.

For an offline rollout, omit `--verify-upstream`, but perform a real verification
before declaring the node ready.

The repository manager is a convenience wrapper around the same DNF and
provisioner operations:

```bash
sudo ./cranesched-codex.sh install \
  --rpm dist/cranesched-codex-0.145.0-1.el9.x86_64.rpm \
  --source-config /root/.codex/config.toml
./cranesched-codex.sh status
```

It is not packaged and is not a second installer.

## Remove

An administrator who has only the RPM uses DNF:

```bash
sudo dnf remove cranesched-codex
```

The package stops and disables the unit and removes the generated credential,
Codex binary, system config, and Admin Skills. A locally modified
`/etc/codex/config.toml` may remain as an RPM `.rpmsave` file.

The repository manager adds only an explicit confirmation:

```bash
sudo ./cranesched-codex.sh uninstall --yes
```

## User experience and BYOK

The RPM installs `/etc/codex/config.toml` as a low-priority system default. It
selects provider `cluster_shared`, whose base URL is the loopback proxy and
which does not require OpenAI authentication.

A user can override the model/provider in `~/.codex/config.toml`, a profile, or
CLI `-c` options. The system default is not enforced and the proxy does not
intercept traffic sent to a user-selected endpoint.

Admin Skills are installed under `/etc/codex/skills` and discovered with Admin
scope. They are enabled by default. A user can disable an individual Skill:

```toml
[[skills.config]]
name = "cranesched-skill"
enabled = false
```

## Package contents

Important installed paths:

```text
/usr/bin/codex
/usr/libexec/cranesched-codex/codex
/usr/libexec/cranesched-codex/cranesched-codex-proxy
/usr/sbin/cranesched-codex-provision
/usr/lib/systemd/system/cranesched-codex-proxy.service
/etc/codex/config.toml
/etc/codex/skills/
/etc/codex/proxy-api-key
```

`/usr/bin/codex` is a symlink to the byte-for-byte official binary under
libexec. The packaged `PROVENANCE` file records its source tag, commit, asset
URL, asset digest, architecture, and extracted binary digest.

## Tests

Run the complete local suite:

```bash
tests/ci.sh
```

The suite covers the Codex Source Lock and artifact boundary, Codex CLI and
app-server compatibility, proxy behavior, Admin Skills, and the built RPM.

Two root-only integration modes exercise behavior that a normal unit test
cannot observe:

```bash
SYSTEM_CONFIG_RUNTIME_TEST=1 proxy/tests/test.sh
SYSTEMD_RUNTIME_TEST=1 proxy/tests/test.sh
sudo tests/test-installed-node.sh
```

The first mounts a private test `/etc` and verifies that the Skill is discovered
with Admin scope and can be disabled by a user. The second starts a temporary
systemd unit against a mock upstream, verifies the credential-to-stdin path,
DynamicUser execution, and the SELinux domain when enforcing, then removes all
temporary state.

The installed-node contract runs after provisioning on a canary. It verifies
the real unit, credential visibility, process exposure, loopback listener,
strict system config, and Admin Skill discovery without printing the Key.

No normal CI job receives a real upstream Key. A real request is an explicit,
administrator-controlled deployment test only.

Compatibility cancels an older in-progress run when the same PR receives a
new head. A Ready PR that changes only the explicit documentation allowlist
still reports the required `test` result but skips submodule initialization and
the privileged EL9 container. Mixed, empty, or unrecognized diffs run the full
suite; `README.md` is not skipped because it is included in the RPM payload.

## Codex upgrades

The `Codex Source Lock` is the sole packaging version source. An administrator
starts an Upgrade Train with the `Upgrade Codex` workflow and supplies the new
Codex version and RPM release.

The workflow:

1. resolves `rust-v<version>` and the official x86_64 musl release asset;
2. records the source commit, asset URL, and published digest in the lock;
3. moves only the Codex submodule;
4. downloads and validates the new binary;
5. builds and tests the RPM without a real Key;
6. uses the ephemeral repository `GITHUB_TOKEN` to create a Draft upgrade PR;
7. waits for an administrator to review the diff and mark the PR ready;
8. runs the pull-request Compatibility checks after that human event;
9. requires administrator approval and a manual squash merge; and
10. publishes the RPM and SHA-256 file from the merged commit.

The repository Actions settings must allow `GITHUB_TOKEN` to create pull
requests. The Upgrade workflow grants it only `Contents: write` and
`Pull requests: write`; no long-lived release credential or GitHub App secret is
required. Because GitHub suppresses ordinary workflow events caused by
`GITHUB_TOKEN`, the generated PR remains Draft until an administrator clicks
**Ready for review**. That human event starts the first Compatibility run.

`main` must require the Compatibility `test` check and one approving review,
including for administrators. The repository must allow squash merges and
disable merge commits and rebase merges. The Upgrade workflow never merges its
own PR. Releases are created only after an administrator squash-merges a
reviewed, green upgrade PR, and are always rebuilt from the resulting committed
state. The Release workflow verifies the squash-only repository policy again
before building or publishing an RPM.
