#!/bin/bash
# Build the game content packs that the in-game updater downloads.
#   tools/build_content.sh <version>        e.g. tools/build_content.sh 0.12
# Exports the "Android Content" preset (everything except the thin base in
# boot/ and the root files) as one pack, then splits it into packs under
# build/content/packs/ plus build/content/manifest.json. Upload them with
#   UPLOAD_TOKEN=... python3 tools/content/packs.py upload build/content
# Files stay in the packs players already have (the live layout on the
# download server), so only changed and new files make new downloads; it
# prints how much players will download. RAGOON_CONTENT_LIKE=none packs from
# scratch, RAGOON_CONTENT_LIKE=<dir> keeps the layout of another local build.
# See tools/content/README.md. Run tools/fetch_assets.py and an import first,
# like for the APK.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.12}"
GODOT="${GODOT:-$HOME/tools/godot}"
tools/android_sdk_stub.sh
mkdir -p build/content
rm -f build/content/full.pck
"$GODOT" --headless --path . --export-pack "Android Content" build/content/full.pck
python3 tools/content/packs.py split build/content/full.pck build/content --version "$VERSION"
rm -f build/content/full.pck
