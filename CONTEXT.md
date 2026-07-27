# CraneSched-Codex

CraneSched-Codex packages a cluster-ready Codex experience for CraneSched HPC users while keeping cluster administration and individual user customization distinct.

## Language

**Managed Default**:
The administrator-provided Codex endpoint and credential path available without per-user setup.
_Avoid_: Forced configuration, mandatory endpoint

**BYOK**:
A user-supplied provider configuration and credential that replaces the Managed Default for that user.
_Avoid_: Multi-user authentication, user provisioning

**Admin Skill**:
A cluster-maintained Skill installed as a default source of CraneSched operational knowledge for every user.
_Avoid_: Forced Skill, bundled prompt

**Codex Source Lock**:
The auditable record that binds one packaged Codex version to its upstream tag, source commit, release asset, architecture, and digest.
_Avoid_: Version file, latest Codex

**Upgrade Train**:
The manually initiated, automatically verified path that updates the Codex Source Lock and publishes the matching RPM from committed repository state.
_Avoid_: Manual release, nightly build
