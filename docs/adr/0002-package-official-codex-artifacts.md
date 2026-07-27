# Package a locked official Codex artifact

CraneSched-Codex packages the official target-specific Codex release binary and verifies its published digest instead of building Codex from source. The Codex submodule is pinned to the matching tag commit for audit and compatibility investigation, while the Codex Source Lock is the packaging source of truth; this keeps builds reproducible without turning a large Rust build into part of every RPM release.
