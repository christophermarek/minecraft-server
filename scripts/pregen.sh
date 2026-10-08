#!/usr/bin/env bash
# Sets per-dimension world borders and pre-generates every chunk inside them with Chunky.
# Run with no players online; it takes hours. Check progress with: make cmd C="chunky progress"
# Override sizes: BORDER_RADIUS=7500 NETHER_RADIUS=1000 END_RADIUS=4000 ./scripts/pregen.sh
set -euo pipefail

CONTAINER=${1:-minecraft-server}
CENTER_X=${CENTER_X:-0}
CENTER_Z=${CENTER_Z:-0}
BORDER_RADIUS=${BORDER_RADIUS:-5000}
NETHER_RADIUS=${NETHER_RADIUS:-$((BORDER_RADIUS / 8))}
END_RADIUS=${END_RADIUS:-3000}

rcon() { echo "> $*"; docker exec "$CONTAINER" rcon-cli "$@"; }

# Vanilla borders are per dimension since 1.21.9; `set` takes a diameter.
for dim_radius in "overworld:$BORDER_RADIUS" "the_nether:$NETHER_RADIUS" "the_end:$END_RADIUS"; do
  dim=${dim_radius%%:*}; radius=${dim_radius##*:}
  if [[ $dim == the_nether ]]; then cx=$((CENTER_X / 8)); cz=$((CENTER_Z / 8)); else cx=$CENTER_X; cz=$CENTER_Z; fi
  rcon "execute in minecraft:$dim run worldborder center $cx $cz"
  rcon "execute in minecraft:$dim run worldborder set $((radius * 2))"
done

# Pre-generate the overworld and nether inside their borders (the End is mostly void; skip it).
for world in world world_nether; do
  rcon "chunky world $world"
  rcon "chunky worldborder"
  rcon "chunky start"
done
rcon "chunky progress"
