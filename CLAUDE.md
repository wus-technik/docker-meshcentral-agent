# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Docker image that runs a [MeshCentral](https://meshcentral.com/) agent in a container, built in
two flavours from one Dockerfile: a **probe** carrying network diagnostics tools (the default, and
what the unsuffixed tags point at) and a **slim** agent-only image (`-slim` tags). There is no
application source code; the deliverable is:

- `Dockerfile` — two targets. `slim` is `debian:trixie-slim` plus `wget`/`curl`/`ca-certificates`,
  `WORKDIR /meshagent`, `entrypoint.sh` as ENTRYPOINT; `tools` builds on it and adds the
  diagnostics packages. `tools` is last, so a bare `docker build .` produces the probe.
- `entrypoint.sh` — the entire runtime logic (see below). Identical in both targets.
- `tools-smoke.sh` — proves every tool in the `tools` target is present and can exec. Shipped in
  the image (operators can run it) and run by CI before publishing.
- `docker-compose.sample.yml` (probe) and `docker-compose.slim.sample.yml` (agent only) — the
  example deployments users copy; they and the README's snippets must stay in sync.
- `.github/workflows/docker-build.yml` — shellcheck, then a build matrix over both targets,
  the tools smoke test, then push to GHCR.
- `CHANGELOG.md` — one entry per dated release, naming the image tags it published. Add an entry
  in the same commit that earns it, not at release time.
- `.gitattributes` — `* text=auto eol=lf`. Not cosmetic: with `core.autocrlf=true` a Windows clone
  checks the scripts out as CRLF, `docker build` bakes `#!/bin/sh\r` into the image, and the
  container dies with `exec /entrypoint.sh: no such file or directory`. Do not remove it.

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

## State contract

`/meshagent` holds everything: the binary, `meshagent.msh` (server URL and group) and
`meshagent.db` — the node certificate, i.e. the device's identity on the server. The installer
downloads into the working directory and the agent runs from there, which is what keeps state in
the volume; do not change `WORKDIR`, and do not `cd` in `entrypoint.sh`, or the identity moves into
the container layer and every recreate produces a duplicate device. Step 2's skip is keyed on the
binary alone, so the script warns separately when `.msh` or `.db` is missing rather than
re-registering in silence.

Note MeshCentral's installer also runs `./meshagent -fullinstall`, which copies the agent to a
system path and tries to register a service — both useless in a container. See the open issue on
bypassing the installer.

## Build, run, test

No build system beyond Docker itself. Verify changes by building and running:

```sh
docker build -t docker-meshcentral-agent .                       # the probe (target: tools)
docker build --target slim -t docker-meshcentral-agent:slim .    # the agent alone

docker run --rm -v ./meshagent-data:/meshagent \
  -e MESH_SERVER_URL="https://your-meshcentral-server.com" \
  -e MESH_GROUP_ID="your-group-id" \
  docker-meshcentral-agent

docker run --rm --entrypoint /tools-smoke.sh docker-meshcentral-agent
```

`entrypoint.sh` and `tools-smoke.sh` are `#!/bin/sh` (POSIX, not bash) — CI runs
`shellcheck --shell=sh` on both and fails the build before anything is pushed, so run it locally
after editing.

There is no test suite for the agent path — it needs a real MeshCentral server. The tools *are*
tested: `tools-smoke.sh` checks each binary with `command -v` and then execs it, failing only on
126/127. Exit status is otherwise ignored, because several of these tools exit non-zero for
`--version`. Add a `check` line whenever you add a package; that file is the list CI enforces.

## Image composition

Three things about the Dockerfile that look like oversights but are not:

