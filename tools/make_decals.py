#!/usr/bin/env python3
"""Turn photos of stains on white backgrounds into alpha decal PNGs.
Usage: python3 tools/make_decals.py <kind> <tint r,g,b or none> <src.jpg> <out_index>
"""
import sys, numpy as np
from PIL import Image

kind, tint, src, idx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
im = np.asarray(Image.open(src).convert("RGB").resize((512, 512), Image.LANCZOS)).astype(np.float32) / 255.0
a = 1.0 - im.min(axis=2)                       # white background -> transparent
a = np.clip((a - 0.06) / 0.94, 0, 1)
col = (im - (1.0 - a[..., None])) / np.maximum(a[..., None], 1e-3)
col = np.clip(col, 0, 1)
if tint != "none":
    t = np.array([float(x) for x in tint.split(",")], dtype=np.float32)
    lum = col.mean(axis=2, keepdims=True)
    col = np.clip(t * (0.55 + 0.9 * lum), 0, 1)   # aged, dark, slightly varied
yy, xx = np.mgrid[0:512, 0:512]
r = np.sqrt((xx - 256) ** 2 + (yy - 256) ** 2) / 256.0
a *= np.clip((1.0 - r) / 0.12, 0, 1)            # no square edges
out = np.dstack([col, a[..., None]])
Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(f"assets/textures/decals/{kind}_{idx}.png")
print("wrote", kind, idx)
