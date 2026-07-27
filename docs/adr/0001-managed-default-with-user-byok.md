# Provide a Managed Default while preserving BYOK

CraneSched-Codex provides a cluster endpoint and root-managed credential as the default, but it does not enforce that provider on users. Users may replace the Managed Default with BYOK configuration because the goal is zero-setup access and credential concealment, not multi-user authentication or policy enforcement.
