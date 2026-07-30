# Codex Upgrade Train

The Upgrade Train is the only Codex version and RPM release path.

## Source rules

- The Codex Source Lock is the sole packaging version source. Never edit its
  version, source identity, artifact, digest, or RPM release manually. Use
  `packaging/update-codex-lock.sh <version> <rpm-release>`.
- A version update changes only `packaging/codex.lock.json` and `submodules/codex`.
  Review and commit them together. A schema-only lock change does not move
  `submodules/codex`, and an upgrade never moves `submodules/CraneSched`.

## Flow

1. An administrator manually dispatches `Upgrade Codex` with the Codex version
   and RPM release.
2. The workflow resolves the official source and x86_64 musl artifact, updates
   the lock and submodule, then verifies their identity and the artifact digest.
   It does not build an RPM.
3. The ephemeral `GITHUB_TOKEN` pushes an `automation/codex-*` branch and
   creates a `codex-upgrade` Draft PR containing only the lock and `submodules/codex`.
   It never enables auto-merge or merges the PR.
4. GitHub suppresses downstream events created by `GITHUB_TOKEN`, so an
   administrator reviews the Draft and clicks **Ready for review**. That human
   event starts the single full EL9 Compatibility suite, including the RPM build,
   proxy and runtime checks, RPM payload checks, and a DNF transaction.
5. `main` requires the Compatibility `test` check and one human approval,
   including for administrators. Only squash merges are enabled.
6. After a human squash merge, the guarded Release workflow verifies the
   same-repository branch and label plus the squash-only repository policy. It
   rebuilds from the merged commit, validates the release RPM payload and DNF
   install/remove transaction, and publishes the RPM. It does not repeat proxy
   or unit tests already completed by Compatibility.

The Upgrade, Compatibility, and Release workflows share an artifact cache keyed
by the complete Source Lock. Every use still verifies the cached archive against
the Source Lock SHA-256 digest before extraction.

Never publish a manual Release or release an uncommitted workflow workspace.
Every Release maps to reviewed repository state containing the exact Source
Lock and submodule pointer.
