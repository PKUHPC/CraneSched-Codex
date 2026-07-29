# Development Workflow

## Before implementation

- Create or claim a fully specified GitHub Issue with scope, acceptance
  criteria, and exclusions. Assign it and apply the appropriate triage label.
- Read `CONTEXT.md` and relevant decisions under `docs/adr/`.
- Initialize upstream references with `git submodule update --init --recursive`
  before packaging or runtime work.
- Create a dedicated branch from the intended base and preserve unrelated work.

Admin Skill changes are ordinary reviewed changes under `skills/`. The future
Agent-assisted CraneSched documentation synchronization workflow is not
implemented.

## Implementation rules

- Shell scripts use Bash with `set -euo pipefail`, quoted expansions, cleanup
  traps, and actionable errors. The credential wrapper remains POSIX shell.
- Python uses the standard library unless a dependency materially simplifies a
  public interface.
- Read structured files with structured parsers rather than line-oriented text
  extraction.
- Short-lived platform tokens may use supported secret environment variables
  for one least-privilege step; never print or persist them.

## Semantic history

Commit messages and PR titles must follow Conventional Commits:

```text
<type>[optional scope][!]: <description>
```

Use lowercase `type` and `scope`, an imperative description, and no trailing
period. The supported types are `feat`, `fix`, `docs`, `refactor`, `perf`,
`test`, `build`, `ci`, `chore`, and `revert`. Use a scope when it adds useful
context, such as `proxy`, `rpm`, `upgrade`, or `agents`.

Use `!` before the colon and a `BREAKING CHANGE:` footer for an incompatible
change. Keep each commit to one logical change and reference its Issue in the
commit body or footer. Because the repository squash-merges PRs, the semantic
PR title becomes the permanent commit subject on the default branch.

Examples:

```text
docs(agents): add semantic contribution rules
fix(proxy): preserve the BYOK provider override
ci(upgrade)!: require a new Source Lock field

BREAKING CHANGE: Source Locks without schema_version are rejected.
```

## Test policy

Tests protect supported seams: Codex CLI/app-server, the Responses proxy,
Source Lock and artifact integrity, RPM/DNF, and systemd. Prefer observable
behavior and high-risk boundaries over assertions about repository layout,
workflow text, or private helper structure.

Every proposed test must identify the meaningful regression it catches and why
a cheaper existing check does not cover it. Do not add a test whose main effect
is increasing maintenance cost or making safe refactoring harder.

Run `tests/ci.sh`. Runtime or packaging changes also require the documented
EL9/root integration modes and canary installed-node check. Pull-request CI uses
fixture credentials and a mock upstream; it never receives a real administrator
Key.

## Issue to merge

1. Implement only the Issue scope and use semantic commits that reference the
   Issue.
2. Run proportionate tests and record the exact commands and results.
3. Push a Draft PR with a semantic title that references the Issue and explains
   observable behavior.
4. Pin the PR base and run two independent SubAgents in parallel:
   - **Standards** checks repository rules and the configured smell baseline.
   - **Spec** checks the diff against the Issue or PRD for missing, incorrect,
     or out-of-scope behavior.
5. Post both reports to the PR under separate `Standards` and `Spec` headings,
   with finding counts and validation evidence. Do not merge or rerank the axes.
6. Resolve actionable findings, rerun tests, commit and push, then request
   independent re-review. Comment with fixes and residual risks. Repeat until
   neither axis has an actionable finding.
7. Move the Issue to `ready-for-human` and leave the clean Draft PR for the
   maintainer. Require green CI and configured approval before a human squash
   merge. Automation must not approve or merge its own PR.

Keep the Issue open while post-merge configuration or verification remains.
Close it only after every acceptance criterion is verified.
