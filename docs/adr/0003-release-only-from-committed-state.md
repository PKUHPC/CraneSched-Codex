# Release only from committed state

An Upgrade Train uses the ephemeral repository `GITHUB_TOKEN` to create a Draft
upgrade PR. An administrator reviews the change, marks the PR ready to start
Compatibility CI, approves it, and squash-merges it after the required check
passes. The Release workflow then rebuilds and publishes the RPM from the merged
commit. Manual asset publication, workflow-initiated merging, and releases from
an uncommitted workflow workspace are excluded so every GitHub Release maps to
reviewed repository state containing the exact Codex Source Lock and submodule
pointer.
