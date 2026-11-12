#!/usr/bin/env python3
"""Rigs an unrigged outfit model on the base character's own skeleton.

For outfit models that Meshy's rigging won't take, made instead with another
image-to-3D service (Hunyuan3D). The model is fitted onto the base model in
its bind pose (up axis, facing, scale and offset, refined with a trimmed
ICP), then every vertex takes the bone weights of the nearest base-model
vertices. The result is a GLB with the base skeleton, skin and bind matrices,
so the base clips play on it unchanged.

  python3 tools/outfits/skin_from_base.py base.glb outfit.glb out.glb
"""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

CTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = open(path, "rb").read()
    off, js, binc = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        else:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = CTYPE[a["componentType"]]
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    if stride and stride != n * np.dtype(dt).itemsize:
        rows = [np.frombuffer(binc, dt, n, start + k * stride) for k in range(a["count"])]
        return np.array(rows)
    return np.frombuffer(binc, dt, a["count"] * n, start).reshape(a["count"], n) if n > 1 else np.frombuffer(binc, dt, a["count"], start)


def image_bytes(js, binc, i):
    bv = js["bufferViews"][js["images"][i]["bufferView"]]
    return binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def fit(src, dst):
    """Uniform scale + translation (+ facing flip) taking src onto dst."""
    tree = cKDTree(dst)
    best = None
    for flip in (False, True):
        p = src.copy()
        if flip:
            p[:, 0] *= -1
            p[:, 2] *= -1
        # Start from the bounding boxes: same height, feet on the floor, centred.
        s = (dst[:, 1].max() - dst[:, 1].min()) / (p[:, 1].max() - p[:, 1].min())
        t = np.array([np.median(dst[:, 0]) - np.median(p[:, 0]) * s, dst[:, 1].min() - p[:, 1].min() * s, np.median(dst[:, 2]) - np.median(p[:, 2]) * s])
        sample = p[np.random.default_rng(1).choice(len(p), min(len(p), 12000), replace=False)]
        for _ in range(40):
            q = sample * s + t
            d, idx = tree.query(q)
            keep = d < np.quantile(d, 0.8)   # trimmed: ignore hair, bags, heels
            a, b = sample[keep], dst[idx[keep]]
            am, bm = a.mean(0), b.mean(0)
            s = float(((a - am) * (b - bm)).sum() / ((a - am) ** 2).sum())
            t = bm - s * am
        err = float(np.mean(tree.query(sample * s + t)[0]))
        print(f"  facing {'flipped' if flip else 'as is'}: scale {s:.4f}, mean gap {err * 100:.2f} cm")
        if best is None or err < best[0]:
            best = (err, flip, s, t)
    return best


