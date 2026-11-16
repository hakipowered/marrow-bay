#!/usr/bin/env python3
"""Check that new voice takes sound like the same person as a character's
reference lines, and say the right words.

    pip install sherpa-onnx librosa
    python3 tools/voice/match.py hardass take1.mp3 take2.ogg ...
    python3 tools/voice/match.py hardass --words take1.mp3    (also transcribe)

For each take it prints the cosine similarity of its speaker embedding to the
character's reference lines and to the nearest other voice (Zegan for the men,
Obcera for the women), and the margin between the two. Same voice, same
settings: margin above 0 (the safe room Hardass lines sit around +0.05, his
0.14 tannoy lines sat at -0.02 to -0.06 and sounded like another man). Lines
under 2 seconds are noisy; judge those by ear or by their longer neighbours.

The speaker model (WeSpeaker ResNet34, VoxCeleb) and, with --words, Whisper
base.en come from the sherpa-onnx GitHub releases on first run, into
~/.cache/ragoon-voice/.
"""
import argparse
import glob
import os
import tarfile
import urllib.request

import librosa
import numpy as np
import sherpa_onnx

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
VOICE = os.path.join(ROOT, "assets", "audio", "voice")
CACHE = os.path.expanduser("~/.cache/ragoon-voice")
REL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
SPK = "wespeaker_en_voxceleb_resnet34.onnx"
ASR = "sherpa-onnx-whisper-base.en"

# character: (reference globs, the voice it must not drift towards)
REFS = {
    "hardass": (["story/h1_*.ogg"], "zegan"),
    "zegan": (["zegan/*.ogg", "story/z_*.ogg", "story/z1_*.ogg"], "hardass"),
    "obcera": (["obcera/*.ogg", "story/o_*.ogg", "story/o1_*.ogg"], None),
}


def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        urllib.request.urlretrieve(url, path + ".part")
        os.replace(path + ".part", path)
    return path


def extractor():
    model = fetch(REL + "speaker-recongition-models/" + SPK, os.path.join(CACHE, SPK))
    return sherpa_onnx.SpeakerEmbeddingExtractor(sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=model, num_threads=4))


def recognizer():
    d = os.path.join(CACHE, ASR)
    if not os.path.isdir(d):
        tar = fetch(REL + "asr-models/" + ASR + ".tar.bz2", os.path.join(CACHE, ASR + ".tar.bz2"))
        with tarfile.open(tar) as t:
            t.extractall(CACHE)
    p = os.path.join(d, "base.en-")
    return sherpa_onnx.OfflineRecognizer.from_whisper(encoder=p + "encoder.onnx", decoder=p + "decoder.onnx",
                                                      tokens=p + "tokens.txt", num_threads=4)


def embed(ex, path):
    y, _ = librosa.load(path, sr=16000)
    s = ex.create_stream()
    s.accept_waveform(16000, y)
    s.input_finished()
    v = np.array(ex.compute(s))
    return v / np.linalg.norm(v), len(y) / 16000


def centroid(ex, who, skip=()):
    files = [f for g in REFS[who][0] for f in glob.glob(os.path.join(VOICE, g))]
    files = [f for f in files if os.path.abspath(f) not in skip]
    c = np.mean([embed(ex, f)[0] for f in files], axis=0)
    return c / np.linalg.norm(c), len(files)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("character", choices=sorted(REFS))
    ap.add_argument("takes", nargs="+")
    ap.add_argument("--words", action="store_true", help="also transcribe each take (Whisper base.en)")
    a = ap.parse_args()
    ex = extractor()
    skip = {os.path.abspath(t) for t in a.takes}
    ref, n = centroid(ex, a.character, skip)
    rival = REFS[a.character][1]
    other = centroid(ex, rival, skip)[0] if rival else None
    print(f"{a.character}: {n} reference lines" + (f", compared with {rival}" if rival else ""))
    rec = recognizer() if a.words else None
    for t in a.takes:
        e, secs = embed(ex, t)
        same = float(e @ ref)
        line = f"{os.path.basename(t):28s} {secs:4.1f}s  {a.character} {same:.3f}"
        if other is not None:
            near = float(e @ other)
            line += f"  {rival} {near:.3f}  margin {same - near:+.3f}"
        if secs < 2.0:
            line += "  (short: noisy)"
        if rec:
            y, _ = librosa.load(t, sr=16000)
            s = rec.create_stream()
            s.accept_waveform(16000, y)
            rec.decode_stream(s)
            line += "  | " + s.result.text.strip()
        print(line)


if __name__ == "__main__":
    main()
