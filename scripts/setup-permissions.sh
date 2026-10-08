#!/usr/bin/env bash
# Creates the LuckPerms rank ladder and grants each rank its commands. Idempotent: re-run any time.
#   default -> every player (homes, tpa, spawn, warps, economy, auction house, towns)
#   mod     -> moderation (CoreProtect lookups/rollback, Grim alerts, replay clips, kick/mute/tempban)
#   admin   -> everything
# Promote someone: make cmd C="lp user <name> parent set mod"
set -euo pipefail

CONTAINER=${1:-minecraft-server}
rcon() { docker exec "$CONTAINER" rcon-cli "$@" >/dev/null; }
grant() { local group=$1; shift; for perm in "$@"; do rcon "lp group $group permission set $perm true"; done; }
deny() { local group=$1; shift; for perm in "$@"; do rcon "lp group $group permission set $perm false"; done; }

echo "Creating groups..."
rcon "lp creategroup mod"
rcon "lp creategroup admin"
rcon "lp group mod parent add default"
rcon "lp group admin parent add mod"
rcon "lp group mod meta setprefix 100 &9[Mod]&r "
rcon "lp group admin meta setprefix 200 &c[Admin]&r "
rcon "lp group mod setweight 100"
rcon "lp group admin setweight 200"

echo "Granting default (all players)..."
grant default \
  essentials.home essentials.sethome essentials.delhome essentials.sethome.multiple \
  essentials.tpa essentials.tpahere essentials.tpaccept essentials.tpdeny essentials.tpacancel \
  essentials.back essentials.back.ondeath essentials.spawn essentials.tpr \
  essentials.warp essentials.warp.list essentials.warps.* \
  essentials.balance essentials.balancetop essentials.pay essentials.sell essentials.worth \
  essentials.kit essentials.kits.starter \
  essentials.msg essentials.r essentials.mail essentials.mail.send essentials.ignore \
  essentials.afk essentials.rules essentials.motd essentials.help essentials.list essentials.seen \
  essentials.me essentials.helpop essentials.near essentials.getpos essentials.compass essentials.depth \
  essentials.chat.url \
  auctionhouse.ah
# PvP in the wild is mandatory: players must not be able to opt out with /pvp.
deny default pvpmanager.command.pvp

echo "Granting mod..."
grant mod \
  essentials.sethome.multiple.staff \
  essentials.kick essentials.mute essentials.tempban essentials.ban essentials.unban essentials.jail essentials.togglejail \
  essentials.vanish essentials.tp essentials.tphere essentials.invsee essentials.whois essentials.socialspy \
  essentials.helpop.receive essentials.seen.extra essentials.mail.sendall \
  coreprotect.inspect coreprotect.lookup coreprotect.rollback coreprotect.restore coreprotect.teleport \
  grim.alerts grim.alerts.enable-on-join grim.verbose \
  flashbackserver.replay \
  pvpmanager.command.pvpinfo.others pvpmanager.command.pvpstatus.others pvpmanager.command.untag

echo "Granting admin..."
grant admin '*'

echo "Done. Ranks: $(docker exec "$CONTAINER" rcon-cli 'lp listgroups' | tr -s ' ' | head -c 300)"
