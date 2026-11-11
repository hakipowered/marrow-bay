#!/usr/bin/env python3
"""Download the CC0 textures and models listed in assets_manifest.json from Poly Haven.

Usage: python3 tools/fetch_assets.py   (run from the project root)
Textures land in assets/polyhaven/textures/<slot>/{albedo,normal,arm}.jpg
Models land in assets/polyhaven/models/<Name>/<Name>.gltf (+ .bin and textures/)
"""
import json, os, sys, urllib.request, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "polyhaven")
API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "ragoon-city-asset-fetch/1.0"}

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()

def save(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = get(url)
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.replace(path + ".part", path)

def texture(slot, asset, res):
    files = json.loads(get(API + asset))
    d = os.path.join(OUT, "textures", slot)
    for key, name in (("Diffuse", "albedo"), ("nor_gl", "normal"), ("arm", "arm")):
        r = files[key].get(res) or files[key]["1k"]
        save(r["jpg"]["url"], os.path.join(d, name + ".jpg"))
    with open(os.path.join(d, "SOURCE.txt"), "w") as f:
        f.write(f"https://polyhaven.com/a/{asset} (CC0)\n")
    return slot

def model(name, res):
    files = json.loads(get(API + name))
    g = files["gltf"].get(res) or files["gltf"]["1k"]
    g = g["gltf"]
    d = os.path.join(OUT, "models", name)
    save(g["url"], os.path.join(d, name + ".gltf"))
    for rel, inc in g.get("include", {}).items():
        save(inc["url"], os.path.join(d, rel))
    return name

def main():
    m = json.load(open(os.path.join(ROOT, "tools", "assets_manifest.json")))
    res = m.get("resolution", "1k")
    jobs = []
    with cf.ThreadPoolExecutor(8) as ex:
        for slot, asset in m["textures"].items():
            jobs.append(ex.submit(texture, slot, asset, res))
        for name in m["models"]:
            jobs.append(ex.submit(model, name, res))
        failed = 0
        for j in cf.as_completed(jobs):
            try:
                print("ok", j.result())
            except Exception as e:
                failed += 1
                print("FAILED", e, file=sys.stderr)
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
