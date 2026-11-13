#!/usr/bin/env python3
"""Generate the game's sound effects with ElevenLabs sound effects on fal.

    python3 tools/sfx/gen_sfx.py [id ...]      (FAL_KEY from the environment)

Each entry in SOUNDS becomes assets/audio/sfx/<id>_<n>.ogg (mono, trimmed,
loudness-matched). Sfx.play_at() picks a random numbered variant, so repeated
groans and hits don't sound identical. Existing files are kept; delete one to
make it again. Listen before committing: generations vary.
"""
import concurrent.futures as cf
import os
import subprocess
import sys
import tempfile
import time

import requests

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
EP = "fal-ai/elevenlabs/sound-effects/v2"
STYLE = "horror game sound effect, close and dry, no music, no speech"

# id: (variants, seconds, loudness LUFS, description)
SOUNDS = {
    # Ordinary infected
    "zombie_idle": (4, 2.6, -20, "a zombie's low guttural groan, wet raspy rattling breath, slow and hungry"),
    "zombie_chase": (4, 2.0, -18, "an aggressive hungry zombie moan rising into a snarl, raspy torn throat"),
    "zombie_alert": (3, 1.4, -16, "a zombie suddenly noticing prey: a sharp raspy gasp turning into a growl"),
    "zombie_attack": (4, 1.1, -15, "a zombie lunging to bite: a short vicious snarl with snapping teeth"),
    "zombie_death": (3, 2.2, -18, "a zombie's dying gurgle, a final choking wheeze as it collapses"),
    "zombie_swipe": (3, 0.6, -17, "a fast heavy arm swipe whoosh through the air, clothing rustle"),
    # Dog-like infected
    "hound_idle": (2, 2.0, -20, "a sick rabid dog's low wet growl and ragged panting"),
    "hound_chase": (2, 1.6, -18, "a rabid dog snarling and barking while charging"),
    "hound_alert": (2, 1.2, -16, "a rabid dog's sudden vicious bark and snarl"),
    "hound_attack": (2, 0.9, -15, "a rabid dog lunging and snapping its jaws, savage snarl"),
    "hound_death": (2, 1.6, -18, "a monstrous dog's dying yelp fading into a gurgle"),
    "hound_hurt": (3, 0.8, -16, "a big vicious dog hit hard: a sharp pained yelp snapping straight back into a snarl"),
    # Mutated infected (spitter, ventling)
    "mutant_idle": (2, 2.4, -20, "a mutated creature's wet clicking throat and slimy breathing"),
    "mutant_chase": (2, 1.8, -18, "a mutated creature's shrill chittering screech while running"),
    "mutant_alert": (2, 1.3, -16, "a mutated creature's sudden piercing hiss and click"),
    "mutant_attack": (2, 1.0, -15, "a mutated creature's lunging shriek with wet slashing"),
    "mutant_death": (2, 2.0, -18, "a mutated creature's dying squeal and bubbling collapse"),
    # Brute
    "brute_idle": (2, 2.6, -19, "a huge brute's deep chesty growl and heavy breathing"),
    "brute_chase": (2, 2.0, -17, "a huge brute's deep furious bellow while stomping forward"),
    "brute_alert": (2, 1.6, -15, "a huge brute's deep angry snort and growl"),
    "brute_attack": (2, 1.2, -14, "a huge brute's grunting heavy punch roar"),
    "brute_death": (2, 2.6, -17, "a huge brute's dying deep groan and heavy body falling"),
    "brute_roar": (2, 2.4, -13, "a giant monster's thunderous enraged roar before charging"),
    "brute_slam": (2, 1.2, -13, "a heavy body slamming into a brick wall, crunching impact, debris"),
    # Specials
    "screamer_shriek": (2, 3.0, -13, "a terrifying long high-pitched inhuman female shriek echoing"),
    "spitter_spit": (2, 0.9, -16, "a monster hocking up and spitting a thick wet glob of slime, throaty gurgle then a splat"),
    "acid_splash": (2, 1.0, -17, "acid splattering on concrete and sizzling, hissing steam"),
    "bloater_burst": (2, 1.6, -14, "a huge swollen sack of slime popping like a wet balloon, squelchy splash and a hiss of gas"),
    "shield_ricochet": (2, 0.8, -15, "a bullet ricocheting off a polycarbonate riot shield, sharp ping and clack"),
    "vent_burst": (1, 1.4, -14, "a metal air vent cover bursting open and clattering to the floor"),
    "metal_bang": (2, 0.9, -15, "a heavy metal bang, sheet metal struck hard"),
    # Hits
    "flesh_hit": (4, 0.5, -16, "a bullet or knife hitting flesh, wet meaty thud"),
    "player_hit": (3, 0.6, -14, "a heavy blow landing on a person's body, punch thud with clothing impact"),
    "body_fall": (2, 1.0, -17, "a lifeless body falling onto a wet concrete floor, heavy thud"),
    # World
    "door_locked": (2, 0.8, -18, "a locked old door handle rattling, won't open"),
    "door_bang": (2, 1.2, -14, "something heavy banging against a wooden door from the other side"),
    "glass_break": (2, 1.2, -15, "a pane of glass shattering, shards falling"),
    "grenade_bounce": (2, 0.6, -18, "a metal grenade bouncing and rolling on concrete"),
    "shutter_bang": (3, 1.0, -14, "a fist pounding hard on a metal roller shutter from the inside, a booming corrugated steel rattle"),
    "shutter_rattle": (1, 1.0, -15, "a metal roller shutter jerked upward a few inches and dropping back, loud clattering steel slats"),
    "shutter_roll": (1, 1.4, -13, "a metal roller shutter forced violently all the way up, fast loud rolling clatter of steel slats ending in a bang"),
    "ceiling_break": (1, 1.6, -14, "an old plaster ceiling cracking and caving in, splintering wood laths, plaster chunks and dust pouring down"),
    "power_down": (1, 2.0, -18, "electrical power failing, lights buzzing off with a dying hum"),
    # The vault circuit: the boiler-room breaker and the vault elevator.
    "breaker_throw": (1, 1.4, -14, "a big old industrial knife switch thrown up by hand: a heavy metal clunk, a short crackle of electric arcing, then a low transformer hum starting"),
    "breaker_dead": (1, 0.8, -19, "an old electrical breaker handle rattled but stuck, dry metal clack, nothing happens"),
    "power_up": (1, 3.0, -17, "old fluorescent tube lights flickering on one after another in a basement: ticking starters, buzzing, a rising mains hum"),
    "lift_dead": (1, 0.9, -19, "pressing a dead elevator call button: a hollow plastic click, then silence"),
    "card_beep": (1, 0.6, -18, "an old security card reader accepting a key card: a short electronic chirp and a relay click"),
    "lift_doors": (1, 2.2, -15, "heavy steel freight elevator doors sliding open on worn runners: a motor whine, metal rumble and a final clank"),
    "lift_ride": (1, 6.0, -16, "an old freight elevator starting its descent: a jolt and a clank, cables groaning, a deep motor drone and rattling metal walls going down a shaft"),
    "roll_whoosh": (2, 0.9, -19, "a person diving into a quick forward roll on a hard floor: fast cloth rustle and whoosh, then a soft body thump and gear rattle"),
    "game_over_sting": (1, 5.0, -15, "a dark orchestral horror sting: one deep low brass and timpani hit, dissonant strings swelling, a distant mournful choir, then fading slowly to silence"),
    # Weapons. The pump shotgun (weapon_m12_*) isn't here: generations come
    # back as a bare 0.2 s blast, so its files are the first batch's take,
    # cut so the pump rack lands before the next shot (tools/weapons/README.md).
    "weapon_breacher": (2, 0.9, -9, "a semi-automatic combat shotgun firing one deafening 12 gauge blast, heavy boom with a sharp crack and a short room echo"),
    "weapon_bolt": (2, 0.9, -15, "a heavy crossbow firing: a loud bowstring snap and wooden thwack, the bolt hissing away"),
    "weapon_knife": (2, 0.6, -20, "a combat knife slashing fast through the air, sharp swish"),
    "weapon_hatchet": (2, 0.8, -19, "a heavy hatchet swung hard through the air, deep whoosh"),
    # The stalker
    "stalker_step": (3, 0.8, -15, "one very heavy boot footstep on a hard floor, deep thud"),
    "stalker_swing": (2, 0.9, -14, "a huge fist swinging through the air, heavy whoosh"),
    "stalker_kneel": (1, 1.2, -17, "a very heavy man kneeling down, leather creak and coat rustle"),
}


