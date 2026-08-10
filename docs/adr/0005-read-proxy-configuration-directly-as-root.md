# Read proxy configuration directly as root

CraneSched-Codex stores the administrator-selected Responses endpoint and
bearer token in the fixed `/etc/codex/proxy-upstream.conf` file, owned by
`root:root` with mode `0600`. The static wrapper reads this file directly,
passes the endpoint to the bundled Proxy as an argument, and passes the token
through stdin; a provisioner and systemd credential transfer were rejected
because deployment administrators are already root and the project does not
need migration compatibility for early nodes.

## Consequences

The wrapper and the Proxy run as root, while the static systemd unit retains
the applicable process, filesystem, capability, network-family, and resource
restrictions. The endpoint is locally visible in the Proxy command line, but
the token is absent from the RPM payload, repository, arguments, environment,
and logs; manual configuration, verification, rotation, rollback, and removal
are administrator operations documented with the package.
