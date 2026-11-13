#!/usr/bin/env python3
"""Voice one new line with the picked cast and drop it into the game.

    FAL_KEY=... python3 tools/voice/say.py zegan z_reload "Reloading."
    FAL_KEY=... python3 tools/voice/say.py obcera o_run "RUN!" --scream
    FAL_KEY=... python3 tools/voice/say.py narrator n_ch1_open "They called it Rah-goon City."
    FAL_KEY=... python3 tools/voice/say.py tallyman tally_new "Forty-three."   (masked automatically)

Writes assets/audio/voice/<character>/<line_id>.ogg (mono, trimmed, loudness-matched).
Pass --direction "[whispering]" to override the default delivery tags (Eleven v4 voices only).
Pass --story to write a cutscene line to assets/audio/voice/story/<line_id>.ogg instead.
Listen to the result before committing: generations vary, so re-run for another take.
"""
import argparse
import json
import os
import subprocess
import tempfile
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def fal_run(endpoint, payload):
    h = {"Authorization": f"Key {os.environ['FAL_KEY']}"}
    sub = requests.post(f"https://queue.fal.run/{endpoint}", headers=h, json=payload, timeout=60)
    sub.raise_for_status()
    sub = sub.json()
    while requests.get(sub["status_url"], headers=h, timeout=60).json().get("status") != "COMPLETED":
        time.sleep(1.5)
    res = requests.get(sub["response_url"], headers=h, timeout=60)
    if res.status_code >= 300:
        raise SystemExit(f"fal error {res.status_code}: {res.text[:400]}")
    return res.json()["audio"]["url"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("character")
    ap.add_argument("line_id")
    ap.add_argument("text")
    ap.add_argument("--scream", action="store_true")
    ap.add_argument("--direction")
    ap.add_argument("--story", action="store_true", help="write to assets/audio/voice/story/ (cutscene and story lines)")
    a = ap.parse_args()
    cast = json.load(open(os.path.join(HERE, "cast.json")))
    c = cast[a.character]
    kind = "scream" if a.scream else "normal"
    if c["endpoint"].startswith("elevenlabs/"):
        tags = a.direction or c["default_direction"][kind]
        url = fal_run(c["endpoint"], {"text": f"{tags} {a.text}", "voice": c["voice"],
                                      "stability": c["stability"][kind], "output_format": "mp3_44100_192"})
    else:
        url = fal_run(c["endpoint"], {"prompt": a.text, "voice": c["voice"], "style_instructions": c["style_instructions"],
                                      "output_format": "wav", "language_code": "English (US)"})
    target = c.get("loudness_lufs", cast["loudness_lufs"][kind])
    mask = c.get("mask_filter", "")
    out_dir = os.path.join(ROOT, "assets", "audio", "voice", "story" if a.story else a.character)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{a.line_id}.ogg")
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "src")
        with open(src, "wb") as f:
            f.write(requests.get(url, timeout=120).content)
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-af",
                        "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.03,areverse,"
                        "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.12,areverse,"
                        + (mask + "," if mask else "")
                        + f"loudnorm=I={target}:TP=-1:LRA=11",
                        "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    print(out)


if __name__ == "__main__":
    main()
