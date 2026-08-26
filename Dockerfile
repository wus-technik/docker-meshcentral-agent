# The MeshCentral agent is not baked into this image: entrypoint.sh fetches it
# from the MeshCentral server at first start, so the base only needs a way to
# download that installer and validate its TLS certificate.
#
# Multi-stage would not help, and this was measured rather than assumed
# (2026-08-26, amd64): debian:trixie-slim is 75.0 MB, this image 98.6 MB. A
# multi-stage variant copying only wget, curl and their libraries came out at
# 93.4 MB, but neither binary could start — transitive libraries were missing.
# Copying enough to fix that re-adds the same packages, for no saving and a
# fragile, arch-specific COPY step.
FROM debian:trixie-slim

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
