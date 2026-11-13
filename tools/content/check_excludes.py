#!/usr/bin/env python3
"""The content export leaves out Poly Haven models nothing uses (the
"Android Content" preset's exclude_filter in export_presets.cfg, kept by
hand). Fails if a script uses one of them: on phones and in the browser that
prop would be an empty node.

    python3 tools/content/check_excludes.py

Run from the project root (tools/playtest.sh runs it).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    presets = open(os.path.join(ROOT, "export_presets.cfg")).read()
    excluded = set()
    for block in re.split(r"\n\[preset\.\d+\]\n", presets):
        if 'name="Android Content"' in block:
            m = re.search(r'^exclude_filter="([^"]*)"', block, re.M)
            if m:
                excluded |= set(re.findall(r"assets/polyhaven/models/([^/]+)/\*", m.group(1)))
    src = ""
    for root, _, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in files:
            if f.endswith(".gd"):
                src += open(os.path.join(root, f)).read()
    used = sorted(m for m in excluded if re.search(r'"%s[/"]' % re.escape(m), src))
    if used:
        print("used by the game but left out of the content export: " + ", ".join(used))
        print("take them off exclude_filter in export_presets.cfg (Android Content)")
        return 1
    print("content export: none of the %d models it leaves out are used" % len(excluded))
    return 0


if __name__ == "__main__":
    sys.exit(main())
