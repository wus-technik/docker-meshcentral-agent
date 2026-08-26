# The MeshCentral agent is not baked into this image: entrypoint.sh fetches it
# from the MeshCentral server at first start, so the base only needs a way to
# download that installer and validate its TLS certificate.
#
# There is nothing to compile, and every package below is needed at runtime
# rather than build time, so a multi-stage build would have nothing to discard
# and would not make the image smaller.
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
