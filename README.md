<div align="center">

# MeshCentral Agent for Docker

**Put a container on your MeshCentral map — two variables and a volume.**

A small Debian-based image that installs the [MeshCentral](https://meshcentral.com/) agent on
first start, straight from your own server, and keeps the installation in a volume you control.

[![Build](https://img.shields.io/github/actions/workflow/status/wus-technik/docker-meshcentral-agent/docker-build.yml?branch=main&style=for-the-badge&label=build&logo=github)](https://github.com/wus-technik/docker-meshcentral-agent/actions/workflows/docker-build.yml)
[![GHCR](https://img.shields.io/badge/ghcr.io-docker--meshcentral--agent-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://github.com/wus-technik/docker-meshcentral-agent/pkgs/container/docker-meshcentral-agent)

[![License: MIT](https://img.shields.io/github/license/wus-technik/docker-meshcentral-agent?style=flat-square&color=blue)](LICENSE)
![Debian](https://img.shields.io/badge/base-debian_13_trixie--slim-A81D33?style=flat-square&logo=debian&logoColor=white)
![Agent](https://img.shields.io/badge/agent-fetched_at_first_start-lightgrey?style=flat-square)
![Tags](https://img.shields.io/badge/tags-stable_%2B_latest-informational?style=flat-square)

</div>

---

## Why

MeshCentral hands you an install script meant for a host, not a container. This image wraps it:
point at your server and a device group, mount one volume, and the agent installs itself once and
comes straight back up on every restart.

## What you get

| | |
|---|---|
| 📦 **Nothing baked in** | The agent comes from **your** server's own installer, so it always matches the server it reports to |
| 💾 **One volume** | `/meshagent` holds the installation — later starts find it and skip the download entirely |
| 🧾 **Two variables** | `MESH_SERVER_URL` and `MESH_GROUP_ID`; the container refuses to start without both, rather than half-installing |
| 🐧 **Small base** | `debian:trixie-slim` (Debian 13) plus `wget`, `curl` and `ca-certificates` — nothing else |
| 🔁 **Clean signals** | The agent is `exec`'d as PID 1, so `docker stop` reaches it directly |
| 🩹 **Fails loudly** | A bad URL, a bad group ID or an installer that produces no binary each stop the container with a message naming the cause |
| 🏷️ **Two tracks** | `:stable` is cut from a git tag on `main`; `:latest` follows the newest branch build. Both leave an immutable tag behind |

## Install

Pull from the [GitHub Container Registry](https://github.com/wus-technik/docker-meshcentral-agent/pkgs/container/docker-meshcentral-agent)
with a very simple compose file — [`docker-compose.sample.yml`](docker-compose.sample.yml) in this
repository is ready to copy:

``` yaml
services:
  meshcentral-agent:
    container_name: meshcentral-agent
    image: ghcr.io/wus-technik/docker-meshcentral-agent:latest
    restart: unless-stopped
    volumes:
      - ./meshagent-data:/meshagent  # Keeps the agent installed across restarts
    environment:
      MESH_SERVER_URL: "https://your-meshcentral-server.com"
      MESH_GROUP_ID: "your-super-long-group-id"
```

> [!TIP]
> `:latest` follows every branch build. For a deployment you want `:stable`, which only moves when
> a release is tagged on `main` — or a `:YYYYMMDD` tag to pin one exact image.

> [!IMPORTANT]
> Group IDs contain `$` characters. Compose reads a single `$` as variable interpolation, so
> **write every one of them twice** (`$$`) — otherwise the agent joins with a mangled ID and never
> appears in the group. From a shell, escape with a backslash instead.

## Configuration

| Variable | Meaning | Required |
|---|---|---|
| `MESH_SERVER_URL` | Base URL of your MeshCentral server — both where the installer comes from and where the agent reports | ✅ |
| `MESH_GROUP_ID` | ID of the device group the agent should join, copied from the server's *Add Agent* dialog | ✅ |

Nothing else is configurable, and nothing is written outside `/meshagent`.

## Persistence

The volume is the whole of the container's state, and one file in it is the device's identity:

| File in `/meshagent` | What it is | Lose it and… |
|---|---|---|
| `meshagent.db` | The node certificate — **the registration** | The agent comes back as a *new* device; the old one goes offline forever |
| `meshagent.msh` | Server URL, device group, startup type | The agent has nothing to connect to |
| `meshagent` | The agent binary | It is downloaded again on the next start |

Back up `meshagent.db` and `meshagent.msh` together, and keep the volume across image updates:
`docker compose pull && docker compose up -d` keeps the same device, because nothing in the
volume is touched.

> [!WARNING]
> `MESH_GROUP_ID` is read **once**, at install. Changing it later does nothing — the agent stays in
> the group recorded in `meshagent.msh`, because a start that finds an existing installation skips
> the installer entirely. To move a device to another group, delete the volume and let it
> re-register, then remove the stale device on the server.

If the volume is ever partially lost, the container says so at startup rather than silently
re-registering:

```
[meshagent] WARNING: /meshagent/meshagent.db is missing — this container will register as a NEW device.
```

Seeing that on *every* start means the agent is keeping its identity somewhere other than the
volume — worth reporting, since it is what the volume exists to prevent.

<details>
<summary><b>What happens on the first start</b></summary>

<br>

`entrypoint.sh` is the whole of it, in order:

1. **Check the contract.** A missing `MESH_SERVER_URL` or `MESH_GROUP_ID` stops the container with
   an error naming the variable — there is no partial install to clean up afterwards.
2. **Look for an existing install.** If `/meshagent/meshagent` is there, everything below is
   skipped. That is the only reason the volume matters: it turns the download into a one-off.
3. **Fetch the installer** from `${MESH_SERVER_URL}/meshagents?script=1`, writing to a `.part` file
   and moving it into place only once the download succeeds, so an interrupted start can't leave a
   truncated script behind.
4. **Run it** with the server URL and group ID, then confirm a binary actually landed at
   `/meshagent/meshagent` before going any further.
5. **Hand over.** `exec` replaces the shell with the agent, making it PID 1.

Delete the volume to force a clean reinstall on the next start.

</details>

<details>
<summary><b>Building it yourself</b></summary>

<br>

```sh
docker build -t docker-meshcentral-agent .

docker run --rm -v ./meshagent-data:/meshagent \
  -e MESH_SERVER_URL="https://your-meshcentral-server.com" \
  -e MESH_GROUP_ID="your-group-id" \
  docker-meshcentral-agent
```

There is no test suite — the image is a base, a script and a workflow. `entrypoint.sh` is POSIX
`sh` rather than bash; CI runs `shellcheck --shell=sh entrypoint.sh` on every push and pull
request, so keep constructs portable.

Publishing has two tracks:

| Trigger | Tags published | Meaning |
|---|---|---|
| Git tag on `main` | `:YYYYMMDD` and `:stable` | The release path — `:stable` is what deployments should follow |
| Push to any branch | `:sha-<commit>` and `:latest` | The moving edge; `:latest` is whatever built most recently |
| Pull request, or a tag not on `main` | *(none — build only)* | Proves the image still builds without touching the registry |

Each track leaves an immutable tag behind (`:YYYYMMDD`, `:sha-…`), so pinning and rolling back
never depend on a moving tag:

```sh
docker pull ghcr.io/wus-technik/docker-meshcentral-agent:stable      # follow releases
docker pull ghcr.io/wus-technik/docker-meshcentral-agent:20260826    # pin to one release
```

</details>

## Versions

- **v1** — first release of the rebuilt image: Debian 13 (trixie) base, install-on-first-start
  entrypoint with explicit failure messages, a `docker-compose.sample.yml` to copy, MIT licence,
  and a build that lints the script before publishing.

---

## License

[MIT](LICENSE) © 2026 W&S Technik GmbH

<div align="center">
<sub>Not affiliated with MeshCentral. The agent itself is downloaded from your own server and carries its own licence.</sub>
</div>
