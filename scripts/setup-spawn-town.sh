#!/usr/bin/env bash
# Turns world spawn into a server-owned Towny town so players can't claim it (or the 5-chunk buffer around it).
# Needs an admin ONLINE: Towny places the town where its first mayor stands.
# Usage: ./scripts/setup-spawn-town.sh <online-admin-name> [container]
set -euo pipefail

ADMIN=${1:?usage: setup-spawn-town.sh <online-admin-name> [container]}
CONTAINER=${2:-minecraft-server}
SERVER_DIR=${SERVER_DIR:-$(cd "$(dirname "$0")/.." && pwd)/server}

rcon() { echo "> $*"; docker exec "$CONTAINER" rcon-cli "$@" | sed 's/\x1b\[[0-9;]*m//g; s/§.//g'; }

docker exec "$CONTAINER" rcon-cli save-all >/dev/null
read -r SX SY SZ < <(python3 -I - "$SERVER_DIR/world/level.dat" <<'PY'
import gzip, struct, sys
data = gzip.open(sys.argv[1]).read()
pos = data.find(b"\x0b\x00\x03pos", data.find(b"\x0a\x00\x05spawn"))
print(*struct.unpack(">iii", data[pos + 10:pos + 22]))
PY
)

rcon "execute in minecraft:overworld run tp $ADMIN $SX.5 $((SY + 1)) $SZ.5"
rcon "ta town new Spawn $ADMIN"
rcon "ta givebonus Spawn 30"
rcon "ta town Spawn deposit 1000"
rcon "sudo $ADMIN t claim rect 2"
rcon "sudo $ADMIN confirm"  # Towny may ask to confirm the cost; harmless if not
rcon "ta town Spawn toggle pvp off"
rcon "ta set mayor Spawn npc"
rcon "sudo $ADMIN t leave"
rcon "sudo $ADMIN confirm"
rcon "ta town Spawn"
