# The MeshCentral agent is not baked into this image: entrypoint.sh fetches it
# from the MeshCentral server at first start, so the base only needs a way to
# download that installer and validate its TLS certificate.
#
# The build has two targets, and the split is about purpose, not size:
#
#   slim   the agent and nothing else — the original image
#   tools  the same agent plus a network diagnostics kit, so the container can
#          be shelled into from MeshCentral and used as a probe on the site
#
# `tools` is last, so a bare `docker build .` produces the probe. Note this is
# NOT the size-saving kind of multi-stage: `tools` builds ON `slim` rather than
# copying out of it. A copy-only variant was measured and rejected (2026-08-26,
# amd64): debian:trixie-slim is 75.0 MB and the agent image 98.6 MB, while a
# variant copying just wget, curl and their libraries came out at 93.4 MB with
# neither binary able to start for want of transitive libraries. Copying enough
# to fix that re-adds the same packages, for no saving and a fragile,
# arch-specific COPY step. Do not re-open that without new evidence.
FROM debian:trixie-slim AS slim

LABEL org.opencontainers.image.title="MeshCentral Agent for Docker" \
      org.opencontainers.image.description="Runs a MeshCentral agent in a container, installed from your own server on first start." \
      org.opencontainers.image.vendor="W&S Technik GmbH" \
      org.opencontainers.image.authors="W&S Technik GmbH" \
      org.opencontainers.image.url="https://github.com/wus-technik/docker-meshcentral-agent" \
      org.opencontainers.image.source="https://github.com/wus-technik/docker-meshcentral-agent" \
      org.opencontainers.image.documentation="https://github.com/wus-technik/docker-meshcentral-agent/blob/main/README.md" \
      org.opencontainers.image.licenses="MIT"

# MeshCentral's installer downloads with `wget ... || curl ...`, so both are
# required: curl is its fallback, not a duplicate.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
    && rm -rf /var/lib/apt/lists/*

# The agent installs into, and runs from, this directory. Mount a volume here
# to keep the installation across container restarts.
WORKDIR /meshagent
VOLUME ["/meshagent"]

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]


# The diagnostics layer. Everything here is a tool you would reach for from
# MeshCentral's remote terminal; nothing here changes how the agent installs or
# runs. Package names are checked by CI (tools-smoke.sh) because Debian renames
# them between releases — `dnsutils` became `bind9-dnsutils` in trixie, which
# would otherwise drop `dig` from the image without failing the build.
FROM slim AS tools

LABEL org.opencontainers.image.title="MeshCentral Agent for Docker (tools)" \
      org.opencontainers.image.description="MeshCentral agent plus a network diagnostics kit, for use as an on-site probe."

RUN apt-get update && apt-get install -y --no-install-recommends \
        bind9-dnsutils \
        bind9-host \
        ethtool \
        fping \
        iperf3 \
        iproute2 \
        iputils-arping \
        iputils-ping \
        iputils-tracepath \
        jq \
        ldap-utils \
        less \
        lsof \
        mtr-tiny \
        netcat-openbsd \
        nmap \
        openssl \
        procps \
        smbclient \
        socat \
        tcpdump \
        traceroute \
        vim-tiny \
        whois \
    && rm -rf /var/lib/apt/lists/*

COPY tools-smoke.sh /tools-smoke.sh
RUN chmod +x /tools-smoke.sh
