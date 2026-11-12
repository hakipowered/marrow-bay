#!/usr/bin/env bash
# Playtest gate: run this before every build, and don't ship while it fails.
#
#   tools/playtest.sh          quick pass, about 6 minutes on 4 cores
#   tools/playtest.sh full     plus the bot playing the whole first area solo
#                              (about 2 more minutes)
#
# Quick pass: the level probe (holes out of the level, infected placed inside
# props or falling through the floor, items no one can pick up), the
# existing rule tests (walls, doors, crowd, death flow, story, weapons, music), the
# bot's weapon / bag / save / death sections, and the co-op tests with two
# copies of the game through a local relay (needs node and the ws package:
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
run smoke_level      120 --script tests/smoke_level.gd
run wall_overlap     120 --script tests/wall_overlap.gd
run level_probe      180 --fixed-fps 60 --script tests/playtest.gd -- only probe
run door_sweep       180 --script tests/door_sweep.gd
run door_reach       180 --script tests/door_reach.gd
run crowd_rules      300 --script tests/crowd_rules.gd
run death_flow       300 --script tests/death_flow.gd
run story            300 --script tests/story_test.gd
run weapon_sweep     300 --script tests/weapon_sweep.gd
run music            180 --script tests/music_test.gd
run bot_weapons      600 --fixed-fps 60 --script tests/playtest.gd -- only weapons
run bot_bag          300 --fixed-fps 60 --script tests/playtest.gd -- only bag
run bot_save         300 --fixed-fps 60 --script tests/playtest.gd -- only save
run bot_death        300 --fixed-fps 60 --script tests/playtest.gd -- only death

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
	coop coop_story tests/coop_story.gd
	coop coop_death tests/coop_death.gd
	coop coop_playtest tests/playtest_coop.gd
	kill $RELAY 2>/dev/null
else
	echo "  skip  co-op tests (needs node with the ws package; see the top of this file)"
fi

if [ "$MODE" = "full" ]; then
	run bot_route 1500 --fixed-fps 60 --script tests/playtest.gd -- only route
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
