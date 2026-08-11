# Source CraneSched Skills from the upstream submodule

CraneSched-Codex no longer owns a second copy of the CraneSched user Skill.
The source of truth is `docs/skills/` in the pinned
`submodules/CraneSched` checkout. The CraneSched repository reviews the Skill
content and excludes this source tree from its MkDocs site with `exclude_docs`,
because the package is consumed by Codex rather than served as CraneSched web
documentation.

## Packaging contract

The RPM build runs `packaging/stage-cranesched-skills.sh`. The helper
initializes the CraneSched submodule when a clean checkout has not cloned it,
checks that its HEAD matches the parent repository's gitlink, rejects
uncommitted submodule changes, validates the source tree, and copies it into
RPM staging. The build therefore packages the reviewed CraneSched commit while
avoiding a local duplicate or an unpinned fetch from `master`.

The parent gitlink is the version lock for Skills. Updating Skill content is a
two-repository change: merge the CraneSched source PR, update the CraneSched
gitlink in this repository, then rebuild and validate the RPM. A release is
still produced only from a committed CraneSched-Codex state.

## User scope

The Skill is written for all CraneSched users and support operators; it is not
an administrator-only manual. Codex reports files under `/etc/codex/skills`
with `admin` scope because that is the system installation location. This
loader classification does not grant or remove CraneSched permissions, and
users may disable the Skill by name. Actual access control remains the
responsibility of the CraneSched deployment.

## Consequences

CraneSched contributors edit one canonical Skill tree, and the two repositories
have an explicit review boundary: CraneSched owns content while
CraneSched-Codex owns packaging and deployment. A build requires the pinned
CraneSched commit and its source tree, so an uninitialized or dirty submodule
fails with an actionable error instead of silently packaging stale content.
The MkDocs site does not expose the Skill as a served page, while RPM users
receive the same validated files under `/etc/codex/skills`.
