# CraneSched-Codex

CraneSched-Codex packages a shared-node Codex experience for CraneSched HPC:

- a pinned native Codex CLI;
- a root-managed loopback Responses API proxy;
- a low-priority system configuration with a Managed Default;
- the CraneSched user Skill, sourced from the pinned CraneSched submodule.

The project delivers these components as one RPM for x86_64 EL9 systems. DNF
is the supported installation and removal path. It does not provide user
authentication, per-user quotas, or accounting. Users can replace the Managed
Default with their own BYOK provider.

## Runtime boundary

```text
user Codex -> 127.0.0.1:617/v1/responses
           -> cranesched-codex-proxy.service
           -> root-only /etc/codex/proxy-upstream.conf
           -> administrator-selected Responses endpoint
```

The proxy holds the upstream bearer token. The token is never packaged or
placed in Codex configuration, process arguments, process environment, logs,
Issues, or pull requests. The loopback proxy is a shared service; concealing a
credential is not the same as enforcing authorization or usage policy.

## Install

Download the RPM from the [latest GitHub Release][release] and install it on
an x86_64 EL9 node:

```bash
sudo dnf install ./cranesched-codex-*.el9.x86_64.rpm
```

The package does not contain an endpoint or token and does not start the proxy
until the administrator creates its root-only configuration. Follow the
[Installation and configuration guide][install-guide]
for first setup, verification, upgrades, rotation, BYOK, troubleshooting, and
removal. The same guide and the architecture reference are installed under
`/usr/share/doc/cranesched-codex/` for nodes without repository access.

## Documentation

Start with the [documentation index][docs-index]:

- [Installation and configuration][install-guide] -
  the authoritative node operations guide.
- [Architecture and security][architecture-guide] - runtime
  boundaries, credential handling, Skill ownership, and non-goals.
- [ADRs][adr-index] - decisions that constrain implementation.
- [Development workflow][development-workflow] - contribution,
  review, and validation rules.
- [Upgrade Train][upgrade-train] - the only Codex/RPM release
  path.

The CraneSched Skill source is maintained in
[`PKUHPC/CraneSched/docs/skills/`][skill-source] and is excluded from the
CraneSched MkDocs site. This repository owns its packaging and deployment
integration, not a second copy of the Skill.

## Build and test

Builds use the Codex Source Lock and the pinned CraneSched submodule:

```bash
git clone --recurse-submodules https://github.com/Nativu5/CraneSched-Codex.git
cd CraneSched-Codex
./cranesched-codex.sh build
tests/ci.sh
```

The build validates and stages `submodules/CraneSched/docs/skills/` into the
RPM. Runtime and packaging changes also require the root-only checks described
in the development workflow.

## Project boundaries

CraneSched-Codex is intentionally an early-stage, single-RPM deployment:

- the system config is a default and remains user-overridable;
- the proxy listens on loopback and accepts only the Responses path;
- the administrator changes only the fixed root-owned upstream configuration;
- CraneSched controls the meaning and permissions of the user-facing Skill.

[release]: https://github.com/Nativu5/CraneSched-Codex/releases/latest
[docs-index]: https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/README.md
[install-guide]: https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/installation-and-configuration.md
[architecture-guide]: https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/architecture-and-security.md
[adr-index]: https://github.com/Nativu5/CraneSched-Codex/tree/main/docs/adr
[development-workflow]: https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/agents/development-workflow.md
[upgrade-train]: https://github.com/Nativu5/CraneSched-Codex/blob/main/docs/agents/upgrade-train.md
[skill-source]: https://github.com/PKUHPC/CraneSched/tree/master/docs/skills
