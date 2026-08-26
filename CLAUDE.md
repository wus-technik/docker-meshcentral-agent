# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A single-purpose Docker image that runs a [MeshCentral](https://meshcentral.com/) agent in a
container. There is no application source code; the deliverable is:

- `Dockerfile` — `debian:trixie-slim` plus `wget`/`curl`/`ca-certificates`, `WORKDIR /meshagent`,
  `entrypoint.sh` as ENTRYPOINT.
- `entrypoint.sh` — the entire runtime logic (see below).
- `docker-compose.sample.yml` — the example deployment users copy; it and the README's snippet must
  stay in sync.
- `.github/workflows/docker-build.yml` — shellcheck, then build and push to GHCR.

## Runtime behaviour (entrypoint.sh)

The agent binary is **not** in the image. It is installed at first container start:

1. Require `MESH_SERVER_URL` and `MESH_GROUP_ID`; each missing one exits 1 with a message naming it.
2. If `/meshagent/meshagent` exists, skip installation. This is why the deployment mounts a volume
   at `/meshagent` — it makes the install a one-off and is the only state the image has.
3. Otherwise download `${MESH_SERVER_URL}/meshagents?script=1` to `meshinstall.sh.part`, move it
   into place, run it with the server URL and group ID, remove it, and verify the agent binary
   exists before continuing.
4. `exec "$AGENT_BIN"` so the agent is PID 1 and receives signals directly.

Install and upgrade semantics belong in this script; there is nowhere else for them to go. Every
failure path goes through `fail()` so the container dies with a cause rather than a stack of
`set -e` silence.

## Build, run, test

No test suite or build system beyond Docker itself. Verify changes by building and running:

```sh
docker build -t docker-meshcentral-agent .
docker run --rm -v ./meshagent-data:/meshagent \
  -e MESH_SERVER_URL="https://your-meshcentral-server.com" \
  -e MESH_GROUP_ID="your-group-id" \
  docker-meshcentral-agent
```

`entrypoint.sh` is `#!/bin/sh` (POSIX, not bash) — CI runs `shellcheck --shell=sh entrypoint.sh`
and fails the build before anything is pushed, so run it locally after editing.

## Image composition

Two things about the Dockerfile that look like oversights but are not:

- **Multi-stage would not help.** Nothing is compiled, and `wget`, `curl` and `ca-certificates`
  are all needed at *runtime* (the agent is downloaded on first start), so a final stage would
  reinstall exactly what a builder stage held. There is nothing to discard.
- **`curl` is not redundant with `wget`.** MeshCentral's `meshinstall-linux.sh` downloads with
  `wget … || curl …`; curl is its fallback path. Removing it breaks installs whenever wget fails.

## Publishing

Pull requests build without pushing. Every push that publishes tags the image both `:latest` and
`:YYYYMMDD`, so `:latest` follows the newest build and the dated tags are the pin/rollback path.
Note this is deliberate and branch-independent: a push to any listed branch moves `:latest`.

Base image: `trixie` is Debian 13, current stable. Check
[docker-library/official-images](https://github.com/docker-library/official-images/blob/master/library/debian)
before bumping — the tag carrying `latest` there is the current stable.

## Branch layout

`v1` is an orphan branch: a clean rebuild with no shared history with `main`. Do not try to merge
or rebase across the two.

## Documentation contract

`entrypoint.sh` is the source of truth for the environment variables — keep the README's
Configuration table, the README's compose snippet, and `docker-compose.sample.yml` in agreement with it.

## Operational note

`MESH_GROUP_ID` values contain `$` characters. In a compose file each must be written `$$` (or
backslash-escaped when passed from a shell), or the value is silently mangled into a broken group
ID and the agent never appears on the server.
