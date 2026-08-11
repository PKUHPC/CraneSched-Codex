# Prefer high-value tests and fast feedback

Tests exist to protect behavior and material risk boundaries, not to mirror the
current implementation. Exact workflow-YAML assertions and repository-path
inventories created maintenance work while providing little confidence: GitHub
interprets the workflows directly, and the build naturally fails when required
packaging inputs are absent.

The repository therefore removes `tests/test-workflows.py` and
`tests/test-repository-contract.sh`. Retained tests cover the Codex Source Lock
and downloaded artifact, supported Codex CLI/app-server interfaces, credential
and proxy behavior, the CraneSched Skill, RPM payload/install semantics, systemd, and
installed-node behavior. A new test must name the meaningful regression or
high-risk boundary it catches and explain why existing validation is
insufficient.

The main CI entry point also avoids duplicate checks. Codex compatibility runs
once in the full Compatibility suite, independently of the reusable RPM build
path, and Skill validation is owned by packaging. Workflow changes use review
and `actionlint` rather than a second hand-written model of the YAML.

Compatibility keeps its required `test` result for every Ready PR, but it does
not initialize submodules or start the privileged EL9 container when every
changed path belongs to an explicit documentation-only allowlist. Empty,
mixed, and unrecognized diffs run the full suite. PR-scoped concurrency also
cancels an in-progress run when a newer head supersedes it. The focused scope
test protects this fail-safe boundary rather than mirroring workflow YAML.

The official Codex binary is large, so RPM's default zstd level 19 dominated CI
runtime without changing package semantics. RPM payloads use zstd level 7 to
trade a modest increase in artifact size for substantially faster build and
review feedback. Digest, payload, install-root, and systemd validation remain
unchanged.

This decision reduces test count and CI latency, but it raises the bar for
future tests: coverage growth alone is not a goal, and implementation-coupled
tests require a concrete operator or user failure story.
