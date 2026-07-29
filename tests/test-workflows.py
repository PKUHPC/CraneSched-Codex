#!/usr/bin/env python3
from pathlib import Path

import yaml


repo = Path(__file__).resolve().parent.parent
workflow_dir = repo / ".github" / "workflows"
paths = {
    "upgrade": workflow_dir / "upgrade-codex.yml",
    "compatibility": workflow_dir / "compatibility.yml",
    "release": workflow_dir / "release-rpm.yml",
}


def load_workflow(path: Path) -> dict:
    if not path.is_file():
        raise AssertionError(f"missing workflow: {path.relative_to(repo)}")
    with path.open(encoding="utf-8") as handle:
        document = yaml.load(handle, Loader=yaml.BaseLoader)
    if not isinstance(document, dict) or not isinstance(document.get("jobs"), dict):
        raise AssertionError(f"invalid workflow document: {path.relative_to(repo)}")
    return document


def steps(document: dict, job_name: str) -> list:
    job = document["jobs"][job_name]
    assert isinstance(job, dict) and isinstance(job.get("steps"), list)
    return job["steps"]


def run_script(document: dict, job_name: str) -> str:
    return "\n".join(
        step["run"]
        for step in steps(document, job_name)
        if isinstance(step, dict) and isinstance(step.get("run"), str)
    )


def contains_string(value, fragment: str) -> bool:
    if isinstance(value, str):
        return fragment in value
    if isinstance(value, dict):
        return any(contains_string(item, fragment) for item in value.values())
    if isinstance(value, list):
        return any(contains_string(item, fragment) for item in value)
    return False


workflows = {name: load_workflow(path) for name, path in paths.items()}

upgrade = workflows["upgrade"]
assert "workflow_dispatch" in upgrade["on"]
assert upgrade["permissions"] == {
    "contents": "write",
    "pull-requests": "write",
}
assert not contains_string(upgrade, "actions/create-github-app-token")
assert not contains_string(upgrade, "CRANESCHED_CODEX_APP")
assert not contains_string(upgrade, "secrets.")
assert contains_string(upgrade, "github.token")
upgrade_steps = steps(upgrade, "prepare-upgrade")
checkout_step = next(
    step for step in upgrade_steps if step.get("uses") == "actions/checkout@v4"
)
assert checkout_step["with"]["persist-credentials"] == "false"
upgrade_run = run_script(upgrade, "prepare-upgrade")
assert "packaging/update-codex-lock.sh" in upgrade_run
assert "gh pr create" in upgrade_run
assert "gh auth git-credential" in upgrade_run
assert "--draft" in upgrade_run
assert "gh pr merge" not in upgrade_run and "--auto" not in upgrade_run
assert "github-actions[bot]" in upgrade_run
assert "git add packaging/codex.lock.json ref/codex" in upgrade_run
assert "git add packaging/codex.lock.json ref/codex ref/CraneSched" not in upgrade_run
assert not contains_string(upgrade, "prerelease")

compatibility = workflows["compatibility"]
assert compatibility["on"]["pull_request"]["branches"] == ["main"]
assert compatibility["on"]["pull_request"]["types"] == [
    "opened",
    "synchronize",
    "reopened",
    "ready_for_review",
]
assert compatibility["jobs"]["test"]["if"] == (
    "github.event.pull_request.draft == false"
)
assert ".github/scripts/run-el9-ci.sh" in run_script(compatibility, "test")
assert not contains_string(compatibility, "secrets.")

release = workflows["release"]
assert release["on"]["pull_request"]["types"] == ["closed"]
assert "workflow_dispatch" not in release["on"]
release_job = release["jobs"]["release"]
assert "github.event.pull_request.merged == true" in release_job["if"]
assert "automation/codex-" in release_job["if"]
assert contains_string(release, "github.event.pull_request.merge_commit_sha")
release_run = run_script(release, "release")
assert ".allow_squash_merge" in release_run
assert ".allow_merge_commit | not" in release_run
assert ".allow_rebase_merge | not" in release_run
assert ".github/scripts/run-el9-ci.sh" in release_run
assert "gh release create" in release_run
assert 'cd dist && sha256sum "${rpm_name}"' in release_run
assert not contains_string(release, "prerelease")

print("GitHub Actions workflow contract passed.")
