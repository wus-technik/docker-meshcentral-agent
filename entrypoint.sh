#!/bin/sh
set -e  # Exit on error

# Ensure required environment variables are set
if [ -z "$MESH_SERVER_URL" ] || [ -z "$MESH_GROUP_ID" ]; then
    echo "ERROR: MESH_SERVER_URL and MESH_GROUP_ID must be set."
    exit 1
fi

# Check if MeshAgent is already installed
if [ -f "/meshagent/meshagent" ]; then
    echo "MeshCentral Agent already installed. Starting..."
else
    echo "Downloading and installing MeshCentral Agent..."
    wget "${MESH_SERVER_URL}/meshagents?script=1" -O meshinstall.sh
    chmod +x meshinstall.sh

    echo "Running MeshCentral Agent installation..."
    ./meshinstall.sh "$MESH_SERVER_URL" "$MESH_GROUP_ID"
fi

echo "Starting MeshCentral Agent..."
exec /meshagent/meshagent