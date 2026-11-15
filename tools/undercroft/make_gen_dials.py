#!/usr/bin/env python3
"""Paints the three panel meters on the generator's control cabinet (chapter 2,
GeneratorSet._build_cabinet): VOLTS, AMPERES and FREQUENCY faces side by side
in one atlas, aged cream enamel with a black scale, the maker's name and a red
mark at the set's rated value.

    python3 tools/undercroft/make_gen_dials.py

Writes assets/textures/undercroft/gen_dials.png (1536 x 512, three 512 px
squares, clear outside each round face so the quads read as discs). The needle pivot is at (256, 400) in each square and the scale runs
from 50 degrees left of straight up to 50 degrees right; GeneratorSet.DIALS
uses the same numbers to point the needles.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT = os.path.join(ROOT, "assets", "fonts", "Oswald.ttf")
OUT = os.path.join(ROOT, "assets", "textures", "undercroft", "gen_dials.png")

S = 512
PIVOT = (256, 400)
R = 300
SPAN = 50.0

# label, unit, lo, hi, major step, minor step, number every, red mark
DIALS = [
    ("VOLTS", "V", 0, 500, 100, 20, 100, 415),
    ("AMPERES", "A", 0, 300, 50, 10, 100, None),
    ("FREQUENCY", "Hz", 45, 55, 1, 0.5, 5, 50),
]


def font(px):
    return ImageFont.truetype(FONT, px)


def ang(v, lo, hi):
    return math.radians(-SPAN + 2 * SPAN * (v - lo) / (hi - lo))


def at(a, r):
    return (PIVOT[0] + math.sin(a) * r, PIVOT[1] - math.cos(a) * r)


def face(rng, spec):
    label, unit, lo, hi, major, minor, every, red = spec
    img = Image.new("RGB", (S, S), (222, 212, 184))
    # Yellowed toward the rim, foxing spots, a tide mark from damp.
    px = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2)
    px *= (1.0 - 0.18 * np.clip(d - 0.35, 0, 1))[..., None]
    px[..., 2] *= 0.93
    noise = rng.normal(0, 4.0, (S, S, 1))
    px = np.clip(px + noise, 0, 255)
    img = Image.fromarray(px.astype(np.uint8))
    dr = ImageDraw.Draw(img)
    for _ in range(40):
        x, y = rng.uniform(30, S - 30), rng.uniform(30, S - 30)
        r = rng.uniform(1, 5)
        c = int(rng.uniform(150, 190))
        dr.ellipse((x - r, y - r, x + r, y + r), fill=(c, int(c * 0.9), int(c * 0.7)))
    tide = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(tide)
    td.arc((-120, 300, 640, 900), 200, 340, fill=110, width=6)
    tide = tide.filter(ImageFilter.GaussianBlur(5))
    img.paste(Image.new("RGB", (S, S), (160, 140, 100)), (0, 0), tide.point(lambda v: v // 2))
    dr = ImageDraw.Draw(img)
    ink = (22, 20, 18)
    # The scale arc, its red zone and ticks.
    box = (PIVOT[0] - R, PIVOT[1] - R, PIVOT[0] + R, PIVOT[1] + R)
    dr.arc(box, -90 - SPAN, -90 + SPAN, fill=ink, width=4)
    if red is not None:
        a0 = math.degrees(ang(red, lo, hi))
        dr.arc((box[0] + 8, box[1] + 8, box[2] - 8, box[3] - 8), -90 + a0 - 3, -90 + a0 + 3, fill=(170, 30, 20), width=18)
    v = lo
    while v <= hi + 1e-6:
        a = ang(v, lo, hi)
        is_major = abs((v - lo) / major - round((v - lo) / major)) < 1e-6
        ln = 34 if is_major else 18
        dr.line([at(a, R), at(a, R - ln)], fill=ink, width=5 if is_major else 3)
        if abs((v - lo) / every - round((v - lo) / every)) < 1e-6:
            t = str(int(v)) if float(v).is_integer() else str(v)
            f = font(40)
            tw = dr.textlength(t, font=f)
            cx, cy = at(a, R - 72)
            dr.text((cx - tw / 2, cy - 26), t, font=f, fill=ink)
        v = round(v + minor, 4)
    # Unit, name, maker.
    f = font(72)
    tw = dr.textlength(unit, font=f)
    dr.text((256 - tw / 2, 238), unit, font=f, fill=ink)
    f = font(30)
    tw = dr.textlength(label, font=f)
    dr.text((256 - tw / 2, 318), label, font=f, fill=ink)
    f = font(20)
    for i, t in enumerate(["ROTHWELL & SONS  -  RIVER WORKS", "MOVING IRON  CLASS 1.5"]):
        tw = dr.textlength(t, font=f)
        dr.text((256 - tw / 2, 432 + i * 24), t, font=f, fill=(60, 54, 46))
    # Pivot boss.
    dr.ellipse((PIVOT[0] - 16, PIVOT[1] - 16, PIVOT[0] + 16, PIVOT[1] + 16), fill=(30, 28, 26))
    # Dust and a grimy shadow round the rim where the bezel sits.
    rim = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rim).ellipse((0, 0, S, S), outline=150, width=40)
    rim = rim.filter(ImageFilter.GaussianBlur(18))
    img.paste(Image.new("RGB", (S, S), (70, 60, 45)), (0, 0), rim)
    return img


def main():
    rng = np.random.default_rng(1958)
    random.seed(1958)
    atlas = Image.new("RGBA", (S * len(DIALS), S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((6, 6, S - 6, S - 6), fill=255)
    for i, spec in enumerate(DIALS):
        atlas.paste(face(rng, spec), (i * S, 0), mask)
    atlas.save(OUT, optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
