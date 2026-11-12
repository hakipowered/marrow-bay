#!/usr/bin/env python3
"""Enemy health against the ammo you can find, area by area (archive hub).

    python3 tools/balance_report.py

For each area it adds up the infected's health and what it takes to clear it
with Warden P9 body shots (26 damage), then the ammo the player has by then:
the starting 45 rounds, every ammo pickup and weapon found so far (as P9-shot
equivalents, by damage), plus the expected drops from kills (zombie drop
table). "Spare" is what's left over if every shot is a body shot; head shots
(x3) only make it easier. Exits 1 if any area runs short.
"""
import re
import sys
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
P9 = 26.0
MISS = 1.25          # assume one shot in five misses on a phone
AVG_HP = 0.99        # zombie.gd rolls 0.94 .. 1.04 of the listed health

def read(p):
    return open(os.path.join(ROOT, p)).read()

db = read("scripts/enemies/enemy_db.gd")
hp = {m.group(1): float(m.group(2)) for m in re.finditer(r'"(\w+)": \{"hp": (\d+)', db)}
shield = {m.group(1): float(m.group(2)) for m in re.finditer(r'"(\w+)": \{[^}]*"shield_hp": (\d+)', db)}
drops = {m.group(1): m.group(2) for m in re.finditer(r'"(\w+)": \{[^}]*"drop": "(\w+)"', db)}

wdb = read("scripts/weapons/weapon_db.gd")
pickup = {m.group(1): int(m.group(2)) for m in re.finditer(r'"(\w+)": \{"name": "[^"]+", "stack": \d+, "pickup": (\d+)\}', wdb)}
# Rough damage per round of each ammo type, in P9 shots.
PER_ROUND = {"9mm": 1.0, "shells": 100 / P9, "50cal": 160 / P9, "rifle": 220 / P9, "grenades": 180 / P9, "fuel": 9 * 0.5 / P9, "bolts": 120 / P9}
WEAPON_MAG = {"m12": ("shells", 5), "longshot": ("rifle", 5), "gl": ("grenades", 1), "bastion": ("50cal", 6)}
# Expected 9mm per kill from the zombie table (30 of 100 weight, 15 rounds) and shells (10 of 100, 6 shells).
DROP_SHOTS = {"zombie": 0.30 * 15 + 0.10 * 6 * PER_ROUND["shells"], "brute": 0.30 * 6 * PER_ROUND["50cal"] + 0.30 * 2 * PER_ROUND["grenades"], "none": 0.0}

hub = read("scripts/levels/archive_hub.gd")
areas = re.split(r"\nfunc (_\w+)\(\) -> void:", hub)
order = ["_street", "_courtyard", "_great_hall", "_west_corridor", "_reading_room", "_office_safe_room", "_records_vault", "_boiler_room"]
bodies = {areas[i]: areas[i + 1] for i in range(1, len(areas) - 1, 2)}

have = 45.0  # P9: 15 in the gun, 30 spare
short = False
print("%-18s %6s %6s %8s %8s %7s" % ("area", "foes", "health", "needs", "has", "spare"))
for a in order:
    body = bodies.get(a, "")
    foes = re.findall(r'place_zombie\("[^"]+", Vector3\([^)]*\), [-\d.]+, "(\w+)"', body)
    for item in re.findall(r'place_pickup\("([^"]+)"', body):
        kind, _, what = item.partition(":")
        if kind == "ammo":
            have += pickup.get(what, 0) * PER_ROUND.get(what, 0)
        elif kind == "weapon" and what in WEAPON_MAG:
            t, n = WEAPON_MAG[what]
            have += n * PER_ROUND[t]
    health = sum(hp[f] * AVG_HP + shield.get(f, 0) for f in foes)
    need = health / P9 * MISS
    spare = have - need
    print("%-18s %6d %6d %8.0f %8.0f %7.0f" % (a[1:], len(foes), health, need, have, spare))
    if spare < 0:
        short = True
    have = spare + sum(DROP_SHOTS.get(drops.get(f, "none"), 0) for f in foes)
print("\nneeds/has/spare in P9 body shots (26 dmg each), %d%% misses included." % ((MISS - 1) * 100))
sys.exit(1 if short else 0)
