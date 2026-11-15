#!/usr/bin/env python3
"""Paints the pump room's enamel pipework board (chapter 2): the 1974 drainage
arrangement of Sump B, as the flood shelter works left it on the wall above
the valves, chipped, stained and rust-streaked.

    python3 tools/undercroft/make_sump_board.py

Writes assets/textures/undercroft/sump_board.jpg. The valve numbers and names
here are the ones on the brass tags in the game (scripts/world/pump_room.gd).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "undercroft", "sump_board.jpg")
FONT = os.path.join(ROOT, "assets", "fonts", "Oswald.ttf")
W, H = 1600, 900
INK = (28, 34, 40)
RED = (150, 32, 22)
BLUE = (34, 62, 96)

rng = random.Random(1974)


def font(px):
    return ImageFont.truetype(FONT, px)


def text(d, xy, s, px, fill=INK, anchor="mm"):
    d.text(xy, s, font=font(px), fill=fill, anchor=anchor)


def pipe(d, pts, w=9, fill=INK):
    d.line(pts, fill=fill, width=w, joint="curve")


def valve(d, x, y, vertical=False, tag="", name="", tag_at=None):
    """A gate valve symbol (two triangles tip to tip, along the pipe) with
    its stem and handwheel, and its brass tag."""
    s = 26
    fill = (230, 224, 206)
    if vertical:
        d.polygon([(x - s, y - s), (x + s, y - s), (x, y)], fill=fill, outline=INK, width=5)
        d.polygon([(x - s, y + s), (x + s, y + s), (x, y)], fill=fill, outline=INK, width=5)
        d.line([(x, y), (x - 46, y)], fill=INK, width=5)
        d.ellipse([x - 70, y - 12, x - 46, y + 12], outline=INK, width=5)
    else:
        d.polygon([(x - s, y - s), (x - s, y + s), (x, y)], fill=fill, outline=INK, width=5)
        d.polygon([(x + s, y - s), (x + s, y + s), (x, y)], fill=fill, outline=INK, width=5)
        d.line([(x, y), (x, y - 46)], fill=INK, width=5)
        d.ellipse([x - 12, y - 70, x + 12, y - 46], outline=INK, width=5)
    if tag:
        tx, ty = tag_at if tag_at else (x, y + 62)
        d.rounded_rectangle([tx - 74, ty - 22, tx + 74, ty + 22], 6, fill=(196, 160, 82), outline=INK, width=3)
        text(d, (tx, ty), tag, 30, INK)
        if name:
            text(d, (tx, ty + 42), name, 25, INK)


def arrow(d, x, y, ang, fill=INK):
    a = math.radians(ang)
    p = [(x + math.cos(a) * 22, y + math.sin(a) * 22),
         (x + math.cos(a + 2.5) * 16, y + math.sin(a + 2.5) * 16),
         (x + math.cos(a - 2.5) * 16, y + math.sin(a - 2.5) * 16)]
    d.polygon(p, fill=fill)


def box(d, x0, y0, x1, y1, title, sub=""):
    d.rectangle([x0, y0, x1, y1], fill=(222, 214, 192), outline=INK, width=6)
    text(d, ((x0 + x1) / 2, (y0 + y1) / 2 - (14 if sub else 0)), title, 34)
    if sub:
        text(d, ((x0 + x1) / 2, (y0 + y1) / 2 + 24), sub, 22)


def pump(d, x, y, label):
    d.ellipse([x - 30, y - 30, x + 30, y + 30], fill=(230, 224, 206), outline=INK, width=5)
    d.polygon([(x - 14, y + 18), (x - 14, y - 18), (x + 20, y)], fill=INK)
    if label:
        text(d, (x, y + 52), label, 24)


def main():
    img = Image.new("RGB", (W, H), (214, 205, 180))
    d = ImageDraw.Draw(img)
    # Enamel plate: a blue rim, a cream field.
    d.rectangle([0, 0, W - 1, H - 1], fill=BLUE)
    d.rounded_rectangle([22, 22, W - 23, H - 23], 18, fill=(226, 218, 196))
    d.rectangle([40, 40, W - 41, H - 41], outline=INK, width=4)
    d.rectangle([40, 40, W - 41, 140], fill=BLUE)
    text(d, (W / 2, 78), "SUMP  B   -   DRAINAGE  ARRANGEMENT", 54, (232, 226, 206))
    text(d, (W / 2, 122), "RIVER DISTRICT SERVICE LEVEL   .   CIVIC ARCHIVE FLOOD SHELTER WORKS   .   1974", 24, (200, 196, 180))

    # The river main (tidal) on the left, the storm sewer on the right.
    box(d, 80, 230, 330, 350, "RIVER MAIN", "TIDAL  -  HIGH IN FLOOD")
    box(d, 1270, 560, 1520, 680, "STORM SEWER", "TO RIVER OUTFALL")
    box(d, 1270, 200, 1520, 320, "RIVER OUTFALL", "FLAP GATE")
    # Sump B in the middle: a tank, its water line and hatched water.
    sx0, sy0, sx1, sy1 = 640, 330, 960, 610
    d.rectangle([sx0, sy0, sx1, sy1], fill=(222, 214, 192), outline=INK, width=8)
    wl = sy0 + 60
    hatch = Image.new("RGB", (W, H), (222, 214, 192))
    hd = ImageDraw.Draw(hatch)
    for k in range(-400, 420, 22):
        hd.line([(sx0 + k, wl), (sx0 + k + (sy1 - wl), sy1)], fill=(150, 168, 186), width=3)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rectangle([sx0 + 4, wl, sx1 - 4, sy1 - 4], fill=255)
    img.paste(hatch, (0, 0), mask)
    d.rectangle([sx0, sy0, sx1, sy1], outline=INK, width=8)
    d.line([(sx0 + 4, wl), (sx1 - 4, wl)], fill=BLUE, width=4)
    d.polygon([(sx1 - 70, wl - 22), (sx1 - 46, wl - 22), (sx1 - 58, wl - 4)], outline=BLUE, width=3)
    text(d, ((sx0 + sx1) / 2, sy0 - 34), "SUMP  B", 44)
    text(d, (sx0 + 120, sy1 + 26), "DRAIN GRATING", 22)

    # River main -> V1 -> sump.
    pipe(d, [(330, 290), (540, 290), (540, 420), (sx0, 420)])
    valve(d, 430, 290, tag="V1", name="RIVER INLET")
    arrow(d, 600, 420, 0)
    # Sump drain -> V2 -> storm sewer.
    pipe(d, [((sx0 + sx1) / 2, sy1), ((sx0 + sx1) / 2, 690), (1140, 690), (1140, 620), (1270, 620)])
    valve(d, 1000, 690, tag="V2", name="SUMP SUCTION", tag_at=(1000, 742))
    arrow(d, 1220, 620, 0)
    # Storm sewer <-> V3 <-> river outfall (the bypass).
    pipe(d, [(1395, 560), (1395, 320)])
    valve(d, 1395, 450, vertical=True, tag="V3", name="SEWER BYPASS", tag_at=(1240, 430))
    arrow(d, 1395, 360, -90)
    arrow(d, 1440, 520, 90, RED)
    text(d, (1490, 476), "HIGH RIVER:", 21, RED)
    text(d, (1490, 498), "RUNS BACK", 21, RED)
    # The pumps, sump to outfall, mains only.
    pipe(d, [(sx1, 380), (1180, 380), (1180, 260), (1270, 260)], w=7, fill=(70, 74, 78))
    pump(d, 1030, 380, "")
    pump(d, 1110, 380, "")
    text(d, (1070, 330), "PUMPS No.1  &  No.2", 24)
    text(d, (1070, 190), "PUMPS:  415 V MAINS ONLY", 26, RED)

    # Notes along the foot.
    text(d, (80, 806), "IN A MAINS FAILURE SUMP B MAY BE EMPTIED BY GRAVITY TO THE STORM SEWER.  SEE DRILL CARD.", 25, INK, "lm")
    text(d, (80, 836), "NO ONE IS TO ENTER THE SUMP WHILE IT HOLDS WATER.   -   WARDEN", 25, RED, "lm")

    a = np.asarray(img).astype(np.float32) / 255.0
    h, w, _ = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    # Yellowed and grimy toward the foot, darker at the edges.
    grime = np.clip((yy / h) ** 2 * 0.35 + (np.abs(xx / w - 0.5) * 2) ** 4 * 0.25, 0, 0.6)
    noise = np.random.default_rng(3).normal(0, 1, (h // 8 + 1, w // 8 + 1)).astype(np.float32)
    noise = np.kron(noise, np.ones((8, 8), np.float32))[:h, :w]
    noise = np.asarray(Image.fromarray(((noise * 0.25 + 0.5).clip(0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))).astype(np.float32) / 255.0
    tint = np.array([0.86, 0.78, 0.6], np.float32)
    a = a * (1 - grime[..., None] * (1 - tint)) * (0.9 + (noise[..., None] - 0.5) * 0.35)
    # Rust streaks running down from the four screw holes and the top edge.
    rust = np.zeros((h, w), np.float32)
    for (cx, cy) in [(60, 60), (w - 60, 60), (60, h - 60), (w - 60, h - 60)] + [(rng.randint(100, w - 100), 30) for _ in range(9)]:
        width = rng.uniform(6, 22)
        length = rng.uniform(80, 420)
        col = np.exp(-((xx - cx - (yy - cy) * rng.uniform(-0.03, 0.03)) ** 2) / (2 * width ** 2))
        fall = np.clip(1 - (yy - cy) / length, 0, 1) * (yy >= cy)
        rust = np.maximum(rust, col * fall)
    rc = np.array([0.42, 0.2, 0.08], np.float32)
    a = a * (1 - rust[..., None] * 0.75) + rc * rust[..., None] * 0.6
    # Chips in the enamel: black iron showing through.
    chips = Image.new("L", (w, h), 0)
    cd = ImageDraw.Draw(chips)
    for _ in range(70):
        edge = rng.random() < 0.85
        if edge:
            side = rng.randint(0, 3)
            cx = rng.randint(0, w) if side < 2 else (rng.randint(0, 40) if side == 2 else w - rng.randint(0, 40))
            cy = (rng.randint(0, 40) if side == 0 else h - rng.randint(0, 40)) if side < 2 else rng.randint(0, h)
        else:
            cx, cy = rng.randint(0, w), rng.randint(0, h)
        r = rng.uniform(2, 11 if edge else 3.5)
        pts = [(cx + math.cos(t) * r * rng.uniform(0.5, 1.3), cy + math.sin(t) * r * rng.uniform(0.5, 1.3)) for t in np.linspace(0, math.tau, 9)]
        cd.polygon(pts, fill=255)
    cm = np.asarray(chips.filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
    a = a * (1 - cm[..., None]) + np.array([0.09, 0.07, 0.06], np.float32) * cm[..., None]
    # Somebody's tally, scratched through the enamel in the bottom corner.
    scratch = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(scratch)
    x0, y0 = w - 360, h - 150
    for g in range(5):
        for i in range(4):
            x = x0 + g * 62 + i * 11
            sd.line([(x, y0 + rng.randint(-3, 3)), (x + rng.randint(-4, 4), y0 + 70)], fill=255, width=3)
        sd.line([(x0 + g * 62 - 6, y0 + 52), (x0 + g * 62 + 44, y0 + 14)], fill=255, width=3)
    sm = np.asarray(scratch).astype(np.float32) / 255.0
    a = a * (1 - sm[..., None] * 0.7) + np.array([0.75, 0.74, 0.7], np.float32) * sm[..., None] * 0.5
    out = Image.fromarray((a.clip(0, 1) * 255).astype(np.uint8))
    out.save(OUT, quality=90)
    print("wrote", OUT, out.size)


if __name__ == "__main__":
    main()
