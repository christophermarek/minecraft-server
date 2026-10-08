#!/usr/bin/env bash
# Creates the WorldGuard "spawn" safe zone around the world's actual spawn point.
# Re-run after resetting the world (spawn moves). Usage: ./scripts/setup-spawn.sh [container] [radius]
set -euo pipefail

CONTAINER=${1:-minecraft-server}
RADIUS=${2:-48}
SERVER_DIR=${SERVER_DIR:-$(cd "$(dirname "$0")/.." && pwd)/server}

docker exec "$CONTAINER" rcon-cli save-all >/dev/null

# Read Data.spawn.pos (1.21.9+ level.dat layout) without needing an NBT library.
read -r SX SZ < <(python3 -I - "$SERVER_DIR/world/level.dat" <<'PY'
import gzip, struct, sys
data = gzip.open(sys.argv[1]).read()
spawn = data.find(b"\x0a\x00\x05spawn")
pos = data.find(b"\x0b\x00\x03pos", spawn)
if spawn < 0 or pos < 0:
    sys.exit("could not find spawn position in level.dat")
x, y, z = struct.unpack(">iii", data[pos + 10:pos + 22])
print(x, z)
PY
)
echo "World spawn is at x=$SX z=$SZ; protecting a $((RADIUS * 2))x$((RADIUS * 2)) area around it."

REGIONS="$SERVER_DIR/plugins/WorldGuard/worlds/world/regions.yml"
mkdir -p "$(dirname "$REGIONS")"
cat > "$REGIONS" <<YML
regions:
    __global__:
        members: {}
        flags: {}
        owners: {}
        type: global
        priority: 0
    spawn:
        min: {x: $((SX - RADIUS)), y: -64, z: $((SZ - RADIUS))}
        max: {x: $((SX + RADIUS - 1)), y: 319, z: $((SZ + RADIUS - 1))}
        members: {}
        flags:
            pvp: deny
            tnt: deny
            creeper-explosion: deny
            other-explosion: deny
            fire-spread: deny
            lava-fire: deny
            greeting: '&aEntering spawn: PvP is disabled.'
            farewell: '&cLeaving spawn: PvP is enabled in the wilderness!'
        owners: {}
        type: cuboid
        priority: 10
YML

# Load the file we just wrote into WorldGuard's memory (otherwise it would overwrite it on save).
docker exec "$CONTAINER" rcon-cli "rg load -w world" >/dev/null
echo "Spawn region loaded. Lock building to staff with: make cmd C=\"rg flag -w world spawn build deny\""
