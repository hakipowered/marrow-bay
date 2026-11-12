#!/usr/bin/env python3
"""Gives every Obcera outfit the same head: the Red Dress model's face, hair
and the top of its ponytail, cut out once into
assets/characters/obcera/head/obcera_head.glb and worn by each outfit model in
place of its own head.

Meshy builds every outfit as a separate model, so each came out with a
slightly different face. This tool:

1. Cuts the shared head out of the donor (Red Dress): every triangle touching
   a point skinned mostly (45%+) to the head bones, which takes the face, the
   skull hair, the strands by the face and the top of the ponytail. The pale,
   skin coloured fringes on its hair strands (most visible on the strands
   beside the eyebrows) are painted the colour of the hair.
2. Removes each outfit's own head the same way at 60%, so the shared head
   overlaps the outfit's neck and the rest of its ponytail a little and
   nothing below the head (collars, straps, hair lying on the back) is cut.

CharacterModel binds the head to the outfit's skeleton by bone name, so it
sits on each outfit's own neck and follows its pose. Run once on fresh
outfit models (the outfit GLBs record that they were done and are skipped
after that), then re-import:

  python3 tools/outfits/shared_head.py
  godot --headless --import
"""
import io
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from match_skin import srgb_to_lab  # noqa: E402
from repack_glb import read_glb, write_glb  # noqa: E402
from skin_from_base import accessor  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "characters", "obcera")
DONOR = "outfits/red_dress/red_dress.glb"
TARGETS = ["obcera.glb", "outfits/catsuit/catsuit.glb", "outfits/street_heat/street_heat.glb",
           "outfits/red_dress/red_dress.glb", "outfits/beach/beach.glb", "outfits/midnight_lace/midnight_lace.glb"]
OUT = "head/obcera_head.glb"
HEAD_BONES = {"Head", "head_end", "headfront"}
DONOR_SEED_W = 0.45   # the shared head keeps a little more neck ...
TARGET_SEED_W = 0.6   # ... than the outfits lose, so the two overlap


# ---------- reading ----------

def load(path):
    js, binc = read_glb(path)
    prim = js["meshes"][0]["primitives"][0]
    a = prim["attributes"]
    d = {"js": js, "b": binc, "prim": prim, "path": path}
    for k, name in [("pos", "POSITION"), ("nrm", "NORMAL"), ("uv", "TEXCOORD_0"), ("tan", "TANGENT"), ("J", "JOINTS_0"), ("W", "WEIGHTS_0")]:
        if name in a:
            d[k] = accessor(js, binc, a[name]).copy()
    d["idx"] = accessor(js, binc, prim["indices"]).astype(np.int64).reshape(-1, 3)
    skin = js["skins"][0]
    d["names"] = [js["nodes"][j]["name"] for j in skin["joints"]]
    ibm = accessor(js, binc, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    d["bind"] = {n: np.linalg.inv(ibm[i]) for i, n in enumerate(d["names"])}
    mat = js["materials"][prim.get("material", 0)]
    pbr = mat["pbrMetallicRoughness"]
    d["img"] = {
        "albedo": js["textures"][pbr["baseColorTexture"]["index"]]["source"],
        "orm": js["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"],
        "normal": js["textures"][mat["normalTexture"]["index"]]["source"],
    }
    d["tex"] = {k: np.asarray(Image.open(io.BytesIO(image_data(js, binc, i))).convert("RGB")).astype(np.float32) / 255
                for k, i in d["img"].items()}
    d["col"] = sample(d["tex"]["albedo"], d["uv"])
    names = np.array(d["names"])
    d["hw"] = sum(d["W"][:, k] * np.isin(names[d["J"][:, k]], list(HEAD_BONES)) for k in range(4))
    lab = srgb_to_lab(d["col"].astype(np.float64))
    d["lab"] = lab
    d["hairlike"] = (np.hypot(lab[:, 1], lab[:, 2]) < 10) & (lab[:, 0] < 50)
    d["weld"], d["nw"] = weld(d["pos"])
    return d


def image_data(js, binc, i):
    bv = js["bufferViews"][js["images"][i]["bufferView"]]
    return binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]


