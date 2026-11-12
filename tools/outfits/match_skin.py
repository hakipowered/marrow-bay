#!/usr/bin/env python3
"""Matches an outfit model's skin tone to the base character's.

Meshy delights its base colour maps, so outfits that show a lot of skin
come out much paler than the base model (Obcera's olive skin turns almost
white). This finds the outfit's skin colour cluster in the base colour map
and moves it, in Lab, onto the base model's skin colour. Pixels far from
that cluster (clothes, hair, white fabric) are left alone.

  python3 tools/outfits/match_skin.py <base_albedo.jpg> <outfit.glb> [strength]
"""
import io
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from repack_glb import read_glb, write_glb  # noqa: E402


def srgb_to_lab(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab_to_srgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = xyz @ m.T
    c = np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055)
    return np.clip(c, 0, 1)


def skin_cluster(rgb, lo_v=0.35):
    hsv = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).convert("HSV")).astype(np.float32) / 255
    h, s, v = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    m = (h > 10) & (h < 40) & (s > 0.12) & (s < 0.55) & (v > lo_v)
    lab = srgb_to_lab(rgb[m])
    # The densest part of the skin-coloured pixels: median, then re-centre on
    # the pixels near it so brown leather or wood doesn't drag it.
    c = np.median(lab, 0)
    for _ in range(3):
        d = np.linalg.norm((lab - c) * np.array([0.35, 1, 1]), axis=1)
        c = np.median(lab[d < np.quantile(d, 0.5)], 0)
    return c


def main(base_albedo, glb, strength=1.0):
    base = np.asarray(Image.open(base_albedo).convert("RGB").resize((1024, 1024))).astype(np.float32) / 255
    target = skin_cluster(base, 0.3)
    js, binc = read_glb(glb)
    pbr = js["materials"][0]["pbrMetallicRoughness"]
    img_i = js["textures"][pbr["baseColorTexture"]["index"]]["source"]
    bv = js["bufferViews"][js["images"][img_i]["bufferView"]]
    raw = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    rgb = np.asarray(im).astype(np.float32) / 255
    small = np.asarray(im.resize((1024, 1024))).astype(np.float32) / 255
    source = skin_cluster(small, 0.45)
    lab = srgb_to_lab(rgb)
    # Weight by closeness to the outfit's skin colour, mostly in hue/chroma.
    d_ab = np.linalg.norm(lab[..., 1:] - source[1:], axis=-1)
    d_l = np.abs(lab[..., 0] - source[0])
    w = np.exp(-(d_ab / 7.0) ** 2) * np.exp(-(d_l / 30.0) ** 2) * strength
    shift = target - source
    # Lightness scales (keeps shading), chroma shifts.
    out = lab.copy()
    out[..., 0] = lab[..., 0] + w * (lab[..., 0] * (target[0] / max(source[0], 1.0)) - lab[..., 0])
    out[..., 1:] = lab[..., 1:] + w[..., None] * shift[1:]
    res = Image.fromarray((lab_to_srgb(out) * 255 + 0.5).astype(np.uint8))
    buf = io.BytesIO()
    res.save(buf, "JPEG", quality=90)
    js["images"][img_i]["mimeType"] = "image/jpeg"
    data = buf.getvalue()
    # Swap the image's bytes in place and rebuild the buffer.
    views = []
    blob = bytearray()
    for vi, v in enumerate(js["bufferViews"]):
        src = data if vi == js["images"][img_i]["bufferView"] else binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        while len(blob) % 4:
            blob += b"\0"
        v["byteOffset"] = len(blob)
        v["byteLength"] = len(src)
        blob += src
        views.append(v)
    js["buffers"] = [{"byteLength": len(blob)}]
    write_glb(glb, js, bytes(blob))
    print(f"{glb}: skin L{source[0]:.0f} a{source[1]:.0f} b{source[2]:.0f} -> L{target[0]:.0f} a{target[1]:.0f} b{target[2]:.0f}, {float((w > 0.5).mean()) * 100:.0f}% of texels moved")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.0)