def fal_run(payload):
    h = {"Authorization": f"Key {os.environ['FAL_KEY']}"}
    for attempt in range(4):
        sub = requests.post(f"https://queue.fal.run/{EP}", headers=h, json=payload, timeout=60)
        if sub.status_code == 429:
            time.sleep(5 * (attempt + 1))
            continue
        sub.raise_for_status()
        sub = sub.json()
        t0 = time.time()
        while requests.get(sub["status_url"], headers=h, timeout=60).json().get("status") != "COMPLETED":
            if time.time() - t0 > 240:
                raise TimeoutError("timed out")
            time.sleep(1.5)
        res = requests.get(sub["response_url"], headers=h, timeout=60)
        if res.status_code >= 300:
            raise RuntimeError(f"fal error {res.status_code}: {res.text[:300]}")
        return res.json()["audio"]["url"]
    raise RuntimeError("fal busy (429)")


def make(sid, n, secs, lufs, text):
    out = os.path.join(OUT, f"{sid}_{n}.ogg")
    if os.path.exists(out):
        return f"keep {sid}_{n}"
    url = fal_run({"text": f"{text}. {STYLE}", "duration_seconds": secs, "prompt_influence": 0.55})
    with tempfile.TemporaryDirectory() as d:
        raw = os.path.join(d, "raw.mp3")
        with open(raw, "wb") as f:
            f.write(requests.get(url, timeout=120).content)
        trim = "silenceremove=start_periods=1:start_threshold=-48dB,areverse,silenceremove=start_periods=1:start_threshold=-48dB,areverse"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", raw, "-ac", "1", "-ar", "44100",
                        "-af", f"{trim},loudnorm=I={lufs}:TP=-1.5:LRA=11,afade=t=out:st={max(secs - 0.08, 0.05)}:d=0.08",
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    return f"made {sid}_{n}"


def main():
    want = set(sys.argv[1:])
    jobs = [(sid, n, s[1], s[2], s[3]) for sid, s in SOUNDS.items() if not want or sid in want for n in range(1, s[0] + 1)]
    failed = 0
    with cf.ThreadPoolExecutor(8) as ex:
        for f in cf.as_completed([ex.submit(make, *j) for j in jobs]):
            try:
                print(f.result(), flush=True)
            except Exception as e:
                failed += 1
                print("FAILED", e, flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