def main(base_path, outfit_path, out_path):
    bj, bb = read_glb(base_path)
    oj, ob = read_glb(outfit_path)
    bprim = bj["meshes"][0]["primitives"][0]["attributes"]
    base_pos = accessor(bj, bb, bprim["POSITION"]).astype(np.float64)
    base_joints = accessor(bj, bb, bprim["JOINTS_0"]).astype(np.int64)
    base_w = accessor(bj, bb, bprim["WEIGHTS_0"]).astype(np.float64)
    oprim = oj["meshes"][0]["primitives"][0]
    pos = accessor(oj, ob, oprim["attributes"]["POSITION"]).astype(np.float64)
    nrm = accessor(oj, ob, oprim["attributes"]["NORMAL"]).astype(np.float64)
    uv = accessor(oj, ob, oprim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    idx = accessor(oj, ob, oprim["indices"]).astype(np.uint32)
    # Bake the outfit's node rotation/scale (Hunyuan exports Z-up under a +90 deg X turn).
    node = next(n for n in oj["nodes"] if "mesh" in n)
    m = np.eye(3)
    if "rotation" in node:
        m = quat_mat(node["rotation"])
    if "scale" in node:
        m = m @ np.diag(node["scale"])
    pos = pos @ m.T
    nrm = nrm @ m.T
    err, flip, s, t = fit(pos, base_pos)
    if flip:
        pos[:, 0] *= -1
        pos[:, 2] *= -1
        nrm[:, 0] *= -1
        nrm[:, 2] *= -1
    pos = pos * s + t
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
    print(f"fitted: facing {'flipped' if flip else 'as is'}, scale {s:.4f}, mean gap {err * 100:.2f} cm, {len(pos)} vertices")
    # Weights from the 6 nearest base vertices, blended by inverse distance.
    tree = cKDTree(base_pos)
    d, nn = tree.query(pos, k=6)
    inv = 1.0 / np.maximum(d, 1e-4) ** 2
    acc = np.zeros((len(pos), len(bj["skins"][0]["joints"])))
    for k in range(6):
        for c in range(4):
            np.add.at(acc, (np.arange(len(pos)), base_joints[nn[:, k], c]), base_w[nn[:, k], c] * inv[:, k])
    top = np.argsort(-acc, axis=1)[:, :4]
    tw = np.take_along_axis(acc, top, 1)
    tw /= tw.sum(1, keepdims=True)
    joints = top.astype(np.uint8)
    weights = tw.astype(np.float32)
    # Textures: base colour 2048 JPEG, normal 1024 PNG, metallic-roughness 1024 JPEG.
    mat = oj["materials"][oprim.get("material", 0)]
    pbr = mat["pbrMetallicRoughness"]

    def tex(info, size, fmt):
        im = Image.open(io.BytesIO(image_bytes(oj, ob, oj["textures"][info["index"]]["source"]))).convert("RGB")
        if im.width > size:
            im = im.resize((size, size), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, fmt, **({"quality": 90} if fmt == "JPEG" else {"optimize": True}))
        return out.getvalue(), "image/jpeg" if fmt == "JPEG" else "image/png"

    images = [tex(mat["normalTexture"], 1024, "PNG"), tex(pbr["baseColorTexture"], 2048, "JPEG"), tex(pbr["metallicRoughnessTexture"], 1024, "JPEG")]
    # New GLB: the base's skeleton nodes, skin and bind matrices, with this mesh.
    js = json.loads(json.dumps(bj))
    blob = bytearray()
    views, accs = [], []

    def add_view(raw, target=None):
        while len(blob) % 4:
            blob.append(0)
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            v["target"] = target
        blob.extend(raw)
        views.append(v)
        return len(views) - 1

    def add_acc(arr, ctype, typ, target, minmax=False):
        a = {"bufferView": add_view(arr.tobytes(), target), "componentType": ctype, "count": int(len(arr)), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    attrs = {
        "POSITION": add_acc(pos.astype(np.float32), 5126, "VEC3", 34962, True),
        "NORMAL": add_acc(nrm.astype(np.float32), 5126, "VEC3", 34962),
        "TEXCOORD_0": add_acc(uv, 5126, "VEC2", 34962),
        "JOINTS_0": add_acc(joints, 5121, "VEC4", 34962),
        "WEIGHTS_0": add_acc(weights, 5126, "VEC4", 34962),
    }
    ind = add_acc(idx, 5125, "SCALAR", 34963)
    ibm_src = accessor(bj, bb, bj["skins"][0]["inverseBindMatrices"]).astype(np.float32)
    ibm = add_acc(ibm_src, 5126, "MAT4", None)
    img_ids = []
    for raw, mime in images:
        img_ids.append({"bufferView": add_view(raw), "mimeType": mime})
    js["images"] = [dict(im, name=n) for im, n in zip(img_ids, ["normal", "Image_0", "Image_1"])]
    js["textures"] = [{"source": 0}, {"source": 1}, {"source": 2}]
    js.pop("samplers", None)
    js["materials"] = [{"name": "Material_0", "doubleSided": True, "normalTexture": {"index": 0},
                        "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}, "metallicRoughnessTexture": {"index": 2}}}]
    js["meshes"] = [{"name": "char1", "primitives": [{"attributes": attrs, "indices": ind, "material": 0}]}]
    js["skins"][0]["inverseBindMatrices"] = ibm
    js["accessors"] = accs
    js["bufferViews"] = views
    js["buffers"] = [{"byteLength": len(blob)}]
    js.pop("animations", None)
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(blob)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    print(out_path, len(open(out_path, "rb").read()) // 1024, "KB")


if __name__ == "__main__":
    main(*sys.argv[1:4])
