# Release only from committed state

An Upgrade Train uses a dedicated GitHub App to create and automatically merge a tested upgrade PR, then rebuilds and publishes the RPM from the merged commit. Manual asset publication and releases from an uncommitted workflow workspace are excluded so every GitHub Release maps to repository state containing the exact Codex Source Lock and submodule pointer.
