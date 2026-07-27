# Domain Docs

How the engineering skills should consume this repository's domain documentation when exploring the codebase.

## Before exploring, read these

- `CONTEXT.md` at the repository root, or
- `CONTEXT-MAP.md` at the repository root if it exists; read each linked context relevant to the topic.
- ADRs under `docs/adr/` that touch the area being changed.

If any of these files do not exist, proceed silently. `/domain-modeling` creates them lazily when terms or decisions are resolved.

## File structure

This is a single-context repository:

```text
/
|-- CONTEXT.md
|-- docs/adr/
|   |-- 0001-example-decision.md
|   `-- 0002-another-decision.md
`-- ...
```

## Use the glossary's vocabulary

When output names a domain concept, use the term defined in `CONTEXT.md`. Do not drift to synonyms the glossary explicitly avoids.

If a required concept is absent, reconsider whether it belongs to the project vocabulary or note the gap for `/domain-modeling`.

## Flag ADR conflicts

Surface conflicts with existing ADRs explicitly rather than silently overriding them.
