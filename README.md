# Minecraft Server

A Dockerized PaperMC Minecraft server with Geyser support for cross-platform play between Java and Bedrock editions.

## Commands

### `make start`
Builds and starts the Minecraft server in a Docker container:
- Builds the Docker image
- Creates the server directory if it doesn't exist
- Starts the server container with:
  - Java Edition on port 25565 (TCP)
  - Bedrock Edition on port 19132 (UDP)
  - Persistent world data stored in `./server`
- Automatically shows server logs (Ctrl+C to exit logs, server keeps running)

### `make stop`
Stops and cleans up the server:
- Stops the running container
- Removes the container
- Removes the Docker image
- Preserves all world data in `./server` directory

### `make console`
Attaches to the server console for running commands

## Quick Start

```bash
make start
```

**Java Edition**: Connect to `localhost:25565`

**Bedrock Edition**: Connect to `localhost:19132` (requires Geyser plugin)

To stop:

```bash
make stop
```

## Adding Geyser for Cross-Platform Play

To enable Bedrock Edition players to join:

1. Download [Geyser-Spigot.jar](https://hangar.papermc.io/GeyserMC/Geyser)
2. Download [Floodgate](https://hangar.papermc.io/GeyserMC/Floodgate) (optional, allows Bedrock players without Java accounts)
3. Place both jars in `./server/plugins/`
4. Restart the server with `make stop` and `make start`

Configuration files will be generated in:
- `./server/plugins/Geyser-Spigot/config.yml`
- `./server/plugins/floodgate/config.yml`

