#!/usr/bin/env python3
"""Set 3D-friendly import settings on every level texture (mipmaps + GPU
compression, normal maps flagged), so floors don't shimmer and phones keep
textures compressed in memory. Run after tools/fetch_assets.py, then
`godot --headless --import`.
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Small props use 512 px textures on the phone; these big ones stay at 1K.
KEEP_1K = ("covered_car", "old_bed_frame", "wooden_bookshelf_worn", "modular_fire_escape", "modular_chainlink_fence",
           "concrete_road_barrier", "Sofa_01", "gothic_statue", "standing_chalkboard_01", "dining_table",
           "vintage_grandfather_clock_01", "GothicCabinet_01", "metal_office_desk", "painted_wooden_bench", "street_lamp_01")
dirs = ["assets/polyhaven", "assets/textures", "assets/characters", "assets/props", "assets/story"]
changed = 0
for d in dirs:
    for imp in glob.glob(os.path.join(ROOT, d, "**", "*.import"), recursive=True):
        src = imp[:-7].lower()
        if not src.endswith((".jpg", ".jpeg", ".png", ".webp")):
            continue
        s = open(imp).read()
        if 'importer="texture"' not in s:
            continue
        is_normal = bool(re.search(r"(normal|_nor_|nor_gl|_nrm)", os.path.basename(src)))
        new = s
        new = re.sub(r"compress/mode=\d", "compress/mode=2", new)
        new = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", new)
        new = re.sub(r"compress/normal_map=\d", "compress/normal_map=%d" % (1 if is_normal else 2), new)
        new = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", new)
        rel = os.path.relpath(imp, ROOT).replace(os.sep, "/")
        if rel.startswith("assets/characters/enemies/"):
            # Many infected share the screen: 1K textures keep memory and APK size down.
            new = re.sub(r"process/size_limit=\d+", "process/size_limit=1024", new)
        if rel.startswith("assets/polyhaven/models/"):
            model = rel.split("/")[3]
            new = re.sub(r"process/size_limit=\d+", "process/size_limit=%d" % (0 if model.startswith(KEEP_1K) else 512), new)
        if new != s:
            open(imp, "w").write(new)
            # Drop the cached import so Godot rebuilds it.
            base = os.path.join(ROOT, ".godot", "imported", os.path.basename(imp[:-7]))
            for f in glob.glob(base + "-*"):
                os.remove(f)
            changed += 1
print("updated", changed, "texture imports")
