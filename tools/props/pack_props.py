#!/usr/bin/env python3
"""Shrinks Meshy prop models (chapter 2's generator, fuse, crank handle, clock
key...) for the phone build, like tools/weapons/pack_weapons.py does for guns.

  python3 tools/props/pack_props.py build_tmp/props assets/props

Each <id>.glb in the source folder becomes <out>/<id>/<id>.glb. Big set
pieces the camera gets close to keep a 2048 px base colour; furniture goes
to 1024 (base colour) and 512 (normal, metal-roughness); small key items to
512 and 256. The source
pictures and fal job ids are listed in tools/props/README.md.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "weapons"))
import pack_weapons as pw

# id: (albedo px, normal / metal-roughness px)
SIZES = {"generator": (2048, 1024), "fuse": (512, 256), "crank_handle": (512, 256), "clock_key": (512, 256)}
DEFAULT = (1024, 512)

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    for f in sorted(os.listdir(src)):
        if not f.endswith(".glb"):
            continue
        pid = f[:-4]
        if only and pid not in only:
            continue
        pw.ALBEDO, pw.SMALL = SIZES.get(pid, DEFAULT)
        js, binc = pw.read_glb(os.path.join(src, f))
        js, binc = pw.shrink(js, binc)
        os.makedirs(os.path.join(dst, pid), exist_ok=True)
        out = os.path.join(dst, pid, pid + ".glb")
        pw.write_glb(out, js, binc)
        print(f"{pid}: {os.path.getsize(os.path.join(src, f)) // 1024} KB -> {os.path.getsize(out) // 1024} KB")
