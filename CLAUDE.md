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

- **Multi-stage would not help**, measured on CI (2026-08-26, amd64): base `debian:trixie-slim`
  75.0 MB, this image 98.6 MB, and a multi-stage variant copying only the binaries and their
  libraries 93.4 MB — with both `wget` and `curl` failing to start for want of transitive
  libraries. Nothing is compiled here and all three packages are runtime dependencies of the
  first-start install, so a builder stage has nothing to discard. Do not re-open this without
  new evidence.
- **`curl` is not redundant with `wget`.** MeshCentral's `meshinstall-linux.sh` downloads with
  `wget … || curl …`; curl is its fallback path. Removing it breaks installs whenever wget fails.

## Publishing

The workflow's `Resolve image tags` step decides both the tags and whether to push at all:

| Event | Tags | Pushed |
|---|---|---|
| Git tag whose commit is an ancestor of `origin/main` | `:YYYYMMDD`, `:stable` | yes |
| Push to any branch | `:sha-<12>`, `:latest` | yes |
| Pull request | `:pr-<n>` | no |
| Git tag *not* on `main` | `:<tag name>` | no, plus a `::warning::` |

Two things that step depends on: `fetch-depth: 0` on the checkout (the ancestry test needs real
history), and the multi-line `$GITHUB_OUTPUT` heredoc for `tags`. `:stable` must stay reachable
only from the tag-on-main path — that is the whole point of the split.

Every action is on a major that runs on **Node 24**, the runner default. Do not pin any back to a
Node 20 major; the runner warns and will eventually refuse.

Base image: `trixie` is Debian 13, current stable. Check
[docker-library/official-images](https://github.com/docker-library/official-images/blob/master/library/debian)
before bumping — the tag carrying `latest` there is the current stable.

## History

`main` was rebuilt from scratch as an orphan branch and force-pushed over the original history, so
it shares no ancestry with the repository's first commits. Nothing predating that rebuild is
reachable from a branch.

## Documentation contract

`entrypoint.sh` is the source of truth for the environment variables — keep the README's
Configuration table, the README's compose snippet, and `docker-compose.sample.yml` in agreement with it.

## Operational note

`MESH_GROUP_ID` values contain `$` characters. In a compose file each must be written `$$` (or
backslash-escaped when passed from a shell), or the value is silently mangled into a broken group
ID and the agent never appears on the server.
