#!/bin/sh
# Install the MeshCentral agent on first start, then hand the container over to
# it. Every later start finds the installation in the /meshagent volume and
# skips straight to the last line.
set -e

AGENT_DIR="/meshagent"
AGENT_BIN="${AGENT_DIR}/meshagent"
INSTALLER="${AGENT_DIR}/meshinstall.sh"
# The device's identity on the server. The agent writes it beside itself on
# first connect; losing it means the next start registers as a new device.
AGENT_DB="${AGENT_DIR}/meshagent.db"
AGENT_MSH="${AGENT_DIR}/meshagent.msh"
# The agent derives its NodeID from the container's MAC address, so a MAC that
# changes between starts resets the identity even though meshagent.db survived.
# Remember the MAC to catch that before the agent does.
MAC_FILE="${AGENT_DIR}/.container-mac"

log() {
    echo "[meshagent] $*"
}

warn() {
    echo "[meshagent] WARNING: $*" >&2
}

fail() {
    echo "[meshagent] ERROR: $*" >&2
    exit 1
}

# First non-loopback interface; that is the one Docker hands the container.
current_mac() {
    for iface in /sys/class/net/*; do
        name="${iface##*/}"
        [ "$name" = "lo" ] && continue
        [ -r "${iface}/address" ] || continue
        cat "${iface}/address"
        return 0
    done
}

# Warn when the MAC differs from the previous start, then record the new one so
# a pinned MAC stays silent and a rotating one reports on every start.
check_mac() {
    mac="$(current_mac)"
    [ -n "$mac" ] || return 0

    if [ -f "$MAC_FILE" ]; then
        previous="$(cat "$MAC_FILE")"
        if [ "$previous" != "$mac" ]; then
            warn "MAC address changed (${previous} -> ${mac}). The agent derives its NodeID from the MAC, so it will register as a NEW device even though ${AGENT_DIR} was kept. Pin the MAC in your deployment (compose: mac_address)."
        fi
    fi

    printf '%s\n' "$mac" > "$MAC_FILE" 2>/dev/null \
        || warn "Could not record the container MAC in ${MAC_FILE}."
}

[ -n "$MESH_SERVER_URL" ] || fail "MESH_SERVER_URL is not set."
[ -n "$MESH_GROUP_ID" ] || fail "MESH_GROUP_ID is not set."

if [ -f "$AGENT_BIN" ]; then
    log "Agent already installed in ${AGENT_DIR}."

    # The binary survived but the state beside it did not: the agent will come
    # up as a brand new device rather than the one already on the server.
    [ -f "$AGENT_MSH" ] || warn "${AGENT_MSH} is missing — the agent has no server settings and cannot connect."
    [ -f "$AGENT_DB" ] || warn "${AGENT_DB} is missing — this container will register as a NEW device. If this repeats on every start, the agent is not keeping its identity in ${AGENT_DIR}."
    check_mac
else
    log "No agent in ${AGENT_DIR} — installing from ${MESH_SERVER_URL}."

    # Download beside the target and move into place only on success, so an
    # interrupted start never leaves a truncated installer behind.
    if ! wget -O "${INSTALLER}.part" "${MESH_SERVER_URL}/meshagents?script=1"; then
        rm -f "${INSTALLER}.part"
        fail "Could not download the installer from ${MESH_SERVER_URL}. Is MESH_SERVER_URL correct and reachable?"
    fi
    mv "${INSTALLER}.part" "$INSTALLER"
    chmod +x "$INSTALLER"

    log "Running the installer."
    "$INSTALLER" "$MESH_SERVER_URL" "$MESH_GROUP_ID" \
        || fail "The installer failed. Check that MESH_GROUP_ID matches a device group on the server."
    rm -f "$INSTALLER"

    [ -f "$AGENT_BIN" ] \
        || fail "The installer finished but left no agent at ${AGENT_BIN}."

    log "Installed."
    check_mac
fi

# exec so the agent becomes PID 1 and receives docker stop's signals itself.
log "Starting agent."
exec "$AGENT_BIN"
