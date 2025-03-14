# meshcentral-agent for docker environments


This repository has an alpine linux docker image that contains the XCP-ng [guest tools](https://xcp-ng.org/docs/guests.html#alpine), configured to expose telemetry to the xcp-ng host. It was created to speed up the configuration process of a virtualized RancherOS VM within XCP-ng.
The code is a fork of the [Image: XCP-ng guest tools for RancherOS](https://github.com/GeoMSK/ros-meshcentral-agent)

# Installation (From [GitHub Container Repo](https://github.com/wus-technik/docker-meshcentral-agent/pkgs/container/docker-meshcentral-agent))

Run with a very simple docker-compose file:

``` yaml
services:
  meshcentral-agent:
    image: meshcentral-agent
    container_name: meshcentral-agent
    image: ghcr.io/wus-technik/docker-meshcentral-agent:latest
    restart: unless-stopped
    volumes:
      - ./meshagent-data:/meshagent  # Persist the agent installation
    environment:
      MESH_SERVER_URL: "https://your-meshcentral-server.com"
      # be careful! the token will contain $ signes which need to be escaped with a backslash
      MESH_GROUP_ID: "your-super-long-group-id"
```

# Configuration
Environment variables:
- `MESH_SERVER_URL` - The URL of the MeshCentral server.
- `MESHCENTRAL_TOKEN` - The token of the group you want the agent to join.



# Versions

- 20250314: 
