#!/usr/bin/env python3
"""Cut the prologue film (assets/story/video/intro_a.ogv + intro_b.ogv).

    python3 tools/story/build_intro.py [--src /mnt/project-files/story-film] [--preview out.mp4]

The film is an edit of generated clips. Sources live outside the repo (they
are big): <src>/src/intro_*_v1.ogv are the first cut of the film (PR #3/#7),
<src>/raw/<name>.mp4 are the clips made for the 2026-11-15 rewrite (fal
MiniMax H3, Wan 3, Kling 3, Seedance 2.5, Kling AI Avatar lip-sync), see
docs/lore.md and the shot notes below.

The SHOTS lists are the edit. Each shot has an id so the CUES (voice, sound)
can be placed relative to a shot; the script prints every cue with its
absolute time on the clip's clock, which is what Chapter1Story._intro() uses.
Keep the two in step: change a shot here, rebuild, then copy the printed
times into chapter1_story.gd.

--preview also writes an MP4 with the voices, sound and music mixed in at
the cue times, for watching the film outside the game.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VOICE = os.path.join(ROOT, "assets/audio/voice/story/%s.ogg")
SSFX = os.path.join(ROOT, "assets/story/sfx/%s.ogg")
GSFX = os.path.join(ROOT, "assets/audio/sfx/%s.ogg")
MUSIC = os.path.join(ROOT, "assets/audio/music/story_intro.ogg")
W, H, FPS = 1280, 720, 24

# (id, source, in, out, options). source "v1:intro_a" = first cut, "raw:x" = <src>/raw/x.mp4
SHOTS = {
    "intro_a": [
        ("city", "v1:intro_a", 0.0, 25.583, {}),  # city, bridge, City Hall, the tunnel, the coffin, the ward
        # One continuous shot: the sleeping tunnel worker opens his eyes and they turn.
        # (Replaces a side shot that cut away mid-blink and a front shot that opened them again.)
        ("eyes", "raw:eyes_h3", 0.875, 8.0, {"fade_out": 0.25}),
        ("city2", "v1:intro_a", 32.708, 73.792, {}),  # TV, festival, blackout, the Archive desk, the street, title, CPR
        # (the first cut went on to the patient grabbing Zegan in the back; that is now told in full below)
        ("flatline", "raw:flatline_h3", 0.0, 4.0, {}),  # the monitor reads zero; he stops (after 4 s the clip shows a different patient)
        ("cover", "raw:cover_h3", 0.0, 6.0, {}),  # he draws the sheet over the dead man's face
        ("radio", "raw:radio_h3", 0.0, 10.14, {}),  # driving the body in; nobody answers the radio
        ("courier", "v1:intro_a", 80.792, 86.5, {}),  # Obcera riding, the ambulance behind her
        ("situp", "raw:situp_wan3", 0.0, 6.0, {}),  # the body under the sheet sits up
        ("grab", "raw:grab_h3", 0.0, 3.0, {}),  # it lunges through the cab window and grabs Zegan
        ("swerve", "raw:swerve_k", 0.0, 5.04, {}),  # starts on the courier shot's last frame: the ambulance swerves
        ("lookback", "raw:lookback_k", 0.8, 5.04, {"fade_out": 0.12}),  # headlights fill her mirror
    ],
    "intro_b": [
        ("crash", "raw:crash_sd", 0.0, 6.04, {}),  # the ambulance clips the bike and rolls onto its side
        ("getup", "raw:asphalt_k", 0.0, 5.04, {}),  # she gets up, hears him scream inside
        ("run", "raw:run_k", 0.0, 5.04, {}),  # runs to the rear doors with her bike lock
        ("pinned", "raw:interior_k", 0.0, 5.04, {}),  # the patient on top of Zegan, teeth at his throat
        ("swing", "raw:swing_k", 0.0, 2.6, {}),  # she swings the lock
        ("out", "v1:intro_b", 5.875, 10.917, {}),  # she gets him out and onto his feet
        ("lc1", "v1:intro_b", 10.917, 14.917, {}),
        ("lc2", "v1:intro_b", 14.917, 23.458, {}),
        ("lc3", "v1:intro_b", 23.458, 26.3, {}),
        ("parcel", "raw:parcel_k", 0.0, 5.04, {}),  # she checks the parcel in her crate
        ("that", "raw:ls_z_that", 0.0, None, {}),
        ("brother", "raw:ls_o_brother", 0.0, None, {}),
        ("shelter", "raw:ls_z_shelter", 0.0, None, {}),
        ("come", "raw:ls_o_come", 0.0, None, {}),
        ("lost", "raw:ls_z_lost", 0.0, None, {}),
        ("names", "raw:names_h3", 0.0, None, {"fade_out": 0.0}),
    ],
}

# (shot id, seconds into the shot, kind, name, volume dB, subtitle). kind: voice | story_sfx | sfx
CUES = {
    "intro_a": [
        # First cut's narration and sounds (unchanged times: the eyes shot is as long as the two it replaced).
        ("city", 1.5, "narrator", "n_intro_1", 0.0, "Every city keeps a ledger. Births. Deaths. Debts."),
        ("city", 11.8, "story_sfx", "tunnel", -9.0, ""),
        ("city", 12.0, "narrator", "n_intro_2", 0.0, "Three weeks ago, the Deep Tunnel crews broke into something the city had buried in 1891."),
        ("city", 22.05, "narrator", "n_intro_3", 0.0, "The men came home with a fever. They slept for two days... and woke up hungry."),
        ("city2", 0.292, "narrator", "n_intro_4", 0.0, "City Hall called it the flu. They locked the evidence in the Archive... and kept the river festival going."),
        ("city2", 10.592, "story_sfx", "blackout", -6.0, ""),
        ("city2", 10.792, "narrator", "n_intro_5", 0.0, "Tonight, the quarantine failed. The lights went out across downtown. And the Archive, the city's storm shelter, stopped answering the radio."),
        ("city2", 24.392, "story_sfx", "ambulance", -12.0, ""),
        ("city2", 24.642, "narrator", "n_intro_6", 0.0, "That night, Rah-goon City stopped counting the living."),
        ("city2", 30.742, "story_sfx", "title_hit", -3.0, ""),
        ("city2", 34.492, "narrator", "n_intro_7", 0.0, "Two strangers drove into it at the same moment. A paramedic, finishing his last call..."),
        # The rewrite.
        ("flatline", 0.3, "story_sfx", "flatline", -10.0, ""),
        ("radio", 0.3, "voice", "z_lc_radio", 0.0, "Dispatch, Medic Twelve. No pulse, no response... I'm bringing him in. ...Dispatch?"),
        ("radio", 5.2, "story_sfx", "radio_static", -6.0, ""),
        ("courier", 0.25, "narrator", "n_intro_8", 0.0, "...and a courier, carrying a sealed package addressed to the Archive."),
        ("situp", 1.2, "story_sfx", "sheet_rise", -4.0, ""),
        ("grab", 0.0, "sfx", "zombie_attack_1", -2.0, ""),
        ("grab", 0.2, "voice", "z_lc_grab", 0.0, "No... NO! GET OFF ME!"),
        ("swerve", 0.0, "story_sfx", "skid", -6.0, ""),
        ("lookback", 0.4, "story_sfx", "ambulance", -6.0, ""),
    ],
    "intro_b": [
        ("crash", 0.55, "story_sfx", "crash", 0.0, ""),
        ("crash", 1.4, "story_loop", "fire", -14.0, ""),
        ("getup", 2.55, "voice", "z_lc_help", -3.0, "HELP! SOMEBODY HELP ME!"),
        ("pinned", 0.0, "sfx", "zombie_attack_3", -3.0, ""),
        ("pinned", 0.6, "voice", "z_lc_strain", 0.0, "Get... OFF!"),
        ("pinned", 4.15, "voice", "o_lc_off", 0.0, "GET OFF HIM!"),
        ("swing", 0.15, "story_sfx", "door_hit", 0.0, ""),
        ("swing", 0.9, "sfx", "melee_hit_1", 0.0, ""),
        ("lc1", 0.0, "voice", "lc_1", 0.0, "You alive? Or are you gonna bite me too?"),
        ("lc2", 0.0, "voice", "lc_2", 0.0, "Ask me again in a minute. My patient... he was dead. He was dead, and he sat up."),
        ("lc3", 0.0, "voice", "lc_3", 0.0, "Yeah. The whole street's doing it."),
        ("that", 0.0, "voice", "z_lc_that", 0.0, "You nearly died... for that?"),
        ("brother", 0.0, "voice", "o_lc_brother", 0.0, "My brother sent it. Nasri. First word from him in two years. One line with it: \"Put it in my hands at the Archive. Tonight. Tell no one.\""),
        ("shelter", 0.0, "voice", "z_lc_shelter", 0.0, "The Archive's the storm shelter. Half the district went there."),
        ("come", 0.0, "voice", "o_lc_come", 0.0, "Then they'll need a medic. And I need somebody watching my back. Come with me."),
        ("lost", 0.0, "voice", "z_lc_lost", 0.0, "I couldn't save him. I'm not losing anybody else tonight."),
        ("names", 4.4, "voice", "o_lc_name", 0.0, "Obcera."),
        ("names", 5.5, "voice", "z_lc_name", 0.0, "Zegan."),
    ],
}


def run(cmd):
    subprocess.run(cmd, check=True)


def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", path]).decode().strip())


def source_path(src, s):
    kind, name = s.split(":", 1)
    if kind == "v1":
        return os.path.join(src, "src", name + "_v1.ogv")
    return os.path.join(src, "raw", name + ".mp4")


def timeline(film, src):
    """[(id, path, in, out, start_on_film, opts)]"""
    out, t = [], 0.0
    for sid, s, a, b, opts in SHOTS[film]:
        p = source_path(src, s)
        if b is None:
            b = duration(p)
        out.append((sid, p, a, b, t, opts))
        t += b - a
    return out, t


def cue_times(film, tl):
    start = {sid: st for sid, _p, _a, _b, st, _o in tl}
    return [(round(start[sid] + at, 2), kind, name, vol, text) for sid, at, kind, name, vol, text in CUES[film]]


def cut(film, src, tmp):
    tl, total = timeline(film, src)
    parts = []
    for i, (sid, p, a, b, _st, opts) in enumerate(tl):
        part = os.path.join(tmp, f"{film}_{i:02d}_{sid}.mp4")
        dur = b - a
        vf = [f"scale={W}:{H}:force_original_aspect_ratio=increase", f"crop={W}:{H}", f"fps={FPS}", "setsar=1"]
        if opts.get("fade_in"):
            vf.append(f"fade=t=in:st=0:d={opts['fade_in']}")
        if opts.get("fade_out"):
            vf.append(f"fade=t=out:st={dur - opts['fade_out']:.3f}:d={opts['fade_out']}")
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.3f}", "-i", p, "-t", f"{dur:.3f}", "-an",
             "-vf", ",".join(vf), "-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "12", "-preset", "medium", part])
        parts.append(part)
    lst = os.path.join(tmp, film + ".txt")
    with open(lst, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, film + "_joined.mp4")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
    out = os.path.join(ROOT, "assets/story/video", film + ".ogv")
    run(["ffmpeg", "-v", "error", "-y", "-i", joined, "-an", "-c:v", "libtheora", "-b:v", "2600k", out])
    return tl, total, joined


def mix(film, cues, total, tmp, with_music):
    """Mix the cues (and the music bed) to a wav the length of the film."""
    inputs, filters = [], []
    for i, (t, kind, name, vol, _text) in enumerate(cues):
        p = {"voice": VOICE, "narrator": VOICE, "sfx": GSFX}.get(kind, SSFX) % name
        if kind == "story_loop":
            inputs += ["-stream_loop", "-1", "-i", p]
        else:
            inputs += ["-i", p]
        filters.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,volume={vol}dB,"
                       f"adelay={int(t * 1000)}|{int(t * 1000)},atrim=0:{total:.3f}[c{i}]")
    n = len(cues)
    if with_music:
        inputs += ["-stream_loop", "-1", "-i", MUSIC]
        filters.append(f"[{n}:a]aformat=sample_rates=44100:channel_layouts=stereo,volume=-15dB,atrim=0:{total:.3f}[c{n}]")
        n += 1
    filters.append("".join(f"[c{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0:duration=longest,apad,atrim=0:{total:.3f}[out]")
    wav = os.path.join(tmp, film + ".wav")
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filters), "-map", "[out]", wav])
    return wav


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="/mnt/project-files/story-film")
    ap.add_argument("--preview", help="also write an MP4 of the whole film with sound")
    ap.add_argument("--only", choices=list(SHOTS), help="cut one film")
    a = ap.parse_args()
    report = {}
    with tempfile.TemporaryDirectory() as tmp:
        joined, wavs = [], []
        for film in SHOTS:
            if a.only and film != a.only:
                continue
            tl, total, j = cut(film, a.src, tmp)
            cues = cue_times(film, tl)
            report[film] = {"length": round(total, 3),
                            "shots": {sid: round(st, 3) for sid, _p, _a, _b, st, _o in tl},
                            "cues": [{"at": t, "kind": k, "name": n, "vol": v} for t, k, n, v, _x in cues]}
            if a.preview:
                joined.append(j)
                wavs.append(mix(film, cues, total, tmp, with_music=True))
        if a.preview and joined:
            parts = []
            for i, (j, w) in enumerate(zip(joined, wavs)):
                p = os.path.join(tmp, f"prev_{i}.mp4")
                run(["ffmpeg", "-v", "error", "-y", "-i", j, "-i", w, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                     "-c:a", "aac", "-b:a", "192k", "-shortest", p])
                parts.append(p)
            lst = os.path.join(tmp, "prev.txt")
            with open(lst, "w") as f:
                f.writelines(f"file '{p}'\n" for p in parts)
            run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-crf", "20",
                 "-preset", "medium", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", a.preview])
    json.dump(report, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()
