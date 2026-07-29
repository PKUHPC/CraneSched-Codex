# CraneSched-Codex Agent Guide

`AGENTS.md` is the operational entry point for repository work. `CLAUDE.md`
must remain a symlink to this file.

## Core rules

- Track work in GitHub Issues using `docs/agents/issue-tracker.md` and
  `docs/agents/triage-labels.md`. Read `CONTEXT.md` and relevant ADRs before
  changing behavior.
- Keep the RPM as the only deployment path and preserve the separation between
  the Managed Default and user BYOK.
- The Codex Source Lock is the packaging version source. Use
  `packaging/update-codex-lock.sh`; never move `submodules/CraneSched` during a Codex
  update.
- Never expose a real Codex or upstream credential in source, argv, environment,
  logs, Issues, PRs, Actions output, or artifacts. Follow
  `docs/agents/security-operations.md` for incidents and trust boundaries.
- Every new test must justify its quality by protecting observable behavior,
  external compatibility, or a concrete high-risk boundary. Do not test file
  layout, exact workflow text, or helper implementation without a failure mode
  that matters to users or operators. See ADR 0004.
- Use Conventional Commits for commit messages and PR titles. See
  `docs/agents/development-workflow.md` for the format and allowed types.

## Core workflows

- **Codex update:** manual dispatch -> verified Draft PR -> human Ready event ->
  Compatibility CI -> human approval and squash merge -> committed-state RPM
  Release. See `docs/agents/upgrade-train.md`.
- **Development:** Issue -> scoped branch -> validation -> Draft PR -> independent
  Standards and Spec SubAgent reviews -> automatic PR comments and fix/re-review
  iterations -> human gate. See `docs/agents/development-workflow.md`.

## References

- Domain context: `docs/agents/domain.md`
- Development and test policy: `docs/agents/development-workflow.md`
- Upgrade Train: `docs/agents/upgrade-train.md`
- Security operations: `docs/agents/security-operations.md`
