# Contributing

CraneSched-Codex changes should keep the RPM as the only deployment path and
preserve the separation between the Managed Default and user BYOK.

## Development setup

Clone both upstream references and read the project context before changing
packaging or runtime behavior:

```bash
git submodule update --init --recursive
```

Relevant project decisions live in `CONTEXT.md` and `docs/adr/`.

## Source updates

Do not edit `packaging/codex.lock.json` or move `ref/codex` independently. Use:

```bash
packaging/update-codex-lock.sh <version> <rpm-release>
```

The lock and submodule pointer must be reviewed and committed together.
Updating Codex must not move `ref/CraneSched`.

Admin Skill changes are ordinary reviewed source changes under `skills/`.
The future Agent-assisted CraneSched documentation synchronization workflow is
not yet implemented.

## Code style

- Shell scripts use Bash with `set -euo pipefail`, quoted expansions, explicit
  cleanup traps, and actionable failure messages.
- The small credential wrapper remains POSIX shell.
- Python uses the standard library unless an external dependency materially
  simplifies a public interface.
- Structured files are read with structured parsers such as `jq` or Python
  JSON/YAML libraries, not line-oriented string extraction.
- Never print, log, archive, or place a real credential in argv or environment.

## Tests

Tests observe the supported seams: Codex CLI/app-server, the Responses proxy,
RPM/DNF, and systemd. Avoid tests coupled only to helper implementation.

Run the complete local suite with:

```bash
tests/ci.sh
```

Root-only system config and systemd checks are documented in `README.md` and
must pass on an EL9 integration node before a runtime change is merged.

Pull-request CI must use only fixture credentials and a mock upstream. Never
add an administrator Key to repository or pull-request Actions secrets.

## Pull requests

Reference the originating issue, describe observable behavior changes, and
include the exact local and integration checks run. Codex upgrade PRs are
created by the Upgrade Train and should contain only the Codex Source Lock and
Codex submodule pointer.
