#!/usr/bin/env python3
"""Flag game sounds that are silent or cut to a click.

    python3 tools/sfx/check_sfx.py      (needs ffmpeg and numpy; prints SFX OK)

Nineteen sounds (shotgun, revolver, rifles, rocket, explosion, flashbang,
flamethrower, reloads, bag clicks) once shipped holding only their first
hundredth of a second, then silence. This decodes every Ogg under
assets/audio and fails on any whose audible part is shorter than 60 ms or
that never gets louder than -25 dBFS.
"""
import glob
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SR = 22050
bad = 0
files = sorted(glob.glob(os.path.join(ROOT, "assets", "audio", "**", "*.ogg"), recursive=True))
for f in files:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", f, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    loud = np.nonzero(np.abs(x) > 1e-3)[0]
    span = (loud[-1] - loud[0]) / SR if len(loud) else 0.0
    peak = 20 * np.log10(np.abs(x).max() + 1e-9) if len(x) else -200.0
    if span < 0.06 or peak < -25:
        bad += 1
        print(f"FAIL {os.path.relpath(f, ROOT)}: audible for {span * 1000:.0f} ms, peak {peak:.1f} dBFS")
print(f"SFX OK ({len(files)} files)" if bad == 0 else f"SFX FAILED ({bad} of {len(files)})")
sys.exit(1 if bad else 0)
