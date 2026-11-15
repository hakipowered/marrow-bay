#!/usr/bin/env bash
# Playtest gate: run this before every build, and don't ship while it fails.
#
#   tools/playtest.sh          quick pass, about 6 minutes on 4 cores
#   tools/playtest.sh full     plus the bot playing chapters 1 and 2 solo,
#                              down the elevator and on through the Undercroft
#
# Quick pass: the level probe (holes out of the level, infected placed inside
# props or falling through the floor, items no one can pick up), the scares
# that bring infected in (no one popping up in view, no body in the floor), the
# existing rule tests (walls, doors, crowd, stun lock, infected chasing her
# through doorways and every one able to leave its room, the Records Vault
# fight and Continue, death flow, infected and hound deaths, story,
# the vault power and elevator, weapons, music, barrels: every gun on every
# drum), chapter 2 (its walls and level probe, the whole story through its
# prompts, the Warden fight's rules), the browser version's profile (both
# levels batched, its adapting on made-up phones; full mode: the bot's whole
# route with it), the
# bot's weapon / bag / save / death sections, the save slots (old saves, the
# save and load screens, the autosave rules), the difficulty numbers and the
# extra infected that Hard and co-op bring (the level probes again with every
# one of them in, the scares with Hard's bigger groups), and the co-op tests
# with two copies of the game through a local relay (needs node and the ws
# package:
# `npm i ws` anywhere and point NODE_PATH at its node_modules, or install it
# in relay/).
#
# Each test's log is in $PLAYTEST_LOGS (default /tmp/playtest). The summary
# at the end lists every failing test with its PLAYTEST BUG / FAIL lines.
# Exit code 0 only when everything passed.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/tools/godot}
command -v "$GODOT" >/dev/null 2>&1 || GODOT=godot
MODE=${1:-quick}
LOGS=${PLAYTEST_LOGS:-/tmp/playtest}
rm -rf "$LOGS" && mkdir -p "$LOGS"
FAILED=()

