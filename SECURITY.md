# Security Policy

## Reporting

Do not publish credentials, private endpoint details, host inventories, or
cluster logs in a GitHub issue. Report a suspected vulnerability privately to
the repository owner or the cluster security contact through the institution's
approved channel.

Include the affected CraneSched-Codex RPM version, node role, observed impact,
and reproduction steps with all credentials and user data removed.

## Credential exposure

If the shared upstream Key may have been exposed:

1. revoke or rotate it at the upstream provider;
2. update the root-readable source configuration;
3. run `cranesched-codex-provision` on every affected node;
4. verify the real upstream on each node; and
5. inspect provider and host audit records for unauthorized use.

Changing only `/etc/codex/config.toml` does not rotate the credential.

## Trust model

The root-owned credential is concealed from ordinary users through systemd
credential loading and stdin. The local proxy is intentionally shared and does
not authenticate users, apply per-user quotas, or provide accounting.

Users control their own Codex configuration and can select BYOK. Administrators
must treat RPM publication, system configuration, the provisioner source
configuration, the Upgrade workflow's write-scoped `GITHUB_TOKEN`, and `main`
branch protection as privileged surfaces.

Normal compatibility CI uses a dummy token and local mock upstream. Real Keys
must not be available to pull-request or fork-triggered workflows.
