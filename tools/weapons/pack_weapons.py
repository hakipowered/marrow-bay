#!/usr/bin/env python3
"""Shrinks the Meshy weapon models for the phone build.

Meshy embeds 2048 px textures (about 10 MB a model). A weapon in the hand is
small on screen even in the inventory's examine view, so the base colour goes
to 1024 px and the normal and metallic-roughness maps to 512 px.

  python3 tools/weapons/pack_weapons.py build_tmp/weapons assets/weapons

Each <id>.glb in the source folder becomes <out>/<id>/<id>.glb. The source
pictures and fal job ids are listed in tools/weapons/README.md.
"""
import io, json, os, struct, sys
from PIL import Image

ALBEDO, SMALL = 1024, 512


def read_glb(path):
    data = open(path, "rb").read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    off, js, binc = 12, None, b""
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
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(binc)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(binc), 0x004E4942) + binc)


def shrink(js, binc):
    role = {}
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "normalTexture" in m:
            role[js["textures"][m["normalTexture"]["index"]]["source"]] = "normal"
        if "metallicRoughnessTexture" in pbr:
            role[js["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]] = "orm"
        if "baseColorTexture" in pbr:
            role[js["textures"][pbr["baseColorTexture"]["index"]]["source"]] = "albedo"
        # Weapons are solid; single-sided halves the fragment work.
        m["doubleSided"] = False
    new_views = {}
    for i, img in enumerate(js.get("images", [])):
        bv = js["bufferViews"][img["bufferView"]]
        raw = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        im = Image.open(io.BytesIO(raw)).convert("RGB")
        r = role.get(i, "albedo")
        size = ALBEDO if r == "albedo" else SMALL
        if im.width > size:
            im = im.resize((size, size), Image.LANCZOS)
        out = io.BytesIO()
        if r == "normal":
            im.save(out, "PNG", optimize=True)
            img["mimeType"] = "image/png"
        else:
            im.save(out, "JPEG", quality=90 if r == "albedo" else 92)
            img["mimeType"] = "image/jpeg"
        new_views[img["bufferView"]] = out.getvalue()
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
    src, dst = sys.argv[1], sys.argv[2]
    for f in sorted(os.listdir(src)):
        if not f.endswith(".glb"):
            continue
        wid = f[:-4]
        js, binc = read_glb(os.path.join(src, f))
        js, binc = shrink(js, binc)
        os.makedirs(os.path.join(dst, wid), exist_ok=True)
        out = os.path.join(dst, wid, wid + ".glb")
        write_glb(out, js, binc)
        print(f"{wid}: {os.path.getsize(os.path.join(src, f)) // 1024} KB -> {os.path.getsize(out) // 1024} KB")