# run NAME TIMEOUT ARGS... : one headless test; fails on a non-zero exit, a
# script error, or a FAIL / PLAYTEST BUG line.
run() {
	local name=$1 limit=$2; shift 2
	local log="$LOGS/$name.log"
	local t0=$SECONDS
	timeout "$limit" "$GODOT" --headless --path . "$@" > "$log" 2>&1
	local code=$?
	if [ $code -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error|PLAYTEST BUG| FAIL|FAILED|TIMEOUT" "$log"; then
		FAILED+=("$name")
		printf '  FAIL  %-22s %4ds  (exit %d)\n' "$name" $((SECONDS - t0)) $code
	else
		printf '  ok    %-22s %4ds\n' "$name" $((SECONDS - t0))
	fi
}

echo "Playtest ($MODE) on $(git rev-parse --short HEAD 2>/dev/null)"
# Every prop model the game uses goes into the content packs (phones, web).
if python3 tools/content/check_excludes.py > "$LOGS/content_excludes.log" 2>&1; then
	printf '  ok    %-22s\n' content_excludes
else
	FAILED+=(content_excludes)
	printf '  FAIL  %-22s\n' content_excludes
fi
run smoke_level      120 --script tests/smoke_level.gd
run wall_overlap     120 --script tests/wall_overlap.gd
run level_probe      180 --fixed-fps 60 --script tests/playtest.gd -- only probe
run door_sweep       180 --script tests/door_sweep.gd
run door_reach       180 --script tests/door_reach.gd
run crowd_rules      300 --script tests/crowd_rules.gd
run stun_lock        300 --script tests/stun_lock.gd
run doorway_chase    300 --fixed-fps 60 --script tests/doorway_chase.gd
run vault_respawn    400 --fixed-fps 60 --script tests/vault_respawn.gd
run enemy_reach      300 --fixed-fps 60 --script tests/enemy_reach.gd
run death_flow       300 --script tests/death_flow.gd
run death_variety    180 --fixed-fps 60 --script tests/death_variety.gd
run hound_deaths     300 --fixed-fps 60 --script tests/hound_deaths.gd
run story            300 --script tests/story_test.gd
run power_route      300 --fixed-fps 60 --script tests/power_route.gd
run weapon_sweep     300 --script tests/weapon_sweep.gd
run music            180 --script tests/music_test.gd
run music_quiet      300 --script tests/music_quiet.gd
run breakables       300 --script tests/breakables.gd
run barrels_every_gun 400 --fixed-fps 60 --script tests/barrels_every_gun.gd
run bot_scares       300 --fixed-fps 60 --script tests/playtest.gd -- only scares
run bot_weapons      600 --fixed-fps 60 --script tests/playtest.gd -- only weapons
run bot_bag          300 --fixed-fps 60 --script tests/playtest.gd -- only bag
run bot_save         300 --fixed-fps 60 --script tests/playtest.gd -- only save
run save_slots       300 --script tests/save_slots.gd
run bot_death        300 --fixed-fps 60 --script tests/playtest.gd -- only death
# Difficulty: the numbers, every extra infected standing where it should, the
# level probe with all of them in (Hard co-op), the scares on Hard solo.
run extra_infected   300 --fixed-fps 60 --script tests/extra_infected.gd
run level_probe_hard_coop 180 --fixed-fps 60 --script tests/playtest.gd -- only probe difficulty hard pressure 3
run bot_scares_hard  300 --fixed-fps 60 --script tests/playtest.gd -- only scares difficulty hard pressure 2
# Chapter 2, the Undercroft: walls, the level probe, the whole story through
# its prompts, the Warden's rules, the bot fighting him its own way, and
# the hunting Tallyman at a shut door, and the pump room walked on foot.
run wall_overlap_ch2 120 --script tests/wall_overlap.gd -- res://scenes/levels/undercroft.tscn
run level_probe_ch2  180 --fixed-fps 60 --script tests/playtest.gd -- only probe2
run level_probe_ch2_hard_coop 180 --fixed-fps 60 --script tests/playtest.gd -- only probe2 difficulty hard pressure 3
run chapter2_flow    600 --fixed-fps 60 --script tests/chapter2_flow.gd
run warden_fight     300 --fixed-fps 60 --script tests/warden_fight.gd
run bot_warden       300 --fixed-fps 60 --script tests/playtest.gd -- only warden2
# The browser version's profile (docs/web_performance.md): both levels built
# and batched with it, and how it adapts to slow and fast phones.
run web_probe        180 --fixed-fps 60 --script tests/playtest.gd -- web only probe
run web_probe_ch2    180 --fixed-fps 60 --script tests/playtest.gd -- web only probe2
run web_adapt         60 --script tests/web_quality_adapt_test.gd
run stalker_doors    300 --fixed-fps 60 --script tests/stalker_doors.gd
run pump_walk        200 --fixed-fps 60 --script tests/pump_walk.gd

# Co-op: two copies of the game through a local relay.
coop() {
	local name=$1 script=$2
	RAGOON_RELAY=ws://127.0.0.1:${RELAY_PORT} timeout 240 "$GODOT" --headless --path . --script "$script" -- host > "$LOGS/${name}_host.log" 2>&1 &
	local host=$!
	sleep 2
	RAGOON_RELAY=ws://127.0.0.1:${RELAY_PORT} timeout 240 "$GODOT" --headless --path . --script "$script" -- join > "$LOGS/${name}_join.log" 2>&1
	local jc=$?
	wait $host
	local hc=$?
	if [ $hc -ne 0 ] || [ $jc -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error| FAIL|FAILED|TIMEOUT" "$LOGS/${name}_host.log" "$LOGS/${name}_join.log"; then
		FAILED+=("${name}_host" "${name}_join")
		printf '  FAIL  %-22s (host exit %d, join exit %d)\n' "$name" $hc $jc
	else
		printf '  ok    %-22s\n' "$name"
	fi
}
if command -v node >/dev/null 2>&1 && node -e "require('ws')" >/dev/null 2>&1; then
	RELAY_PORT=${RELAY_PORT:-8797}
	PORT=$RELAY_PORT node relay/local_relay.js > "$LOGS/relay.log" 2>&1 &
	RELAY=$!
	sleep 1
	coop coop_peer tests/coop_peer.gd
	coop coop_version tests/coop_version.gd
	coop coop_story tests/coop_story.gd
	coop coop_death tests/coop_death.gd
	coop coop_playtest tests/playtest_coop.gd
	coop coop_saves tests/coop_saves.gd
	coop coop_pickups tests/coop_pickups.gd
	kill $RELAY 2>/dev/null
else
	echo "  skip  co-op tests (needs node with the ws package; see the top of this file)"
fi

if [ "$MODE" = "full" ]; then
	run bot_route 3000 --fixed-fps 60 --script tests/playtest.gd -- only route
	run bot_route_web 3000 --fixed-fps 60 --script tests/playtest.gd -- web only route
fi

echo
if [ ${#FAILED[@]} -eq 0 ]; then
	echo "PLAYTEST PASSED"
	exit 0
fi
echo "PLAYTEST FAILED: ${FAILED[*]}"
for n in "${FAILED[@]}"; do
	echo "--- $n ($LOGS/$n.log)"
	grep -E "SCRIPT ERROR|PLAYTEST BUG| FAIL|FAILED|TIMEOUT" "$LOGS/$n.log" | head -12
done
exit 1
