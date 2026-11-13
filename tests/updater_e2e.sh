#!/bin/bash
# End-to-end test of the in-game updater on this machine (no phone needed).
#   tools/build_content.sh <version>   # first: makes build/content
#   tests/updater_e2e.sh
# Exports the thin base (the APK's content) as a pack, serves build/content
# locally the way the download server does, and runs the base headless
# through: first install, relaunch, first level from the packs, offline,
# new app needed, server behind, an update that needs one pack, a damaged
# download, content made for another app, and offline with nothing installed.
# Exit 0 only when every step did what it should.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/tools/godot}"
[ -f build/content/manifest.json ] || { echo "run tools/build_content.sh <version> first"; exit 1; }
T=$(mktemp -d)
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

python3 tools/content/packs.py build-info > /dev/null
"$GODOT" --headless --path . --export-pack "Android" "$T/thin.pck" > "$T/export.log" 2>&1 || { cat "$T/export.log"; exit 1; }

# Server 1: the real build. Server 2: the same packs as a new version.
# Server 3: like 2, but one pack's checksum doesn't match (a damaged download).
# Server 4: content for a newer app. Server 5: content for an older app.
mkdir -p "$T"/s{2,3,4,5}
python3 - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
m = json.load(open("build/content/manifest.json"))
def put(n, change):
    x = json.loads(json.dumps(m))
    change(x)
    json.dump(x, open(f"{t}/s{n}/manifest.json", "w"))
def v2(x): x["version"] = "9.99"; x["build"] = "9.99-e2e"
def damaged(x): v2(x); [p for p in x["packs"] if p["name"] == "ui"][0]["sha256"] = "0" * 64
def newer_app(x): x["base"] = "000000000000"; x["app"]["code"] = 9999
def older_app(x): x["base"] = "000000000000"; x["app"]["code"] = 0
put(2, v2); put(3, damaged); put(4, newer_app); put(5, older_app)
EOF
for n in 2 3 4 5; do ln -s "$PWD/build/content/packs" "$T/s$n/packs"; done
port=8790
for dir in "$PWD/build/content" "$T/s2" "$T/s3" "$T/s4" "$T/s5"; do
	python3 tools/content/packs.py serve "$dir" --port $port 2> /dev/null &
	PIDS+=($!)
	port=$((port + 1))
done
sleep 1
url() { echo "http://127.0.0.1:$((8789 + $1))/packs/"; }

DATA="$T/data"
step=0
run() { # run <server url> <smoke mode> <expected pattern>...
	local u="$1" mode="$2"
	shift 2
	step=$((step + 1))
	local log="$T/run$step.log"
	# Run outside the project folder, or Godot finds the source files there.
	(cd "$T" && XDG_DATA_HOME="$DATA" RAGOON_CONTENT_URL="$u" RAGOON_BOOT_SMOKE="$mode" \
		timeout 300 "$GODOT" --headless --main-pack "$T/thin.pck" > "$log" 2>&1) || true
	for want in "$@"; do
		if ! grep -q -- "$want" "$log"; then
			echo "FAIL step $step: expected '$want'"
			grep -v '^\s*at:' "$log" | tail -40
			exit 1
		fi
	done
	# With nothing mounted the game's autoloads can't load yet (expected);
	# once packs are mounted there must be no script errors at all.
	if grep -q "SCRIPT ERROR\|Parse Error\|Failed to instantiate an autoload" "$log" && grep -q "mounted true" "$log"; then
		echo "FAIL step $step: script errors"
		grep -B1 -A2 "SCRIPT ERROR\|Parse Error\|Failed to instantiate" "$log" | head -30
		exit 1
	fi
	echo "ok   step $step: $(grep '^boot:' "$log" | head -1 | cut -c7-90)"
}
packs_dir() { echo "$DATA"/godot/app_userdata/*/content/packs; }
installed() { echo "$DATA"/godot/app_userdata/*/content/installed.json; }

N=$(python3 -c "import json; print(len(json.load(open('build/content/manifest.json'))['packs']))")
BUILD=$(python3 -c "import json; print(json.load(open('build/content/manifest.json'))['build'])")

echo "first install"
run "$(url 1)" 1 "state UPDATE, $N packs" "download ok" "installed $BUILD" "boot: restart"
run "$(url 1)" 1 "state UP_TO_DATE" "mounted true $BUILD" "title screen is res://scenes/main_menu.tscn"
echo "first level from the packs"
run "$(url 1)" level "level is res://scenes/levels/"
echo "offline with the game installed: plays it"
run "http://127.0.0.1:9/packs/" 1 "state OFFLINE" "title screen is res://scenes/main_menu.tscn"
echo "content needs a newer app / server still has older content"
run "$(url 4)" 1 "state NEEDS_APP" "waiting on: Get the new app" "waiting on: Play"
run "$(url 5)" 1 "state SERVER_BEHIND" "waiting on: Try again"
echo "new version where one pack changed"
UI=$(ls "$(packs_dir)" | grep '^ui-')
rm "$(packs_dir)/$UI"
run "$(url 2)" 1 "state UPDATE, 1 packs" "download ok" "installed 9.99-e2e"
run "$(url 2)" 1 "state UP_TO_DATE" "mounted true 9.99-e2e" "title screen is"
echo "damaged download is refused, then repaired"
rm "$(packs_dir)/$UI"
run "$(url 3)" 1 "state UPDATE, 1 packs" "download failed: a download came through damaged" "waiting on: Try again"
[ ! -e "$(packs_dir)/$UI" ] && ! ls "$(packs_dir)" | grep -q '\.part$' || { echo "FAIL: damaged pack kept"; exit 1; }
run "$(url 2)" 1 "mounted false" "state UPDATE, 1 packs" "download ok"
run "$(url 2)" 1 "state UP_TO_DATE" "mounted true 9.99-e2e"
echo "content made for another app (new APK installed): reuses packs on disk"
sed -i 's/"base": "[0-9a-f]*"/"base": "ffffffffffff"/' "$(installed)"
run "$(url 2)" 1 "mounted false" "state UPDATE, 0 packs" "boot: restart"
run "$(url 2)" 1 "state UP_TO_DATE" "mounted true 9.99-e2e"
echo "offline with nothing installed"
rm -rf "$DATA"
run "http://127.0.0.1:9/packs/" 1 "state OFFLINE" "waiting on: Try again"
echo "PASS: updater end to end"