def sample(tex, uv):
    h, w, _ = tex.shape
    u = np.clip((uv[:, 0] % 1) * (w - 1), 0, w - 1).astype(int)
    v = np.clip((uv[:, 1] % 1) * (h - 1), 0, h - 1).astype(int)
    return tex[v, u]


def weld(pos, tol=1e-5):
    """Vertices split at UV seams share a welded id."""
    key = np.round(pos / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return inv.reshape(-1), len(first)


def adjacency(n, tris):
    e = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    m = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr()
    return ((m + m.T) > 0).astype(np.float64).tocsr()


def to_nodes(d, mask):
    out = np.zeros(d["nw"], bool)
    np.logical_or.at(out, d["weld"], mask)
    return out


# ---------- picking the head and hair ----------

def face_strands(d, piece):
    """Loose strands hanging in front of the face (temples and cheeks): thin
    hair (another surface within 8 mm on either side, where the solid face
    has nothing in front and the whole head behind), grown from the hair
    coloured part through its grey and pale edges."""
    pos, nrm = d["pos"], d["nrm"]
    head = d["bind"]["Head"][:3, 3]
    top = d["bind"]["head_end"][:3, 3]
    nn = nrm / (np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9)
    chroma = np.hypot(d["lab"][:, 1], d["lab"][:, 2])
    zone = piece & (pos[:, 2] > head[2] + 0.025) & (pos[:, 1] < top[1] - 0.05) \
        & (pos[:, 1] > head[1] - 0.06) & (np.abs(pos[:, 0] - head[0]) > 0.025) \
        & (d["hairlike"] | (chroma < 9))
    tree = cKDTree(pos)
    thin = np.zeros(len(pos), bool)
    for i in np.nonzero(zone)[0]:
        for sgn in (-1.0, 1.0):
            for t in np.arange(0.002, 0.009, 0.0015):
                near = tree.query_ball_point(pos[i] + sgn * nn[i] * t, 0.004)
                if any(sgn * ((pos[k] - pos[i]) @ nn[i]) > 0.0015 for k in near):
                    thin[i] = True
                    break
            if thin[i]:
                break
    w = d["weld"]
    adj = adjacency(d["nw"], w[d["idx"]])
    okw = to_nodes(d, thin)
    selw = to_nodes(d, thin & d["hairlike"])
    q = deque(np.nonzero(selw)[0])
    while q:
        i = q.popleft()
        for j in adj.indices[adj.indptr[i]:adj.indptr[i + 1]]:
            if not selw[j] and okw[j]:
                selw[j] = True
                q.append(j)
    return selw[w]


# ---------- textures ----------

def footprint(shape, uv, tris, fills=None, grow=1):
    """Rasterises triangles in UV space: a mask, or an RGB image of per-triangle fills."""
    h, w = shape[:2]
    img = Image.new("RGB" if fills is not None else "L", (w, h), 0)
    dr = ImageDraw.Draw(img)
    for k, t in enumerate(tris):
        pts = [((uv[v, 0] % 1) * w, (uv[v, 1] % 1) * h) for v in t]
        if max(p[0] for p in pts) - min(p[0] for p in pts) > w / 2 or max(p[1] for p in pts) - min(p[1] for p in pts) > h / 2:
            continue   # wraps across the atlas edge
        if fills is None:
            dr.polygon(pts, fill=255, outline=255 if grow else None)
        else:
            c = tuple(int(x) for x in np.clip(fills[k] * 255, 0, 255))
            dr.polygon(pts, fill=c, outline=c if grow else None)
    return np.asarray(img)


def clean_hair_texels(d, tris):
    """Pale fringes on hair strands (skin bleeding onto the strand edges) go
    to the strand's own colour."""
    tex = d["tex"]["albedo"]
    hair = tris[d["hairlike"][tris].all(1)]
    mask = footprint(tex.shape, d["uv"], hair) > 0
    lab = srgb_to_lab(tex.reshape(-1, 3).astype(np.float64)).reshape(tex.shape)
    hair_lab = np.median(d["lab"][d["hairlike"] & (d["hw"] > 0.9)], 0)
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    bad = mask & ((lab[..., 0] > hair_lab[0] + 22) | (chroma > 14))
    fill = footprint(tex.shape, d["uv"], hair, fills=d["col"][hair].mean(1))
    tex[bad] = fill[bad].astype(np.float32) / 255
    print(f"  darkened {int(bad.sum())} pale texels on {len(hair)} hair triangles")


def encode(arr, mime):
    im = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8))
    buf = io.BytesIO()
    if mime == "image/png":
        im.save(buf, "PNG", optimize=True)
    else:
        im.save(buf, "JPEG", quality=92)
    return buf.getvalue()


