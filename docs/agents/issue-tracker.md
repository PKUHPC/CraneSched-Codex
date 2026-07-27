# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** Set this to `yes` if the repo later treats external PRs as feature requests.

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>`.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`, keeping only `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` author associations.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so resolve a bare `#42` with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The map is a single issue with child issues as tickets.

- **Map**: create one issue labelled `wayfinder:map`, holding Notes, Decisions-so-far, and Fog.
- **Child ticket**: link an issue to the map as a GitHub sub-issue. If sub-issues are unavailable, add it to a task list in the map and put `Part of #<map>` at the top of the child body.
- **Blocking**: use GitHub native issue dependencies. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where the database ID comes from `gh api repos/<owner>/<repo>/issues/<n> --jq .id`.
- **Frontier query**: select the first unassigned open child whose blockers are all closed.
- **Claim**: `gh issue edit <n> --add-assignee @me`.
- **Resolve**: comment with the answer, close the child, and append its context pointer to the map.
