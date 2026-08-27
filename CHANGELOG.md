# Changelog

Releases are dated, not numbered: the git tag is `YYYYMMDD` — or `YYYYMMDD.N` for a second release
on the same day — and the image carries that tag verbatim alongside `:stable`. There is no semantic
version, because nothing here has an API to break; what matters about a release is when it was cut
and what moved.

Each entry names the image tags it published. `:stable` and `:latest` move; the dated and
`sha-` tags never do, so those are what to pin and roll back to.

## 20260827.1

Published `:20260827.1`, `:stable`, `:20260827.1-slim`, `:stable-slim`.

The image splits into two variants built from one Dockerfile, and **the unsuffixed tags change
meaning**: they are now a probe carrying network diagnostics tools. The agent-only image continues
unchanged under `-slim`.

### Added

- A `tools` build target adding ~25 network diagnostics tools, so MeshCentral's remote terminal
  lands somewhere you can actually work from: `ping` `arping` `fping` `traceroute` `tracepath`
  `mtr`, `dig` `nslookup` `host`, `ip` `ss` `ethtool` `lsof` `ps`, `nc` `nmap` `iperf3` `socat`
  `tcpdump`, `openssl` `smbclient` `ldapsearch` `whois`, `jq` `less` `vi`.
- `tools-smoke.sh`, which runs every one of those tools and fails if one is missing or cannot
  start. CI runs it against the built image before publishing, and it ships inside the image:
  `docker run --rm --entrypoint /tools-smoke.sh <image>`.
- `docker-compose.slim.sample.yml`, the agent-only deployment on `:stable-slim`.
- `.gitattributes` pinning the working tree to LF.

### Changed

- `:stable`, `:latest`, the dated tags and the `sha-` tags now point at the probe. The agent-only
  image moves to `:stable-slim`, `:latest-slim`, `:<date>-slim` and `:sha-<commit>-slim`.
- `docker-compose.sample.yml` deploys the probe, with `cap_add: [NET_ADMIN]` for `tcpdump` and a
  commented `network_mode: host` for watching the host's own interfaces.
- Release tags are dates rather than semantic versions, and the workflow now takes the image tag
  from the git tag name instead of the build date. The two were previously independent: re-running
  an old release's workflow would have stamped today's date onto an old commit, and two releases in
  one day would have overwritten each other. A tag on `main` that is not a date now fails the build
  rather than publishing under a surprising name.
- `dnsutils` is `bind9-dnsutils` — in Debian 13 the old name is a transitional package that
  installs cleanly and leaves no `dig` behind. This is the class of failure `tools-smoke.sh` exists
  to catch.

### Fixed

- A Windows clone produced a broken image. With `core.autocrlf=true` and no `.gitattributes`,
  `entrypoint.sh` was checked out as CRLF, `docker build` baked `#!/bin/sh\r` into the image, and
  the container died at start with `exec /entrypoint.sh: no such file or directory` — naming the
  file it had just failed to run.

### Upgrading

Deployments following `:stable` move from the agent to the probe on their next pull, and become
about 120 MB larger. Nothing else changes: both variants install the agent identically and share
the same volume contract, so the device keeps its identity across the switch. To stay on the agent
alone, repin to `:stable-slim`.

## 20260827

Published `:20260827`, `:stable`. Tagged `v1.0.0` — the only semantic version this project had,
before the dated scheme above replaced it.

First release of the rebuilt image.

### Added

- Debian 13 (trixie) base with `wget`, `curl` and `ca-certificates`.
- `entrypoint.sh`: installs the MeshCentral agent from your own server on first start, keeps it in
  the `/meshagent` volume, and `exec`s it as PID 1 so `docker stop` reaches it directly. Every
  failure path names its cause — a missing variable, an unreachable server, an installer that
  produced no binary.
- A warning when the volume survived but `meshagent.db` or `meshagent.msh` did not, rather than
  silently re-registering as a new device.
- `docker-compose.sample.yml`, MIT licence, and a build that lints the entrypoint before
  publishing anything.
