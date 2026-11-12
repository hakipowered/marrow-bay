#!/usr/bin/env python3
"""Turns the generated effect sheets in tools/fx/src into game textures.

Each source is a 2x2 sheet of four isolated sprites (fal, Nano Banana) on a
flat black (fire, smoke, flashes) or white (blood) background. This keys the
background out into alpha, centres each sprite in its cell and writes:

  assets/textures/fx/<name>_atlas.png   2x2 atlases for particles and flashes
  assets/textures/decals/blood_N.png    single blood stains for Decals

  python3 tools/fx/make_fx_textures.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "tools", "fx", "src")
FX = os.path.join(ROOT, "assets", "textures", "fx")
DECALS = os.path.join(ROOT, "assets", "textures", "decals")


def load(name):
    return np.asarray(Image.open(os.path.join(SRC, name)).convert("RGB")).astype(np.float32) / 255.0


def cells(img):
    h, w = img.shape[:2]
    return [img[r * h // 2:(r + 1) * h // 2, c * w // 2:(c + 1) * w // 2] for r in range(2) for c in range(2)]


def key_black(rgb):
    """Bright sprite on black: alpha from brightness, colour un-premultiplied."""
    m = rgb.max(axis=2)
    a = np.clip((m - 0.035) / 0.6, 0.0, 1.0)
    col = np.clip(rgb / np.maximum(a[..., None], 1e-3), 0.0, 1.0)
    return col, a


def key_smoke(rgb):
    """Grey smoke on black: alpha from luminance, colour kept as shading."""
    lum = rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    a = np.clip((lum - 0.03) / 0.55, 0.0, 1.0)
    shade = np.clip(lum / np.maximum(a, 1e-3), 0.0, 1.0)
    return np.repeat(shade[..., None], 3, axis=2), a


def key_white(rgb):
    """Dark red on white: alpha from how far the pixel is from white (the
    green and blue channels), colour un-mixed from the white behind it."""
    a = np.clip((1.0 - (rgb[..., 1] + rgb[..., 2]) * 0.5 - 0.04) / 0.8, 0.0, 1.0)
    col = (rgb - (1.0 - a[..., None])) / np.maximum(a[..., None], 1e-3)
    col = np.clip(col, 0.0, 1.0)
    # Keep it blood: never lighter than a deep crimson.
    col[..., 0] = np.minimum(col[..., 0], 0.62)
    col[..., 1] = np.minimum(col[..., 1], 0.06)
    col[..., 2] = np.minimum(col[..., 2], 0.06)
    return col, a


def feather(a, frac=0.04):
    h, w = a.shape
    y = np.minimum(np.arange(h), np.arange(h)[::-1]) / (h * frac)
    x = np.minimum(np.arange(w), np.arange(w)[::-1]) / (w * frac)
    return a * np.clip(y[:, None], 0, 1) * np.clip(x[None, :], 0, 1)


def place(col, a, size, anchor="center", pad=0.06):
    """Crops to the sprite and fits it in a size x size square."""
    a = feather(a)
    ys, xs = np.where(a > 0.04)
    if len(xs) == 0:
        y0, y1, x0, x1 = 0, a.shape[0], 0, a.shape[1]
    else:
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.concatenate([col, a[..., None]], axis=2)[y0:y1, x0:x1]
    h, w = rgba.shape[:2]
    side = int(max(h, w) * (1.0 + 2 * pad))
    out = np.zeros((side, side, 4), dtype=np.float32)
    if anchor == "bottom":     # flames stand on their base
        oy = side - h - int(side * 0.03)
        ox = (side - w) // 2
    elif anchor == "left":     # side muzzle blasts start at the barrel
        oy = (side - h) // 2
        ox = int(side * 0.02)
    else:
        oy = (side - h) // 2
        ox = (side - w) // 2
    out[oy:oy + h, ox:ox + w] = rgba
    img = Image.fromarray((out * 255).astype(np.uint8), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def atlas(name, keyer, size, anchors=("center",) * 4):
    sheet = load(name + "_sheet.jpg")
    out = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    for i, c in enumerate(cells(sheet)):
        col, a = keyer(c)
        out.paste(place(col, a, size, anchors[i]), ((i % 2) * size, (i // 2) * size))
    path = os.path.join(FX, name + "_atlas.png")
    out.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def blood_decals():
    sheet = load("blood_decal_sheet.jpg")
    for i, c in enumerate(cells(sheet)):
        col, a = key_white(c)
        img = place(col, a, 512, pad=0.03)
        path = os.path.join(DECALS, "blood_%d.png" % (i + 1))
        img.save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT))


def bullet_holes(n=3, size=256, seed=7):
    """Procedural bullet holes: a dark pit, a ring of chipped, lighter
    plaster and a few hairline cracks, on transparency."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    dx, dy = (xx - c) / c, (yy - c) / c
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    for i in range(n):
        wob = sum(rng.uniform(0.008, 0.022) * np.sin(k * ang + rng.uniform(0, 6.3)) for k in (3, 5, 9, 14))
        col = np.zeros((size, size, 3), np.float32)
        a = np.zeros((size, size), np.float32)
        # Chipped ring: lighter broken plaster with grit.
        grit = rng.uniform(0.0, 1.0, (size, size)).astype(np.float32)
        grit_r = np.asarray(Image.fromarray((grit * 255).astype(np.uint8)).resize((size // 16, size // 16)).resize((size, size), Image.BILINEAR), np.float32) / 255.0
        pit = 0.12 + wob * 0.4
        chip = 0.34 + wob * 1.3 + (grit_r - 0.5) * 0.08
        ring = np.clip((chip - r) / 0.05, 0.0, 1.0)
        col[:] = np.stack([0.62, 0.6, 0.57]) * (0.75 + 0.25 * grit[..., None])
        a = np.maximum(a, ring * (0.55 + 0.3 * grit))
        # Soot and shadow toward the pit.
        soot = np.clip((chip * 0.75 - r) / (chip * 0.5), 0.0, 1.0)
        col = col * (1.0 - 0.7 * soot[..., None])
        a = np.maximum(a, soot * 0.85)
        # The pit.
        hole = np.clip((pit - r) / 0.03, 0.0, 1.0)
        col = col * (1.0 - hole[..., None]) + np.array([0.03, 0.025, 0.02]) * hole[..., None]
        a = np.maximum(a, hole)
        # Hairline cracks.
        for _ in range(rng.integers(3, 6)):
            th = rng.uniform(0, 2 * np.pi)
            ln = rng.uniform(0.55, 0.95)
            d = np.abs(np.sin(ang - th)) * r
            along = np.cos(ang - th) * r
            line = np.clip(1.0 - d / 0.012, 0.0, 1.0) * (along > pit) * (along < ln) * (1.0 - along / ln)
            col = col * (1.0 - 0.8 * line[..., None])
            a = np.maximum(a, line * 0.8)
        rgba = np.concatenate([np.clip(col, 0, 1), np.clip(a, 0, 1)[..., None]], axis=2)
        path = os.path.join(DECALS, "bullet_hole_%d.png" % (i + 1))
        Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    os.makedirs(FX, exist_ok=True)
    atlas("fire", key_black, 512, ("bottom",) * 4)
    atlas("fireball", key_black, 256)
    atlas("smoke", key_smoke, 256)
    atlas("muzzle", key_black, 256, ("left", "left", "center", "center"))
    atlas("blood_spray", key_white, 256, ("left",) * 4)
    blood_decals()
    bullet_holes()
