#!/usr/bin/env python3
"""Set 3D-friendly import settings on every level texture (mipmaps + GPU
compression, normal maps flagged), so floors don't shimmer and phones keep
textures compressed in memory. Run after tools/fetch_assets.py, then
`godot --headless --import`.
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
dirs = ["assets/polyhaven", "assets/textures", "assets/characters"]
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
        if new != s:
            open(imp, "w").write(new)
            # Drop the cached import so Godot rebuilds it.
            base = os.path.join(ROOT, ".godot", "imported", os.path.basename(imp[:-7]))
            for f in glob.glob(base + "-*"):
                os.remove(f)
            changed += 1
print("updated", changed, "texture imports")
