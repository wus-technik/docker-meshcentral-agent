# Security review and dependency check — 2026-10-28

## Scope

Whole repository at `main` @ `abcab25`: `Dockerfile`, `entrypoint.sh`, `tools-smoke.sh`,
`.github/workflows/docker-build.yml`, `.dockerignore`, both compose samples, `README.md`,
`CLAUDE.md`. Also the published images `:stable` and `:stable-slim` (`20260827.1`).

Not visible to the review: repository settings, rulesets, branch protection, GHCR package
permissions.

## Method

- Independent review: OpenAI Codex CLI 0.163.0, model `gpt-6.1-sol`,
  `codex exec --sandbox read-only --model gpt-6.1-sol -` with all files embedded in the prompt.
  The findings were then checked against the files by hand.
- Dependencies: latest releases and `action.yml` runtime of every action, checked via `gh api`.
- Image scan: `aquasec/trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed`.
- Verification of the fixes: `shellcheck --shell=sh`, `actionlint`, local build of both targets,
  `tools-smoke.sh`, Trivy rescan, entrypoint runs against an `http://` URL, an `https://` → `http://`
  redirect and a trailing slash, and the tag pattern against valid and invalid names.

## Dependencies

| Item | State found | Action |
|---|---|---|
| `actions/checkout` | `@v7`, latest v7.0.1, node24 | pinned to SHA of v7.0.1 |
| `docker/setup-buildx-action` | `@v4`, latest v4.4.1, node24 | pinned to SHA of v4.4.1 |
| `docker/build-push-action` | `@v7`, latest v7.4.0, node24 | pinned to SHA of v7.4.0 |
| `docker/login-action` | `@v4`, latest v4.7.0, node24 | pinned to SHA of v4.7.0 |
| Base `debian:trixie-slim` | current Debian stable (13) | unchanged |
| apt packages (published images) | last built 2026-08-27; `:stable-slim` 25 fixable HIGH/CRITICAL (3 CRITICAL), `:stable` 59 (4 CRITICAL: perl-base, socat, …) | `apt-get upgrade`, weekly cache-busting rebuild; local rebuild: 0 fixable HIGH/CRITICAL |

Dependabot: enabled for `github-actions` only (`.github/dependabot.yml`, weekly, grouped). The
`docker` ecosystem is not useful with a floating codename tag; package freshness comes from the
weekly rebuild instead.

## Findings

| # | Severity | Location | Finding | Verdict | Done |
|---|---|---|---|---|---|
| 0 | High | published images | Images not rebuilt since 2026-08-27; fixed CRITICAL CVEs shipped. A rebuild alone would not have helped: the GHA cache replays old apt layers, and `apt-get install` never upgrades base packages. | Confirmed (Trivy) | Fixed: `apt-get upgrade`, ISO-week `APT_REFRESH` build arg, weekly schedule. `:stable` still needs a new release tag. |
| 1 | High | `entrypoint.sh:60,76,84` | `MESH_SERVER_URL` could be `http://`, and wget follows `https` → `http` redirects; the downloaded installer runs as root. | Confirmed | Fixed: `https://` required, download via `curl --proto =https --proto-redir =https`. Tested. Residual: the MeshCentral installer's own agent download is not under our control. |
| 2 | Medium | `docker-build.yml:14` | `packages: write` for every run: anyone who can push a branch can change the workflow on that branch and push to `:stable`. The tag-on-main check is policy, not enforcement. | Likely valid (depends on repo settings) | Open — needs a decision (split build/publish jobs, protected environment for releases). |
| 3 | Medium | `docker-build.yml` (all `uses:`) | Actions pinned to movable tags while holding a token that can replace images. | Confirmed | Fixed: SHA pins with version comments, Dependabot maintains them. |
| 4 | Medium | `docker-build.yml:70` | Tag glob `[0-9]{8}.[0-9]*` accepted `20261028.1-slim`; the probe would overwrite the slim image of that name. | Confirmed | Fixed: `grep -Eqx '[0-9]{8}(\.[0-9]+)?'`. Tested. |
| 5 | Medium | `entrypoint.sh:63` | Install skip is keyed on the binary alone; a partially written binary is never reinstalled. | Plausible (installer write order unverified) | Open — needs a completion marker; decision pending. |
| 6 | Low–Medium | `docker-compose.sample.yml:23,30` | `NET_ADMIN` together with `network_mode: host` lets a compromised agent or admin account change the host's network. Possibly `NET_RAW` suffices for tcpdump. | Valid as default/documentation point | Open — to test and decide. |
| 7 | Low | `README.md:43`, `CHANGELOG.md:8` | Dated and `sha-` tags were called immutable; re-runs and the new weekly rebuild rewrite them. | Confirmed | Fixed: wording corrected, digest pinning recommended. |
| 8 | Info | `entrypoint.sh:84`, compose | `MESH_GROUP_ID` visible via `docker inspect` and `/proc`. Not in image layers or logs. | Valid | Accepted, inherent to the installer call. |
| 9 | Low | `docker-build.yml` | No `concurrency`; runs could finish out of order and leave `:latest` on an older build. | Valid | Fixed: per-ref concurrency group, no cancellation (a global group would let a branch push cancel a queued release). |
| 10 | Low | `entrypoint.sh` | Trailing slash in `MESH_SERVER_URL` produced `//meshagents`. | Confirmed | Fixed: stripped. Tested. |
| 11 | Low | `docker-build.yml:36` | Checkout persisted the token in `.git/config` (excluded from the build context, so no leak). | Hardening | Fixed: `persist-credentials: false`. |
| 12 | Info | `docker-build.yml` | `:latest` follows any branch push; at review time it pointed at an unmerged PR branch. Documented design. | Valid observation | Open — decision pending. |
| 13 | Info | `.dockerignore` | Denylist missed `docker-compose.slim.sample.yml`; no security effect. | Valid | Covered by open PR #5. |

Checked and fine: no expression injection in `run:` (tag name via env, PR number numeric),
multi-line output cannot be injected (ref names have no newlines), `.git` excluded from the build
context, cache scopes separated and protected by GitHub's branch cache isolation, no insecure apt
options, TLS verification never disabled, `.part` download pattern, quoting under `set -e`,
`exec` to PID 1, PRs and off-main tags never publish, no privileged mode or Docker socket.
