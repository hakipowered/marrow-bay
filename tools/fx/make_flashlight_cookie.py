#!/usr/bin/env python3
"""Draws the flashlight's beam pattern (the SpotLight3D projector texture).

A real torch doesn't light an even disc: a reflector focuses a bright hot
spot in the middle, ringed by a faint bright edge where the reflector ends,
then a wide dim spill that fades out softly. The reflector's facets leave
faint rings in the spill, and the lens adds a little uneven smudging. This
draws that pattern in greyscale; the light's colour warms it in the game.

The texture maps onto the spot cone with the cone's edge at the inscribed
circle, so r = 1 here is the edge of SpotLight3D.spot_angle.

  python3 tools/fx/make_flashlight_cookie.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "fx", "flashlight_cookie.png")
N = 256


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    y, x = np.mgrid[0:N, 0:N].astype(np.float64)
    u = (x + 0.5) / N * 2.0 - 1.0
    v = (y + 0.5) / N * 2.0 - 1.0
    r = np.sqrt(u * u + v * v)
    a = np.arctan2(v, u)

    hot = 0.5 * np.exp(-(r / 0.25) ** 2)                  # focused centre
    rim = 0.06 * np.exp(-((r - 0.32) / 0.05) ** 2)         # reflector edge
    spill = 0.5 * (1.0 - smoothstep(0.1, 1.0, r))          # wide soft spill
    spill *= 1.0 + 0.03 * np.sin(r * 58.0 + 0.8 * np.sin(a * 5.0)) * smoothstep(0.35, 0.5, r)  # facet rings
    beam = hot + rim + spill

    # Faint lens smudges: low-frequency noise, stronger towards the edge.
    rng = np.random.default_rng(7)
    noise = np.zeros_like(r)
    for k, amp in ((3, 0.5), (6, 0.3), (11, 0.2)):
        for _ in range(3):
            fx, fy, ph = rng.uniform(-k, k), rng.uniform(-k, k), rng.uniform(0, 6.283)
            noise += amp * np.sin(fx * u * 3.14159 + fy * v * 3.14159 + ph)
    noise /= np.abs(noise).max()
    beam *= 1.0 + 0.05 * noise * smoothstep(0.1, 0.6, r)
    beam *= 1.0 + 0.025 * np.sin(a * 7.0 + 1.3) * smoothstep(0.3, 0.8, r)

    beam *= 1.0 - smoothstep(0.80, 1.0, r)                # nothing past the cone
    beam = np.clip(beam / beam.max(), 0.0, 1.0)
    img = (beam ** (1 / 2.2) * 255.0 + 0.5).astype(np.uint8)  # stored as sRGB
    Image.fromarray(img, "L").convert("RGB").save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