- **The multi-stage split is about purpose, not size.** `tools` builds *on* `slim` rather than
  copying out of it, so nothing is discarded and both images share every layer of the agent. The
  size-saving kind of multi-stage was measured and rejected (2026-08-26, amd64, `docker images`):
  base `debian:trixie-slim` 75.0 MB, the agent image 98.6 MB, and a variant copying only the
  binaries and their libraries 93.4 MB — with both `wget` and `curl` failing to start for want of
  transitive libraries. Nothing is compiled here and all three packages are runtime dependencies of
  the first-start install, so a builder stage has nothing to discard. Do not re-open that without
  new evidence. Current sizes (2026-08-27, `du -sx` inside the container, so not comparable to the
  figures above): `slim` 100 MB, `tools` 221 MB.
- **`bind9-dnsutils`, not `dnsutils`.** In trixie `dnsutils` is a transitional package: apt
  installs it happily and no `dig` appears. This class of failure is exactly what `tools-smoke.sh`
  exists to catch, and it will catch the next one on a base bump.
- **`curl` is not redundant with `wget`.** MeshCentral's `meshinstall-linux.sh` downloads with
  `wget … || curl …`; curl is its fallback path. Removing it breaks installs whenever wget fails.

## Publishing

The workflow's `Resolve image tags` step decides both the tags and whether to push at all:

Every leg runs twice, once per matrix target, and the matrix `suffix` is appended to each tag:
`''` for `tools`, `-slim` for `slim`. **The unsuffixed tags are the probe** — deployments follow
`:stable` and get the tools.

Release tags are dates — `YYYYMMDD`, or `YYYYMMDD.N` for a second release the same day — and the
image tag is `$GITHUB_REF_NAME` verbatim, not `date +%Y%m%d`. Those were previously independent,
which meant re-running an old release's workflow stamped today onto an old commit, and two releases
in one day silently overwrote each other. A tag on `main` in any other shape now fails the step
with an `::error::` rather than publishing. No semantic versions: nothing here has an API to break.

| Event | Tags (probe / slim) | Pushed |
|---|---|---|
| Git tag whose commit is an ancestor of `origin/main` | `:<tag>`, `:stable` / `:<tag>-slim`, `:stable-slim` | yes |
| Push to any branch | `:sha-<12>`, `:latest` / `:sha-<12>-slim`, `:latest-slim` | yes |
| Pull request | `:pr-<n>` / `:pr-<n>-slim` | no |
| Git tag *not* on `main` | `:<tag name>` / `:<tag name>-slim` | no, plus a `::warning::` |

Three things that step depends on: `fetch-depth: 0` on the checkout (the ancestry test needs real
history), the multi-line `$GITHUB_OUTPUT` heredoc for `tags`, and `SUFFIX` reaching the script
through `env:` rather than being interpolated mid-heredoc. `:stable` must stay reachable only from
the tag-on-main path — that is the whole point of the split.

Before the push step, the `tools` leg builds the probe with `load: true` and runs
`tools-smoke.sh` in it. The push that follows is a cache hit on that build, so this costs a
container run rather than a second build. The two legs use separate `cache-to` scopes so they do
not evict each other.

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
Configuration table, the README's compose snippets, `docker-compose.sample.yml` and
`docker-compose.slim.sample.yml` in agreement with it.

Both samples set `hostname:`, and the README's Naming section explains why. This is deployment
advice rather than image behaviour: the agent reports its hostname on every connect and MeshCentral
renames the device to match (`meshagent.js`, the `computer name` change path), so a container
without a fixed hostname is renamed to a fresh random string on every recreate. It does *not*
produce a second device — the identity is the public-key fingerprint of the certificate in
`meshagent.db`. Keep those two failure modes distinct in the docs; conflating them sends people to
delete volumes that are fine.

`tools-smoke.sh` is the source of truth for what the probe contains — keep the README's Variants
table in agreement with it. Adding a package means touching the Dockerfile, `tools-smoke.sh` and
that table together.

`CHANGELOG.md` is the source of truth for releases — keep the README's Releases table pointing at
it rather than restating it.

## Operational note

`MESH_GROUP_ID` values contain `$` characters. In a compose file each must be written `$$` (or
backslash-escaped when passed from a shell), or the value is silently mangled into a broken group
ID and the agent never appears on the server.