# ---------- writing ----------

def rebuild(js, binc, views):
    """Reassembles the binary chunk with some bufferViews replaced."""
    blob = bytearray()
    for vi, v in enumerate(js["bufferViews"]):
        src = views.get(vi)
        if src is None:
            src = binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        while len(blob) % 4:
            blob += b"\0"
        v["byteOffset"] = len(blob)
        v["byteLength"] = len(src)
        blob += src
    js["buffers"] = [{"byteLength": len(blob)}]
    return bytes(blob)


def set_accessor(js, views, i, arr):
    a = js["accessors"][i]
    arr = np.ascontiguousarray(arr)
    a["count"] = int(arr.shape[0])
    a.pop("byteOffset", None)
    views[a["bufferView"]] = arr.tobytes()
    if "min" in a:
        flat = arr.reshape(arr.shape[0], -1)
        a["min"] = [float(x) for x in flat.min(0)] if a["componentType"] == 5126 else [int(x) for x in flat.min(0)]
        a["max"] = [float(x) for x in flat.max(0)] if a["componentType"] == 5126 else [int(x) for x in flat.max(0)]


def index_array(js, i, tris):
    ct = js["accessors"][i]["componentType"]
    if tris.size and tris.max() > 65535:
        js["accessors"][i]["componentType"] = ct = 5125
    return tris.reshape(-1).astype(np.uint16 if ct == 5123 else np.uint32)


def write_images(d, views, which):
    js = d["js"]
    for k in which:
        i = d["img"][k]
        mime = js["images"][i].get("mimeType", "image/jpeg")
        views[js["images"][i]["bufferView"]] = encode(d["tex"][k], mime)


# ---------- building ----------

def tuck(d, verts, lo, hi, low_in, depth):
    """Moves neck points inwards (against their normal) by up to depth metres
    across the head-weight band lo..hi: most at the low end for the shared
    head (its lower edge), most at the high end for an outfit (its cut edge)."""
    hw = d["hw"][verts]
    t = np.clip((hw - lo) / (hi - lo), 0, 1)
    amount = depth * ((1 - t) if low_in else t)
    n = d["nrm"][verts]
    n = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)
    d["pos"][verts] -= n * amount[:, None]


