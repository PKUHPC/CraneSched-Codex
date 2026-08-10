# Security Operations

## Reporting

Do not put credentials, private endpoint details, host inventories, or cluster
logs in GitHub Issues, PRs, comments, Actions output, or artifacts. Report a
suspected vulnerability privately to the repository owner or cluster security
contact through the institution's approved channel.

Include the affected CraneSched-Codex RPM version, node role, observed impact,
and reproduction steps with credentials and user data removed.

## Credential exposure

If the shared upstream Key may have been exposed:

1. Revoke or rotate it at the upstream provider.
2. Edit `/etc/codex/proxy-upstream.conf` on every affected node with `sudoedit`.
3. Restore ownership `root:root` and mode `0600`.
4. Restart `cranesched-codex-proxy.service` and verify the real upstream.
5. Inspect provider and host audit records for unauthorized use.

Changing `/etc/codex/config.toml` does not rotate the shared credential.

## Trust model

The root-owned proxy upstream configuration is concealed from ordinary users
by mode `0600`. The root-running wrapper passes the token to the proxy through
stdin; the endpoint, but not the token, appears in the proxy command line. The
loopback proxy is intentionally shared and does not authenticate users, apply
per-user quotas, or provide accounting. Users may replace the Managed Default
with BYOK.

Treat RPM publication, `/etc/codex/proxy-upstream.conf`, write-scoped workflow
tokens, and `main` branch protection as privileged surfaces. Normal CI uses a
fixture configuration and a mock upstream; real Keys are not available to
pull-request or fork-triggered workflows.
