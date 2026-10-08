# Minecraft Server

A community survival server: PaperMC 1.21.11 on the [itzg/minecraft-server](https://docker-minecraft-server.readthedocs.io/) image, with Geyser + Floodgate so Bedrock players can join.

- **Safe zones**: spawn is a protected WorldGuard region; Towny town claims are build-protected and PvP-free.
- **PvP**: on everywhere else (the wilderness). Combat logging is punished by PvPManager, and players can't opt out with `/pvp`.
- Everything is free and open source.

## Commands

| Command | What it does |
|---|---|
| `make start` | Starts the server (and the backup sidecar), then tails logs. Ctrl+C leaves it running. |
| `make stop` | Stops everything. World data stays in `./server`. |
| `make console` | Attaches to the server console. Ctrl+P, Ctrl+Q to detach. |
| `make cmd C="..."` | Runs one console command, e.g. `make cmd C="lp user Steve parent set mod"`. |
| `make setup-perms` | Creates the `default`/`mod`/`admin` ranks and their permissions. Run once after the first start. |
| `make setup-spawn` | Creates the PvP-free spawn region around the world's spawn point. Re-run after a world reset. |
| `make pregen` | Sets world borders (5,000-block radius) and pre-generates the world. Takes hours; run with nobody online. |
| `make backup-now` | Takes a backup immediately. Automatic backups run every 6 hours into `./backups` and are kept 7 days. |

First run: `make start`, wait for `Done`, then `make setup-perms`, `make setup-spawn` and `make pregen`.

## Ports

| Port | Use | Exposed |
|---|---|---|
| 25565/tcp | Java Edition | Public |
| 19132/udp | Bedrock Edition | Public |
| 8100 | BlueMap live map, http://localhost:8100 | localhost only |
| 8804 | Plan player stats, http://localhost:8804 | localhost only |

To share the map or stats publicly, put a reverse proxy or Cloudflare Tunnel in front of 8100/8804 rather than opening the ports.

## Plugins

Plugins are declared in [`config/plugins.txt`](config/plugins.txt), pinned to versions that support 1.21.11. The image downloads them from Modrinth on every start and removes any you delete from the list. Geyser and Floodgate always track their latest builds (Bedrock clients auto-update), and the MCXboxBroadcast Geyser extension is fetched by the `geyser-extensions` service in `docker-compose.yml`.

| Need | Plugin | Player commands |
|---|---|---|
| Homes, teleports, spawn, economy | EssentialsX (+ Spawn, Chat) | `/sethome`, `/home`, `/tpa`, `/tpaccept`, `/back`, `/spawn`, `/tpr`, `/bal`, `/pay`, `/sell` |
| Towns, nations, land claims | Towny | `/t new <name>`, `/t claim`, `/t add <player>`, `/n new <name>` |
| Safe spawn | WorldGuard + WorldEdit | — |
| Combat logging | PvPManager | `/pvpstatus`, `/tag` |
| Grief logging + rollback | CoreProtect | staff: `/co i`, `/co rollback` |
| Anticheat | GrimAC (exempts Bedrock players) | — |
| World border pre-gen | Chunky | — |
| Live map with town borders | BlueMap + BlueMap-Towny | — |
| Player stats | Plan (web), ajLeaderboards + DecentHolograms (in-game) | — |
| Auction house | Auction House | `/ah`, `/ah sell <price>` |
| Clips | Flashback Server | staff: `/replay clip save <player>` |
| Ranks, tablist | LuckPerms, TAB, PlaceholderAPI, VaultUnlocked | — |
| Bedrock/newer Java clients | ViaVersion (the latest Geyser speaks 26.x; ViaVersion bridges it to 1.21.11) | — |

Paper ships spark built in, so `/spark` works without a plugin.

### Safe zones and PvP

PvP is on in the world; these layers turn it off where people should be safe:

- **Spawn**: `make setup-spawn` creates the WorldGuard region `spawn`, a 96×96 column around world spawn with PvP, explosions and fire spread off. Building there is still allowed; `/rg flag spawn build deny` locks it to staff. To stop players claiming right next to spawn, turn it into a server-owned town (see below).
- **Towns**: Towny's town default is `pvp: false`, and mayors can't toggle it back on (`-towny.command.town.toggle.pvp` in `townyperms.yml`). Town plots are build-protected from outsiders.
- **Wilderness**: anyone can build (grief is handled by CoreProtect rollbacks) and PvP is on. PvPManager gives new players 10 minutes of protection, tags players in combat for 15 seconds, blocks teleport commands while tagged, and punishes logging out mid-fight. EssentialsX teleports have a 3-second warmup.

### Spawn town

Make spawn a town owned by the server so nobody can claim it and its 5-chunk buffer:

1. Stand at spawn as an admin and run `/eco give <you> 1000`, `/t new Spawn`, `/ta givebonus Spawn 30` (lifts the claim limit), then `/t claim rect 2` (a 5×5-chunk square around you).
2. `/ta set mayor Spawn npc` hands the town to an NPC mayor; then `/t leave` so you can found or join your own town.
3. Optional: `/plot set embassy` on plots (as admin) and `/plot forsale <price>` lets players from any town buy a shop or base plot at spawn.

### How players claim land

- Found a town anywhere in the wilderness: `/t new <name>`. The chunk you're standing in becomes your home block.
- Expand: `/t claim` for the chunk you're in, `/t claim rect 2` for a square. Claims must touch your town unless you buy an outpost (`/t claim outpost`, $500).
- Invite friends: `/t add <player>`; they accept with `/invite accept <town>`. Or `/t toggle open` so anyone can `/t join <town>`.
- Each player can be in one town. Towns can team up: `/n new <name>` makes a nation, and `/n add <town>` invites others.
- Group size is capped so no single clan dominates: 10 players per town, 3 towns or 20 players per nation, and 2 allied nations. Land only grows by recruiting (8 chunks per member). Tune these in `server/plugins/Towny/settings/config.yml` (`max_residents_per_town`, `max_towns_per_nation`, `max_residents_per_nation`, `max_allies`, `town_block_ratio`).
- Towns must keep 5 chunks between their land and other towns' land, so nobody can box you in.

Towns cost $100 to found and $25 per extra chunk, with no daily upkeep. A town can claim 8 chunks per resident plus 8 bonus chunks, so a solo player gets 16 (a 64×64-block area is 16 chunks). Players start with $100 and earn more with `/sell` (prices in `server/plugins/Essentials/worth.yml`) and by trading on `/ah`.

### Clips

Flashback Server keeps a rolling 30-second buffer per player and auto-saves a clip on death. Staff save one on demand with `/replay clip save <player>`. Clips land in `server/plugins/FlashbackServer/` as `.flashback` files; open them in the [Flashback](https://modrinth.com/mod/flashback) client mod (Fabric) to watch from any angle and export video.

## Updating

- **Plugins**: change the version in `config/plugins.txt`, then `make stop && make start`.
- **Minecraft**: `VERSION` in `docker-compose.yml` is pinned. Don't set it to `LATEST`; that now resolves to 26.x, world upgrades are one-way, and most plugins here need different builds. Back up first.