def build_head(d, out_path):
    piece = d["hw"] >= DONOR_SEED_W
    # Triangles mostly on the head and wholly above the shoulders, so the
    # lower edge follows the neck instead of reaching down in long shards.
    hw_t = d["hw"][d["idx"]]
    tris = d["idx"][(hw_t.mean(1) >= DONOR_SEED_W) & (hw_t.min(1) >= DONOR_SEED_W - 0.2)]
    # Its neck tucks a few millimetres under the outfit's neck towards the
    # lower edge, so the edge never shows.
    tuck(d, np.unique(tris), DONOR_SEED_W - 0.15, DONOR_SEED_W + 0.25, low_in=True, depth=0.008)
    print(f"  head: {len(tris)} triangles")
    clean_hair_texels(d, tris)
    # The strands framing the face have pale, skin coloured edges where they
    # pass the ends of the eyebrows: those go the colour of the hair.
    strands = face_strands(d, piece)
    st = tris[strands[tris].all(1) & (d["hairlike"][tris].sum(1) >= 2)]
    tex = d["tex"]["albedo"]
    m = footprint(tex.shape, d["uv"], st) > 0
    lab = srgb_to_lab(tex.reshape(-1, 3).astype(np.float64)).reshape(tex.shape)
    hair_lab = np.median(d["lab"][d["hairlike"] & (d["hw"] > 0.9)], 0)
    pale = m & (lab[..., 0] > hair_lab[0] + 25)
    hair_rgb = np.median(d["col"][d["hairlike"] & (d["hw"] > 0.9)], 0)
    # Keep a little of the texel's own shading so the strand isn't flat.
    shade = np.clip(lab[..., 0] / 100.0, 0, 1)[..., None]
    tex[pale] = (hair_rgb[None, :] * (0.85 + 0.3 * shade[pale]))
    print(f"  strands by the face: {len(st)} triangles, {int(pale.sum())} pale texels darkened")
    used = np.unique(tris)
    remap = np.full(len(d["pos"]), -1, np.int64)
    remap[used] = np.arange(len(used))
    js = json.loads(json.dumps(d["js"]))
    prim = js["meshes"][0]["primitives"][0]
    views = {}
    for k, name in [("pos", "POSITION"), ("nrm", "NORMAL"), ("uv", "TEXCOORD_0"), ("tan", "TANGENT"), ("J", "JOINTS_0"), ("W", "WEIGHTS_0")]:
        if name in prim["attributes"]:
            set_accessor(js, views, prim["attributes"][name], d[k][used])
    set_accessor(js, views, prim["indices"], index_array(js, prim["indices"], remap[tris]))
    dd = dict(d, js=js)
    write_images(dd, views, ["albedo"])
    js["meshes"][0]["name"] = "obcera_head"
    js.setdefault("extras", {})["shared_head_from"] = os.path.relpath(d["path"], ROOT)
    binc = rebuild(js, d["b"], views)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    write_glb(out_path, js, binc)
    print(f"  wrote {out_path}: {len(used)} vertices")


def strip_head(d):
    """Removes the outfit's own head: every triangle touching a point skinned
    mostly to the head bones. The neck below and the ponytail further down
    stay, and the shared head overlaps them a little."""
    seeds = d["hw"] >= TARGET_SEED_W
    # A dark collar standing round the back of the neck (the catsuit's) is
    # skinned to the head as well: it stays.
    head = d["bind"]["Head"][:3, 3]
    pos = d["pos"]
    seeds &= ~((pos[:, 1] < head[1] + 0.03) & (pos[:, 2] < head[2] + 0.03) & (d["hw"] < 0.9) & d["hairlike"])
    keep = ~seeds[d["idx"]].all(1)
    tris = d["idx"][keep]
    print(f"  removed {int((~keep).sum())} head triangles")
    # Its neck tucks under the shared head towards the cut.
    tuck(d, np.unique(tris), TARGET_SEED_W - 0.25, TARGET_SEED_W + 0.1, low_in=False, depth=0.004)
    js = d["js"]
    prim = js["meshes"][0]["primitives"][0]
    views = {}
    set_accessor(js, views, prim["attributes"]["POSITION"], d["pos"].astype(np.float32))
    set_accessor(js, views, prim["indices"], index_array(js, prim["indices"], tris))
    js.setdefault("extras", {})["shared_head"] = OUT
    binc = rebuild(js, d["b"], views)
    write_glb(d["path"], js, binc)
    print(f"  wrote {d['path']}")


def main():
    out = os.path.join(ROOT, OUT)
    donor = load(os.path.join(ROOT, DONOR))
    if not donor["js"].get("extras", {}).get("shared_head"):
        print("shared head from", DONOR)
        build_head(donor, out)
    elif not os.path.exists(out):
        sys.exit("The donor model has no head any more; restore the Obcera models from git first.")
    else:
        print("keeping the shared head in", OUT)
    for t in TARGETS:
        path = os.path.join(ROOT, t)
        d = load(path)
        if d["js"].get("extras", {}).get("shared_head"):
            print(t, "already wears the shared head")
            continue
        print(t)
        strip_head(d)


if __name__ == "__main__":
    main()
