# Patch two leaks, then build your SMP

Two problems in the repo come before any plugin work. First, `christophermarek/minecraft-server` is a **public** GitHub repo, and it tracks the Floodgate private key and a live Microsoft/Xbox session (including a refresh token). Second, `start.sh` depends on a PaperMC download API that was **shut down on 2026-07-01**, so the next container restart deletes the working server jar and the server does not come back. Fix both today. Then move the server to **Paper 1.21.11**, the final 1.21 release, under `itzg/docker-minecraft-server` with every version pinned. Do not stay on 1.21.10 and do not jump to 26.x. Here is the stack I recommend. **EssentialsX 2.22.0** with **VaultUnlocked** and **LuckPerms** covers homes, /tpa, /spawn, the economy and ranks. **Lands** (€19.99) gives claims with teams, nations and native Bedrock menus; **Towny** is the free alternative. A **WorldGuard** spawn region with `pvp deny` makes spawn safe. **CoreProtect CE 24.1** handles grief logging and rollback, and **GrimAC** plus Paper's built-in anti-xray handle cheating. **BlueMap 5.16** replaces Dynmap, and **Plan 5.8** with in-game leaderboards provides stats. The free **ElaineQheart Auction House** covers trading, **Chunky** pre-generates the world inside a vanilla border, and **Flashback Server** captures clips. Everything except Lands is free. Bedrock players are the main weak spot: mainstream Java anticheats exempt them, and some chest-menu interactions don't translate to Bedrock.

## Two repo problems outrank every plugin decision

### The public repo exposes a Floodgate key and live Xbox tokens

`gh repo view` reports the repo as **PUBLIC**. Two secrets are tracked in git and present on `origin/main`. **`server/plugins/floodgate/key.pem`** was added in commit `994c320 add geyser`. **`server/plugins/Geyser-Spigot/extensions/mcxboxbroadcast/cache.json`** was added in `73ab7af xboxconnect;` and contains `userToken`, `xstsToken`, an MSA `accessToken` and **`refreshToken`**, and an `xblDeviceToken.privateKey` for the Microsoft account that MCXboxBroadcast signs in with. Only the key names were inspected, not the values. The same commit also tracks `player_history.db`. Neither path is covered by `server/.gitignore`, which ignores only jars, world folders, logs and caches (local repo inspection, confirmed by the coordinator on 2026-10-08). A refresh token can mint new access tokens. Deleting the file in a new commit does not remove it from history, so treat that Microsoft account as compromised.

Rotate first, because a history rewrite cannot un-publish anything that has already been cloned. **Start by revoking the Microsoft session**: change the password of the Microsoft account MCXboxBroadcast uses and sign out of all its sessions from the account's security settings. The research could not confirm whether these Xbox tokens can be revoked one at a time, so assume only account-wide measures work, and consider moving MCXboxBroadcast to a dedicated alt account. Next, **delete `cache.json`** so the extension authenticates again on its next start. Then **replace the Floodgate key**: stop the server, delete `key.pem`, and let Floodgate generate a new one on startup. Geyser runs on the same Paper server, so it picks up the new key automatically. This key matters because it is the shared secret Geyser uses to vouch for Bedrock identities, and anyone holding the old one could forge Floodgate logins. After that, **stop tracking both files** by adding both paths to `.gitignore` and running `git rm --cached` on them. Rewriting history is optional, for example with `git filter-repo --invert-paths --path server/plugins/floodgate/key.pem --path server/plugins/Geyser-Spigot/extensions/mcxboxbroadcast/cache.json` followed by a force-push. Forks and existing clones keep the old objects, which is why revocation, not the rewrite, is what actually protects you.

The rest of the build makes this worse unless the ignore policy changes. DiscordSRV bot tokens, the RCON password, restic repository passwords, and the Plan and CoreProtect databases will all land under `server/`. Switch to an allowlist: ignore `server/plugins/**`, then un-ignore only the specific `config.yml` files you want versioned.

### `start.sh` deletes its own server jar on the next restart

