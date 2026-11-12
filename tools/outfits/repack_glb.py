#!/usr/bin/env python3
"""Shrinks a Meshy character GLB for the phone build.

Meshy embeds 2048 px textures: a PNG normal map (about 5 MB), the base colour
(JPEG) and the metallic-roughness map (JPEG). The base colour stays at 2048
for close-ups; the normal and metallic-roughness maps go to 1024, which is
plenty at phone resolution and keeps the repo and the APK lean.

  python3 tools/outfits/repack_glb.py in.glb out.glb
"""
import io
import json
import struct
import sys

from PIL import Image

HALF = 1024


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    off = 12
    js, binc = None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def write_glb(path, js, binc):
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binc += b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(binc)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(binc), 0x004E4942) + binc)


def shrink(js, binc):
    # Which image is used how.
    role = {}
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "normalTexture" in m:
            role[js["textures"][m["normalTexture"]["index"]]["source"]] = "normal"
        if "metallicRoughnessTexture" in pbr:
            role[js["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]] = "orm"
        if "baseColorTexture" in pbr:
            role[js["textures"][pbr["baseColorTexture"]["index"]]["source"]] = "albedo"
    new_views = {}
    for i, img in enumerate(js.get("images", [])):
        bv = js["bufferViews"][img["bufferView"]]
        raw = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        im = Image.open(io.BytesIO(raw))
        r = role.get(i, "albedo")
        out = io.BytesIO()
        if r == "normal":
            im = im.convert("RGB")
            if im.width > HALF:
                im = im.resize((HALF, HALF), Image.LANCZOS)
            im.save(out, "PNG", optimize=True)
            img["mimeType"] = "image/png"
        elif r == "orm":
            im = im.convert("RGB")
            if im.width > HALF:
                im = im.resize((HALF, HALF), Image.LANCZOS)
            im.save(out, "JPEG", quality=92)
            img["mimeType"] = "image/jpeg"
        else:
            im = im.convert("RGB")
            im.save(out, "JPEG", quality=90)
            img["mimeType"] = "image/jpeg"
        new_views[img["bufferView"]] = out.getvalue()
        print(f"  image {i} ({r}): {len(raw) // 1024} KB -> {len(new_views[img['bufferView']]) // 1024} KB, {im.size}")
    # Rebuild the binary chunk view by view.
    blob = bytearray()
    for vi, bv in enumerate(js["bufferViews"]):
        src = new_views.get(vi)
        if src is None:
            o = bv.get("byteOffset", 0)
            src = binc[o: o + bv["byteLength"]]
        while len(blob) % 4:
            blob += b"\0"
        bv["byteOffset"] = len(blob)
        bv["byteLength"] = len(src)
        bv["buffer"] = 0
        blob += src
    js["buffers"] = [{"byteLength": len(blob)}]
    return js, bytes(blob)


if __name__ == "__main__":
    js, binc = read_glb(sys.argv[1])
    js, binc = shrink(js, binc)
    write_glb(sys.argv[2], js, binc)
    print(sys.argv[2], len(open(sys.argv[2], "rb").read()) // 1024, "KB")
