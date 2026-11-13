#!/bin/bash
# Build the browser version of the game into build/web/. The download worker
# serves it at https://ragoon-city-download.hakipowered.workers.dev/play/
# (upload with tools/upload_web.sh).
#   tools/build_web.sh
# Needs Godot 4.4.1 at ~/tools/godot and the Web export templates (web_release.zip
# from the same .tpz as the Android ones) in
# ~/.local/share/godot/export_templates/4.4.1.stable/.
# The "Web" preset uses the Compatibility (WebGL 2) renderer, threads (the
# worker sends the COOP/COEP headers that needs) and the same ETC2/ASTC
# textures as Android, so the content packs are shared with the app.
set -e
cd "$(dirname "$0")/.."
T=~/.local/share/godot/export_templates/4.4.1.stable
[ -f "$T/web_release.zip" ] || { echo "missing $T/web_release.zip (unzip templates/web_* from the 4.4.1 export templates .tpz)"; exit 1; }
# The web base and the content packs must carry the same base id as the APK's.
[ -f tools/content/packs.py ] && python3 tools/content/packs.py build-info
rm -rf build/web
mkdir -p build/web
touch build/.gdignore  # keep Godot from importing build output
~/tools/godot --headless --path . --export-release "Web" build/web/index.html
cp web/splash.jpg web/icon-192.png web/icon-512.png web/manifest.webmanifest build/web/
# The page checks the server's content packs are made for this base before
# downloading them (web/shell.html).
cp boot/build_info.json build/web/build_info.json
du -sh build/web/* | sort -h
# The browser loads index.pck before the title screen, so it must be the small
# base; the game content comes from the updater's packs (/packs/).
PCK=$(stat -c %s build/web/index.pck)
if [ "$PCK" -gt $((64 * 1048576)) ] && [ -z "$ALLOW_FULL_PCK" ]; then
	echo "build/web/index.pck is $((PCK / 1048576)) MB: the Web preset is exporting the whole game instead of the thin base."
	echo "Don't upload this (it would take minutes to load on a phone and double the KV storage). ALLOW_FULL_PCK=1 to build it anyway for a local test."
	exit 1
fi