PaperMC froze its v2 download API on 2025-12-31 and **disabled it on 2026-07-01** ([itzg #3517 quoting PaperMC](https://github.com/itzg/docker-minecraft-server/issues/3517)). A live request to `api.papermc.io/v2/projects/paper` now returns `{"ok":false,"error":"sunset"}`, and other hosting panels hit the same wall in July ([CubeCoders forum](https://discourse.cubecoders.com/t/minecraft-module-downgrades-paper-on-every-start-version-feed-appears-stale-after-papermc-v2-api-sunset/41289)).

The script still calls v2, and it fails destructively. With the Makefile default `MC_VERSION=latest`, `jq '.versions[-1]'` returns `null` and the build resolves to `null`, giving `JAR_NAME=paper-null-null.jar`. That file does not exist, so the script runs `rm -f *.jar` and **removes the working `paper-1.21.10-115` jar**. The `wget` that follows fails, so the container never starts. Setting `MC_VERSION=1.21.10` does not help, because the build lookup still returns `null`. There is a second trap behind the first. Fixing the API call while leaving `latest` would now resolve to **26.3**, because Fill lists `26.3` first ([PaperMC Downloads Service](https://docs.papermc.io/misc/downloads-service/)). That would be an irreversible world upgrade that most of this stack does not support.

The replacement is **Fill v3** at `https://fill.papermc.io/v3/projects/paper/versions/{version}/builds`. Filter for `channel == "STABLE"`, take the download URL from `downloads."server:default".url` instead of building it yourself, and send a User-Agent that names your project and gives a contact URL ([PaperMC docs](https://docs.papermc.io/misc/downloads-service/)). On 2026-10-08, 1.21.10's newest build was **130 STABLE**, and the server runs 115. If you keep the custom Alpine image, this patch follows the documented pattern. It is untested, so run it once before relying on it, and confirm the checksum field path against Fill's Swagger:

```bash
UA="christophermarek-minecraft-server/1.0 (https://github.com/christophermarek/minecraft-server)"
: "${MC_VERSION:=1.21.11}"     # pin; never "latest"
API="https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds"
BUILD_JSON=$(wget -qO- -U "$UA" "$API" | jq -c 'map(select(.channel=="STABLE"))[0] // empty') || true
if [[ -n $BUILD_JSON ]]; then
  PAPER_BUILD=$(jq -r '.id' <<<"$BUILD_JSON")
  URL=$(jq -r '.downloads."server:default".url' <<<"$BUILD_JSON")
  SHA=$(jq -r '.downloads."server:default".checksums.sha256' <<<"$BUILD_JSON")
  JAR_NAME="paper-${MC_VERSION}-${PAPER_BUILD}.jar"
  if [[ ! -e $JAR_NAME ]]; then
    wget -q -U "$UA" "$URL" -O "$JAR_NAME.tmp" && echo "$SHA  $JAR_NAME.tmp" | sha256sum -c - \
      && rm -f paper-*.jar && mv "$JAR_NAME.tmp" "$JAR_NAME"
  fi
fi
JAR_NAME=$(ls -t paper-*.jar | head -1)   # fall back to the existing jar if the API is unreachable
```

The old jar is deleted only after a verified download, and an API outage falls back to the jar already on disk. Also change `MC_VERSION ?= latest` in the Makefile. The better long-term fix is to drop the custom script entirely, as described in the next section.

## Move to Paper 1.21.11 once, then freeze it

**Recommendation: upgrade 1.21.10 → 1.21.11 now, then pin it.** The deciding factor is EssentialsX, the plugin behind /home, /tpa, /spawn, kits and the economy. **EssentialsX 2.22.0** (2026-05-31) is the only release since August 2025, and it "fixes several item duplication and server crash exploits". Its release notes list 1.21.11 and 26.1.2 as supported and **do not list 1.21.10** ([EssentialsX 2.22.0](https://github.com/EssentialsX/Essentials/releases/tag/2.22.0)). The code agrees: `VersionUtil.supportedVersions` contains `1.21.11-R0.1-SNAPSHOT`, and any other version gets `SupportStatus.OUTDATED` with `supported=false` ([VersionUtil.java @2.22.0](https://github.com/EssentialsX/Essentials/blob/2.22.0/Essentials/src/main/java/com/earth2me/essentials/utils/VersionUtil.java)). It will most likely still run on 1.21.10, but you would be on an officially unsupported combination for your most important plugin. The pattern repeats elsewhere. HuskHomes tags 1.21.11 but not 1.21.10 ([Modrinth](https://modrinth.com/plugin/huskhomes)). WorldGuard has exactly one stable release for 1.21.10 (7.0.15), and 7.0.16 is "Update to 1.21.11" ([Modrinth WorldGuard](https://modrinth.com/plugin/worldguard)). squaremap ties each build to a single MC version ([Modrinth squaremap](https://api.modrinth.com/v2/project/squaremap/version)). On 1.21.10 you are pinning dead-end builds. On 1.21.11 you get the last build each 1.21-line plugin will ever target, and most plugins' version ranges cover it.

The case for staying on 1.21.10 is that 1.21.10 → 1.21.11 is still a one-way world upgrade, and every plugin in the table below does have a working 1.21.10 build. That holds only if you accept EssentialsX running unsupported. Take a full offline backup before the upgrade and the risk is small. Do not go to 26.x yet. The ecosystem is moving there and the 1.21 line is now frozen, but Dynmap has no 26.x release at all ([SpigotMC Dynmap](https://www.spigotmc.org/resources/dynmap%C2%AE.274/updates)), and this research validated pins only for 1.21.x. Plan a deliberate 26.x migration later, once your claims and map plugins confirm support.

Run the server on **`itzg/minecraft-server` with `TYPE=PAPER` and `VERSION=1.21.11`**. itzg's mc-image-helper moved to Fill v3 in mid-2025, a year before the v2 shutdown, and it is actively released (docker-minecraft-server 2026.9.2). It installs plugins from Modrinth through `MODRINTH_PROJECTS` with `Project:Version` pinning and `?` for optional entries, and from direct URLs through `PLUGINS` ([itzg Modrinth docs](https://docker-minecraft-server.readthedocs.io/en/latest/mods-and-plugins/modrinth/); [itzg plugins docs](https://docker-minecraft-server.readthedocs.io/en/latest/mods-and-plugins/)). RCON is enabled by default ([itzg RCON](https://docker-minecraft-server.readthedocs.io/en/latest/sending-commands/commands/)). One caution: unpinned Modrinth entries are upgraded to the newest compatible release on every start. That makes itzg an auto-updater, which PaperMC advises against in production ([PaperMC docs](https://docs.papermc.io/misc/downloads-service/)). Pin every entry and raise versions deliberately.

Several plugins in this stack can't come from Modrinth for Paper. Floodgate comes from the GeyserMC download API. spark has no Paper build on Modrinth or Hangar, so keep your existing jar. MCXboxBroadcast is a Geyser extension, not a plugin, and goes in `Geyser-Spigot/extensions/`. Lands, Jobs Reborn, CMILib and EconomyShopGUI come from SpigotMC, and EssentialsX blocks automated Spiget downloads ([itzg Spiget docs](https://docker-minecraft-server.readthedocs.io/en/latest/mods-and-plugins/spiget/)). Put all of these in a read-only `/plugins` mount. A skeleton:

```yaml
services:
  mc:
    image: itzg/minecraft-server
    environment:
      EULA: "TRUE"
      TYPE: PAPER
      VERSION: "1.21.11"            # pin; Paper build floats within 1.21.11 STABLE
      MEMORY: 10G
      USE_AIKAR_FLAGS: "true"
      RCON_PASSWORD_FILE: /run/secrets/rcon
      MODRINTH_PROJECTS: |          # verify each version string on Modrinth before use
        geyser
        luckperms:v5.5.71
        vaultunlocked:2.20.3
        placeholderapi:2.12.3
        worldedit:7.4.3
        worldguard:7.0.16
        coreprotect:24.1
        chunky:1.4.40
        bluemap:5.16
        plan
        grimac
        tab-was-taken:6.2.0
      PLUGINS: |
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
    ports: ["25565:25565/tcp", "19132:19132/udp"]   # never publish 25575, 8100 or 8804
    volumes: ["./server:/data", "./plugins-manual:/plugins:ro"]
  backup:
    image: itzg/mc-backup
    environment: { BACKUP_METHOD: restic, BACKUP_INTERVAL: "3h", RCON_HOST: mc,
                   PRUNE_RESTIC_RETENTION: "--keep-hourly 24 --keep-daily 14 --keep-weekly 8" }
  caddy:
    image: caddy           # map.example.com -> mc:8100, stats.example.com -> mc:8804
```

The `itzg/mc-backup` sidecar handles `save-off`/`save-all`/`save-on` over RCON and supports restic for deduplicated, offsite backups ([itzg/docker-mc-backup](https://github.com/itzg/docker-mc-backup)). Keep Geyser on its latest build, because Bedrock clients update themselves. Its current build (2.11.3-b1249, 2026-10-06) still targets 1.21.10-era Paper. For the heap, PaperMC recommends 6–10 GB with Aikar's G1 flags and Xms equal to Xmx ([PaperMC Aikar's flags](https://docs.papermc.io/paper/aikars-flags/)). itzg advises a container limit about 25% above the heap ([itzg JVM options](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/jvm-options/)). That works out to `MEMORY=8G` for about 20–30 players and 10–12G for about 50. Also lower the repo's `simulation-distance=10` to 5–6 and `view-distance` to 8 ([minecraft-optimization guide](https://github.com/YouHaveTrouble/minecraft-optimization)).

## The recommended stack: one €19.99 purchase, everything else free

The table lists the versions to pin. "1.21.11 pin" is what to run after the recommended upgrade. "1.21.10 pin" is the fallback if you stay where you are. Versions were checked against the Modrinth, Hangar, Spiget and GitHub APIs on 2026-10-08.

| Need | Pick | 1.21.11 pin | 1.21.10 pin | Cost | Source |
|---|---|---|---|---|---|
| Server | Paper | latest STABLE 1.21.11 (confirm on Fill) | build 130 | Free | [Fill docs](https://docs.papermc.io/misc/downloads-service/) |
| Crossplay | Geyser / Floodgate / MCXboxBroadcast | latest / latest / build 116 | same | Free | [itzg plugins](https://docker-minecraft-server.readthedocs.io/en/latest/mods-and-plugins/) |
| Profiler | spark (already installed) | keep current | same | Free | — |
| Perms, ranks | LuckPerms | v5.5.71 | v5.5.71 | Free | [Modrinth](https://modrinth.com/plugin/luckperms) |
| Placeholders, tablist | PlaceholderAPI, TAB | 2.12.3, 6.2.0 | same | Free | [PAPI](https://modrinth.com/plugin/placeholderapi), [TAB](https://modrinth.com/plugin/tab-was-taken) |
| Economy API | VaultUnlocked | 2.20.3 | 2.20.3 | Free | [Modrinth](https://modrinth.com/plugin/vaultunlocked) |
| /home /tpa /spawn /back /rtp, kits, money | EssentialsX + Chat + Spawn | 2.22.0 | 2.22.0 (unsupported) | Free | [Release](https://github.com/EssentialsX/Essentials/releases/tag/2.22.0) |
| Claims with teams | **Lands** | 8.6.8 (confirm 1.21.x build) | ask vendor | **€19.99** | [Spiget 53313](https://api.spiget.org/v2/resources/53313) |
| Free claims alternative | Towny | 0.103.2.0 | 0.103.2.0 | Free | [Modrinth](https://api.modrinth.com/v2/project/towny/version) |
| Spawn region, selections | WorldGuard + WorldEdit | 7.0.16 + 7.4.3 | 7.0.15 + 7.4.3 | Free | [WG](https://api.modrinth.com/v2/project/worldguard/version), [WE](https://api.modrinth.com/v2/project/worldedit/version) |
| Combat log, newbie PvP shield | PvPManager Lite | 4.0.22 | 4.0.22 | Free | [Modrinth](https://api.modrinth.com/v2/project/pvpmanager/version) |
| Grief logging, rollback | CoreProtect CE | 24.1 | 24.1 | Free | [Modrinth](https://api.modrinth.com/v2/project/coreprotect/version) |
| Anticheat (Java) | GrimAC | 2.3.74-f5bbe9c (confirm tag) | 2.3.74-f5bbe9c | Free | [Modrinth](https://modrinth.com/plugin/grimac) |
| Anti-xray | Paper built-in, engine-mode 2 | — | — | Free | [Paper docs](https://docs.papermc.io/paper/anti-xray/) |
| Border, pregen | Vanilla border + Chunky | 1.4.40 | 1.4.40 | Free | [Chunky wiki](https://github.com/pop4959/Chunky/wiki/Commands) |
| Live web map | BlueMap (+ BlueMap Floodgate addon) | 5.16-paper | 5.16-paper | Free | [Modrinth](https://api.modrinth.com/v2/project/bluemap/version) |
| Stats (web) | Plan | 5.8 build 3638 (confirm tag) | 5.8 build 3638 | Free | [Modrinth](https://api.modrinth.com/v2/project/plan/version) |
| Stats (in-game) | ajLeaderboards + DecentHolograms | 2.11.0-b338 + 2.10.1 | same | Free | [ajLB](https://modrinth.com/plugin/ajleaderboards/versions), [DH](https://modrinth.com/plugin/decentholograms/versions) |
| Auction house | Auction House (ElaineQheart) | 1.5.5 | 1.5.5 | Free | [Hangar](https://hangar.papermc.io/ElaineQheart/AuctionHousePlugin) |
| Money in / player shops | Jobs Reborn + CMILib, EconomyShopGUI, QuickShop-Hikari | latest Spigot, latest Spigot, 6.3.0.3 | same | Free | [Jobs](https://www.spigotmc.org/resources/jobs-reborn.4216/), [ESGUI](https://www.spigotmc.org/resources/economyshopgui.69927/), [QS](https://modrinth.com/plugin/quickshop-hikari) |
| Clips | Flashback Server | 1.2.2 | 1.2.2 | Free | [Modrinth](https://modrinth.com/plugin/flashback-server) |
| Staff replay review | BetterReplay (needs PacketEvents, FoliaLib) | 1.5.0 | 1.5.0 | Free | [Modrinth](https://modrinth.com/plugin/betterreplay) |
| Discord bridge, votes | DiscordSRV; VotingPlugin + azuvotifier | 1.30.5; 7.1.1 + 3.3.6 | same | Free | [DiscordSRV](https://modrinth.com/plugin/discordsrv), [azuvotifier](https://modrinth.com/plugin/azuvotifier) |

**Claims are the one place worth paying.** You asked for groups and teams, and with Bedrock crossplay that narrows the field quickly. GriefPrevention 16.18.7 is excellent and free, but it has **no groups**, only per-claim trust lists ([GP docs](https://docs.griefprevention.com/)). **Lands** has members, roles, ally and enemy relations, nations and an optional war system. **When Floodgate is present, every Lands GUI renders as a native Bedrock form** ([Lands wiki](https://wiki.incredibleplugins.com/general/gui-menus/bedrock-forms.md)). It also draws claims natively on BlueMap, squaremap, Pl3xMap and Dynmap ([Lands web maps](https://wiki.incredibleplugins.com/lands/integrations-and-ui/web-maps.md)). The open question is version support. The newest Lands, 8.6.8, advertises 26.x support, and Spigot's tested-versions field says only "1.21". Confirm which build supports 1.21.11 with IncrediblePlugins before you buy. **Towny 0.103.2.0** is the free route to towns and nations. It is very actively maintained, but it is command-driven, has no documented Bedrock forms, and **ships with town PvP turned on** ([Towny ConfigNodes](https://github.com/TownyAdvanced/Towny/blob/master/Towny/src/main/java/com/palmergames/bukkit/config/ConfigNodes.java)). Skip HuskClaims for now: its last release targets 1.21.7 ([HuskClaims releases](https://github.com/WiIIiam278/HuskClaims/releases)).

**BlueMap beats Dynmap for a new 2026 build.** Dynmap 3.8 does run on 1.21.10 and 1.21.11, but it has no 26.x release, its high-res templates "can take a VERY long time for initial fullrender", and it renders continuously as players explore ([Dynmap config](https://github.com/webbukkit/dynmap/blob/v3.0/spigot/src/main/resources/configuration.txt)). BlueMap 5.16 is the last build that supports 1.21.10 and 1.21.11. It renders in 3D, serves on port 8100, can be hosted as static files behind Caddy with only `/maps/*/live/*` proxied ([BlueMap external webserver](https://bluemap.bluecolored.de/wiki/webserver/ExternalWebserversFile.html)), and has a "BlueMap Floodgate" addon for Bedrock skins ([BlueMap addons](https://github.com/BlueMap-Minecraft/BlueMapWiki/blob/master/assets/addon_browser/addons.conf)). Set `hide-vanished: true` so staff in vanish stay off the map. There is one exception. If you choose GriefPrevention instead of Lands, use **squaremap** (1.3.12 on 1.21.11, 1.3.9 on 1.21.10), because only squaremap has maintained first-party GriefPrevention and WorldGuard marker addons ([squaremap-addons](https://github.com/jpenilla/squaremap-addons)).

**Stats need two layers.** Plan 5.8 is the staff analytics panel. It runs on port 8804, recognizes Bedrock players through its Floodgate integration, and supports SQLite, H2 and MySQL ([Plan wiki](https://github.com/plan-player-analytics/Plan/wiki/Bukkit-Configuration)). Download it **only from the current official Modrinth project or GitHub**. An impersonator controlled Plan's Modrinth page from 15 Feb to 11 Mar 2025 and distributed builds with backdoor malware ([Plan Modrinth](https://modrinth.com/plugin/plan)). Plan's login works only over HTTPS. Behind Caddy, set `KeyStore_path: proxy` and `Alternative_IP` ([Plan HTTPS wiki](https://github.com/plan-player-analytics/Plan/wiki/SSL-Certificate-(HTTPS)-Set-Up)), and give players `access.player.self` so each player sees only their own page ([Plan web permissions](https://github.com/plan-player-analytics/Plan/wiki/Web-permissions)). For bragging rights that players will actually see, put ajLeaderboards holograms at spawn.

**For the auction house, Bedrock's input model matters more than features.** Geyser cannot distinguish left from right clicks in inventories, and chat links aren't clickable ([Geyser limitations](https://geysermc.org/wiki/geyser/current-limitations/)). That rules out any auction GUI that uses left-click to buy and right-click to cancel. The **ElaineQheart Auction House 1.5.5** (GPL-3.0) lists items with a typed `/ah sell` command, supports bidding with anti-snipe time, and requires Vault or VaultUnlocked. The paid upgrade is **zAuctionHouse V4** (€12.99), which adds taxes, Redis and configurable menus. Its free Modrinth demo trails the paid version by one release ([zAuctionHouse](https://www.spigotmc.org/resources/zauctionhouse.63010/)). Avoid Fadah and CrazyAuctions on 1.21.x, because neither has a current stable build for it. On the money side, Jobs Reborn and a server sell shop put money in, and QuickShop chest shops plus auction listing fees move it around and take it out. Bedrock players also need to type `/tpaccept`, because EssentialsX's clickable accept button doesn't work for them.

**Anticheat leaves Bedrock players effectively unchecked.** GrimAC is free, GPL-3.0, and had a new build on 2026-10-07. It exempts Geyser players entirely, and it needs Floodgate on the same backend to do that, which your setup already has ([Grim README](https://github.com/GrimAnticheat/Grim)). Vulcan ($19.99) also skips Bedrock players ([Spiget 83626](https://api.spiget.org/v2/resources/83626)), so paying for it buys fewer false positives on Java but nothing for Bedrock. The only Bedrock-side checker is the **Boar** Geyser extension, and its author calls it early-development and says to "expect falses" ([Modrinth Boar](https://modrinth.com/plugin/boar)). If you add it, run it in alert-only mode. Paper's built-in anti-xray works on chunk packets, so it protects against x-ray on both editions. Use **engine-mode 2** (fake ores), or mode 3, which cuts network load at join by roughly half ([Paper Anti-Xray](https://docs.papermc.io/paper/anti-xray/)). Avoid NoCheatPlus, which false-flags Bedrock players ([Geyser anticheat page](https://geysermc.org/wiki/geyser/anticheat-compatibility/)).

**Clips work, but the server-side recorder everyone cites doesn't run on Paper.** ServerReplay is Fabric-only ([Modrinth](https://modrinth.com/mod/server-replay)). On Paper, use **Flashback Server 1.2.2** (MIT, no dependencies). It keeps a rolling per-player buffer, `clips.window-seconds: 30`, saves it with `/replay clip save <player>`, and auto-clips on death by default. It writes `.flashback` files that staff or creators open in the Flashback Fabric client mod to render video. Set `telemetry.enabled: false` ([Flashback Server](https://modrinth.com/plugin/flashback-server)). For moderation, **BetterReplay 1.5.0** plays recordings back in-game with no client mod, has a Floodgate soft-dependency, and exposes an API for auto-recording ([BetterReplay](https://modrinth.com/plugin/betterreplay)). Because Geyser runs on Paper, Bedrock players appear to the server as normal players, so these recorders should capture them too. That is untested, so check it in step 9.

## Spawn and claims are safe, the wilderness is PvP

The model has three layers. PvP is on for the whole world. A WorldGuard region turns it off at spawn. The claims plugin turns it off inside claims.

**World level.** The repo's `server.properties` has no `pvp=` line. That fits 1.21.9 turning PvP into a per-world game rule. Confirm with `/gamerule pvp` in each dimension (and `execute in minecraft:the_nether run gamerule pvp`), and make sure it is `true`.

**Spawn.** WorldGuard's `pvp` state flag controls player combat, and at equal priority `deny` beats `allow` ([WorldGuard flags](https://worldguard.enginehub.org/en/latest/regions/flags/)):

```
//wand                                   (select the spawn corners, full height)
/rg define spawn
/rg setpriority spawn 10
/rg flag spawn pvp deny
/rg flag spawn build deny
/rg flag spawn mob-spawning deny
/rg flag spawn creeper-explosion deny
/rg flag spawn tnt deny
/rg flag spawn invincible allow          (optional)
/rg flag spawn greeting &aSafe zone – PvP disabled
```

With Lands, WorldGuard regions get Lands' `lands-claim` flag set to deny by default, so nobody can claim spawn ([Lands wiki](https://wiki.incredibleplugins.com/lands/llms-full.txt)). Add `/rg flag spawn lands-claim deny` explicitly anyway. With GriefPrevention, put an `/adminclaim` over spawn and `/trust public` it ([GP docs](https://docs.griefprevention.com/configuration/)).

**Claims with Lands.** Land PvP is the "attack player" role flag. Owners can toggle it, so force it off for every role in `roles.yml`. That way no owner can turn their land into an arena. Lands also has `combat.tag-time: 15s`: a player who attacks someone can be hit back "regardless of land settings" ([Lands FAQ](https://wiki.incredibleplugins.com/lands/llms-full.txt)). I recommend keeping it. It only affects players who started a fight, so claims stay safe for everyone else, and it stops hit-and-hide abuse along claim borders. Tell players about it in `/rules`.

**Claims with Towny or GriefPrevention.** For Towny, set `default_perm_flags.town.default.pvp: "false"`, keep `new_world_settings.pvp.world_pvp: true` and `force_pvp_on: false`, run `/t toggle pvp` on any town created before the change, and deny `towny.command.town.toggle.pvp` in LuckPerms so towns can't switch it back ([Towny ConfigNodes](https://github.com/TownyAdvanced/Towny/blob/master/Towny/src/main/java/com/palmergames/bukkit/config/ConfigNodes.java)). GriefPrevention is safe out of the box: `PvP.ProtectPlayersInLandClaims.PlayerOwnedClaims: true` applies as long as GP's PvP rules are enabled in the world, and GP ships `PunishLogout`, a 15 s combat timeout and fresh-spawn protection ([GP source](https://github.com/GriefPrevention/GriefPrevention/blob/master/src/main/java/me/ryanhamshire/GriefPrevention/GriefPrevention.java)).

**Wilderness fairness.** With Lands or Towny, add **PvPManager Lite 4.0.22** for newbie protection, combat tagging and combat-log punishment. Deny its per-player `/pvp` toggle permission, or players will simply opt out of wilderness PvP ([PvPManager](https://modrinth.com/plugin/pvpmanager)). If you run GP, use its built-in logout punishment, or PvPManager's, but not both. Test with one Java account and one Bedrock account at each layer: inside spawn, inside a claim (as a member, an outsider and a tagged aggressor), and in the open wild.

## Border at 5,000 blocks and pre-generate before launch

Since 1.21.9 the vanilla world border is set separately for each dimension ([Minecraft Wiki](https://minecraft.wiki/w/World_border)). Use it rather than a plugin border. It also limits the treasure-map structure searches that cause lag spikes ([optimization guide](https://github.com/YouHaveTrouble/minecraft-optimization)), and Chunky can read it directly. For 10–25 players, set an overworld **radius of 5,000** (about 390k chunks as a square). For 25–50, use 7,500–10,000. Give the Nether about one-eighth of that. Growing the border later is easy and shrinking it is not. Published pregen times disagree widely: a 10k radius is quoted at 5–15 hours on good hardware and 3–5× slower on a 2-core VPS ([supercraft guide](https://www.supercraft.host/wiki/minecraft/chunky_pregeneration_guide/); [space-node guide](https://space-node.net/blog/minecraft-world-pregeneration-chunky-guide-2026)). Disk estimates differ by 10× or more. Measure on your own hardware: run radius 1,000 first, record elapsed time and `du -sh world/region`, then extrapolate.

```
worldborder center 0 0
worldborder set 10000                                  # diameter → radius 5000
execute in minecraft:the_nether run worldborder set 1500
execute in minecraft:the_end run worldborder set 8000
chunky world world        → chunky worldborder → chunky start
chunky world world_nether → chunky worldborder → chunky start
```

The `execute in` syntax for setting a per-dimension border was not checked against the wiki, so try it on a test world first. Run the pregen with no players online ([Chunky wiki](https://github.com/pop4959/Chunky/wiki/Commands)). Afterwards, BlueMap will render the whole bordered area, which also takes hours. Exclude BlueMap's tiles from backups, since they can be regenerated.

## Roll out in ten stages, each covered by a backup

Each stage ends with a check you can verify before moving on. Back up before each stage. That way the whole stack goes in without a big-bang launch, and Bedrock problems surface while there is still only one Bedrock tester.

| # | Stage | What to do | Done when |
|---|---|---|---|
| 0 | Contain secrets (today) | Revoke the Microsoft sessions, delete `cache.json`, regenerate `key.pem`, gitignore both plus `server/plugins/**`, optionally run filter-repo and force-push | `git ls-files` shows neither path. Bedrock and Xbox-friend joins work with the new key |
| 1 | Fix the launcher | Take an offline tarball of `server/`, then move to itzg with `VERSION` pinned (or apply the Fill v3 patch and change the Makefile default) | Two restarts in a row neither re-download nor delete the jar |
| 2 | Upgrade and back up | Run 1.21.11 with only Geyser, Floodgate, MCXboxBroadcast and spark. Add mc-backup with restic every 3 h and keep RCON internal only | Java and Bedrock both join. A test restore succeeds |
| 3 | Foundation | Install LuckPerms (default → member → regular → veteran track), VaultUnlocked, PlaceholderAPI, EssentialsX + Chat + Spawn (`sethome-multiple` 3/5/10, `newbies` kit), TAB, WorldEdit, WorldGuard, CoreProtect | The economy is detected at startup. `/co i` logs a test break, and `/co rollback` restores it |
| 4 | World | Set the vanilla borders, run the r=1,000 timing test, then full Chunky pregen offline. Apply view 8 / simulation 5–6 and anti-xray engine-mode 2 | Chunky reports complete. `/spark health` is clean with no players online |
| 5 | Safe zones | Build spawn, add the WorldGuard region and flags, install Lands (or Towny/GP) with forced no-PvP, and add PvPManager | The Java + Bedrock PvP matrix from the safe-zone section passes |
| 6 | Anticheat | Install GrimAC (optionally Boar in alert-only mode), and send alerts to a staff Discord channel through DiscordSRV | No false flags on Bedrock testers during an hour of play |
| 7 | Map and stats | Install BlueMap 5.16 with Lands markers and the Floodgate addon behind Caddy HTTPS. Add Plan with proxy keystore, plus ajLeaderboards holograms | Ports 8100, 8804 and 25575 can't be reached from outside. Map and Plan load over HTTPS |
| 8 | Economy | Install Jobs Reborn + CMILib, EconomyShopGUI (keep sell prices low), QuickShop-Hikari and the Auction House | A Bedrock player can list, buy and cancel an auction |
| 9 | Clips, onboarding, launch | Install Flashback Server (telemetry off) and BetterReplay, set up VotingPlugin + azuvotifier, `/rules` and the MOTD. Do a whitelisted soft launch, then run a `spark profiler` during peak | A Bedrock player's death clip opens in Flashback. Peak MSPT stays under budget |

## Conclusion

Most of the risk in this build has nothing to do with choosing plugins. It comes from version drift and secrets. Minecraft's move to year-based 26.x versions froze the 1.21 line. As a result, "latest" became a dangerous default for both the Paper jar and each plugin, and every component now needs an explicit pin. Moving to 1.21.11 lines you up with the last 1.21 build each plugin will ever ship, and itzg's pinned `MODRINTH_PROJECTS` turns the plugin list into a reviewable manifest instead of a folder of jars. The same discipline applies to secrets. The repo already leaked two of them, and this stack adds several more (Discord bot token, RCON and restic passwords, databases), so the allowlist `.gitignore` belongs in step 0, not after the next incident.

Crossplay has a cost the feature list hides. Bedrock players skip the anticheat, can't use right-click menus or clickable chat, and haven't been tested end to end with the replay recorders. Moderation for them therefore rests on CoreProtect logs, server-side anti-xray and replay evidence. The plugins most likely to help that half of your player base are the ones built for Bedrock: Lands' native forms, typed-command auction listing, and BlueMap's Floodgate skins. Those features also pay for themselves in fewer support questions.
