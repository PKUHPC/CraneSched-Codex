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

for name, path in paths.items():
    if not path.is_file():
        raise AssertionError(f"missing {name} workflow: {path.relative_to(repo)}")
    with path.open(encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    if not isinstance(document, dict) or "jobs" not in document:
        raise AssertionError(f"invalid workflow document: {path.relative_to(repo)}")

upgrade = paths["upgrade"].read_text(encoding="utf-8")
assert "workflow_dispatch:" in upgrade
assert "CRANESCHED_CODEX_APP_ID" in upgrade
assert "CRANESCHED_CODEX_APP_PRIVATE_KEY" in upgrade
assert "packaging/update-codex-lock.sh" in upgrade
assert "gh pr create" in upgrade
assert "gh pr merge" in upgrade and "--auto" in upgrade
assert "git add packaging/codex.lock.json ref/codex" in upgrade
assert "git add packaging/codex.lock.json ref/codex ref/CraneSched" not in upgrade

compatibility = paths["compatibility"].read_text(encoding="utf-8")
assert "pull_request:" in compatibility
assert "tests/ci.sh" in compatibility
assert "secrets:" not in compatibility

release = paths["release"].read_text(encoding="utf-8")
assert "pull_request:" in release
assert "types: [closed]" in release
assert "workflow_dispatch:" not in release
assert "github.event.pull_request.merged == true" in release
assert "automation/codex-" in release
assert "github.event.pull_request.merge_commit_sha" in release
assert "gh release create" in release
assert "tests/ci.sh" in release

print("GitHub Actions workflow contract passed.")
