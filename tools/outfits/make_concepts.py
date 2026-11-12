"""Outfit concept art for the survivors.

Edits A-pose renders of the in-game model into each outfit with Nano Banana on
fal (needs FAL_KEY), front first, then the back view using the new front as
the reference. Prints the fal.media addresses that Meshy image-to-3D takes.

  python3 tools/outfits/make_concepts.py <render_dir> <out_dir> [character:outfit ...]

render_dir holds <character>_front.png and <character>_back.png from
tests/render_reference.gd.
"""
import base64, concurrent.futures as cf, json, os, sys, time
import requests

H = {"Authorization": "Key " + os.environ["FAL_KEY"], "Content-Type": "application/json"}
ENGINES = {"nano": "fal-ai/nano-banana-2/edit", "seedream": "fal-ai/bytedance/seedream/v4/edit"}
SPEC = json.load(open(os.path.join(os.path.dirname(__file__), "outfits.json")))


def data_uri(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()


def run(payload, engine="nano", timeout=600):
    payload = dict(payload, num_images=1)
    if engine == "nano":
        payload.update(output_format="png", resolution="2K")
    else:
        payload.update(image_size={"width": 1344, "height": 2016})
    r = requests.post(f"https://queue.fal.run/{ENGINES[engine]}", headers=H, json=payload, timeout=120)
    r.raise_for_status()
    sub = r.json()
    t0 = time.time()
    while requests.get(sub["status_url"], headers=H, timeout=60).json().get("status") != "COMPLETED":
        if time.time() - t0 > timeout:
            raise TimeoutError(payload["prompt"][:60])
        time.sleep(3)
    res = requests.get(sub["response_url"], headers=H, timeout=60)
    if res.status_code >= 300:
        raise RuntimeError(res.text[:300])
    return res.json()["images"][0]["url"]


def fetch(url, path):
    with open(path, "wb") as f:
        f.write(requests.get(url, timeout=300).content)


def make(char, oid, render_dir, out_dir):
    o = SPEC["outfits"][char][oid]
    keep = SPEC["keep"][char]
    front = run({
        "prompt": f"{o['prompt']} {keep} {SPEC['common']} This is the front view.",
        "image_urls": [data_uri(os.path.join(render_dir, f"{char}_front.png"))],
    }, o.get("engine", "nano"))
    fetch(front, os.path.join(out_dir, f"{char}_{oid}_front.png"))
    back = run({
        "prompt": "The first image is the back view of a character. Change only the clothes so they match the outfit in the second image (the same character seen from the front), as it would look from directly behind. "
        f"{o['prompt']} {keep} Keep the first image's back view, the same A-pose and the same framing. {SPEC['common']}",
        "image_urls": [data_uri(os.path.join(render_dir, f"{char}_back.png")), front],
    }, o.get("engine", "nano"))
    fetch(back, os.path.join(out_dir, f"{char}_{oid}_back.png"))
    return {"id": f"{char}:{oid}", "front": front, "back": back}


if __name__ == "__main__":
    render_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    wanted = sys.argv[3:] or [f"{c}:{o}" for c in SPEC["outfits"] for o in SPEC["outfits"][c]]
    results = {}
    with cf.ThreadPoolExecutor(6) as ex:
        futs = {ex.submit(make, *w.split(":"), render_dir, out_dir): w for w in wanted}
        for f in cf.as_completed(futs):
            try:
                r = f.result()
                results[r["id"]] = r
                print(json.dumps(r), flush=True)
            except Exception as e:
                print("FAILED", futs[f], e, flush=True)
    path = os.path.join(out_dir, "concepts.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(results)
    json.dump(old, open(path, "w"), indent=1)
