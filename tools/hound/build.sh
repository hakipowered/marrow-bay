#!/bin/bash
# Builds the infected hound from its Meshy scan: skeleton + heat-weighted
# skin (build_rig.py), every clip (animate.py), GLB export (export.py), then
# the game files assets/characters/enemies/hound/hound.glb + hound_anims.res.
#
#   BPY=/path/to/venv/bin/python tools/hound/build.sh <meshy_model.glb> [work_dir]
#
# BPY is a Python with Blender as a module: python3 -m venv v && v/bin/pip install bpy
# (Blender 5.3; import numpy only after a glTF import or bpy aborts). The scan
# is the job "m3d_hound_B" in /mnt/project-files/infected/model_jobs.txt. The
# skeleton's landmarks in build_rig.py are measured on that scan (S, YMID and
# the bone list): a different scan needs them measured again.
# Check clips with: $BPY tools/hound/contact.py -- <work>/hound_anims.blend <clip> <out_prefix> 8 side
set -e
SRC=$1
WORK=${2:-/tmp/hound_work}
BPY=${BPY:-python3}
GODOT=${GODOT:-$HOME/tools/godot}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
mkdir -p "$WORK"
"$BPY" "$HERE/build_rig.py" -- "$SRC" "$WORK/rig.blend"
"$BPY" "$HERE/animate.py" -- "$WORK/rig.blend" "$WORK/hound.glb" "$WORK/hound_anims.glb"
"$BPY" "$HERE/export.py" -- "$WORK/hound_anims.blend" "$WORK/hound.glb" "$WORK/hound_all.glb"
mkdir -p "$ROOT/assets/characters/enemies/hound" "$ROOT/build_tmp/anims/enemies/hound"
cp "$WORK/hound.glb" "$ROOT/assets/characters/enemies/hound/hound.glb"
cp "$WORK/hound_all.glb" "$ROOT/build_tmp/anims/enemies/hound/hound_all.glb"
cd "$ROOT"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
python3 tools/fix_imports.py
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --script tools/import_character.gd -- enemies/hound
