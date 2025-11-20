# Minecraft Server

A Dockerized PaperMC Minecraft server with Pl3xMap web mapping.

## Commands

### `make start`
Builds and starts the Minecraft server in a Docker container:
- Builds the Docker image
- Creates the server directory if it doesn't exist
- Starts the server container with:
  - Minecraft server on port 25565
  - Web map on port 8080
  - Persistent world data stored in `./server`
- Automatically shows server logs (Ctrl+C to exit logs, server keeps running)

### `make stop`
Stops and cleans up the server:
- Stops the running container
- Removes the container
- Removes the Docker image
- Preserves all world data in `./server` directory

## Quick Start

```bash
make start
```

Connect to `localhost:25565` in Minecraft and view the map at `http://localhost:8080`

To stop:

```bash
make stop
```

