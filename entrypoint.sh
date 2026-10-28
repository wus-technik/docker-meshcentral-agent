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
# Written only once an install is verified complete. The binary alone is no
# proof: a failed install leaves one behind, and starting from it would loop.
INSTALLED_MARKER="${AGENT_DIR}/.installed"

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

# The installer runs as root. Over plain HTTP anyone on the path could swap it.
case "$MESH_SERVER_URL" in
    https://*) ;;
    *) fail "MESH_SERVER_URL must start with https:// — the installer it serves runs as root." ;;
esac
# A trailing slash would otherwise reach both the download URL and the
# installer as `//meshagents` and `https://host/`.
MESH_SERVER_URL="${MESH_SERVER_URL%/}"

# The binary and its settings are both in place and non-empty. This is checked
# rather than trusting the installer's exit status: MeshCentral's installer
# exits 0 even when its downloads fail, and `wget -O` has already created an
# empty `meshagent` by then.
agent_complete() {
    [ -s "$AGENT_BIN" ] && [ -x "$AGENT_BIN" ] && [ -s "$AGENT_MSH" ]
}

# The state beside a kept binary is gone: the agent will come up as a brand new
# device rather than the one already on the server.
warn_missing_state() {
    [ -f "$AGENT_MSH" ] || warn "${AGENT_MSH} is missing — the agent has no server settings and cannot connect."
    [ -f "$AGENT_DB" ] || warn "${AGENT_DB} is missing — this container will register as a NEW device. If this repeats on every start, the agent is not keeping its identity in ${AGENT_DIR}."
}

if [ -f "$INSTALLED_MARKER" ] && [ -x "$AGENT_BIN" ]; then
    log "Agent already installed in ${AGENT_DIR}."
    warn_missing_state
    check_mac
elif [ ! -f "$INSTALLED_MARKER" ] && [ -f "$AGENT_DB" ] && agent_complete; then
    # A volume from before the marker existed. The node certificate is there,
    # so this agent has run and connected before: the install did finish.
    log "Agent installed in ${AGENT_DIR} by an older image; marking the install complete."
    touch "$INSTALLED_MARKER"
    check_mac
else
    if [ -e "$AGENT_BIN" ]; then
        warn "Found an incomplete installation in ${AGENT_DIR} (an earlier install was interrupted or failed) — installing again."
    fi
    log "Installing the agent from ${MESH_SERVER_URL}."
    rm -f "$INSTALLED_MARKER"

    # A reinstall must not cost the device its identity. Whatever the
    # installer does to the directory, the node certificate goes back after.
    if [ -f "$AGENT_DB" ]; then
        cp -p "$AGENT_DB" "${AGENT_DB}.keep"
    fi

    # Download beside the target and move into place only on success, so an
    # interrupted start never leaves a truncated installer behind.
    # curl rather than wget: wget follows an https -> http redirect without a
    # word, and --proto-redir is what closes that downgrade.
    if ! curl --fail --silent --show-error --location \
            --proto '=https' --proto-redir '=https' \
            -o "${INSTALLER}.part" "${MESH_SERVER_URL}/meshagents?script=1"; then
        rm -f "${INSTALLER}.part"
        fail "Could not download the installer from ${MESH_SERVER_URL}. Is MESH_SERVER_URL correct and reachable?"
    fi
    mv "${INSTALLER}.part" "$INSTALLER"
    chmod +x "$INSTALLER"

    log "Running the installer."
    "$INSTALLER" "$MESH_SERVER_URL" "$MESH_GROUP_ID" \
        || fail "The installer failed. Check that MESH_GROUP_ID matches a device group on the server."
    rm -f "$INSTALLER"

    if [ -f "${AGENT_DB}.keep" ]; then
        mv -f "${AGENT_DB}.keep" "$AGENT_DB"
    fi

    # No marker on failure, so the next start installs again instead of
    # exec'ing a truncated binary forever under `restart: unless-stopped`.
    agent_complete \
        || fail "The installer finished but left no usable agent: ${AGENT_BIN} and ${AGENT_MSH} must both exist and be non-empty. Its output above names the download that failed."

    touch "$INSTALLED_MARKER"
    log "Installed."
    check_mac
fi

# exec so the agent becomes PID 1 and receives docker stop's signals itself.
log "Starting agent."
exec "$AGENT_BIN"
