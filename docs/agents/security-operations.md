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
2. Update the root-readable source configuration.
3. Run `cranesched-codex-provision` on every affected node.
4. Verify the real upstream on each affected node.
5. Inspect provider and host audit records for unauthorized use.

Changing only `/etc/codex/config.toml` does not rotate the credential.

## Trust model

The root-owned credential is concealed from ordinary users through systemd
credential loading and stdin. The loopback proxy is intentionally shared and
does not authenticate users, apply per-user quotas, or provide accounting.
Users may replace the Managed Default with BYOK.

Treat RPM publication, system configuration, provisioner source configuration,
write-scoped workflow tokens, and `main` branch protection as privileged
surfaces. Normal CI uses fixture credentials and a mock upstream; real Keys are
not available to pull-request or fork-triggered workflows.
