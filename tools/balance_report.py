#!/usr/bin/env python3
"""Enemy health against the ammo you can find, area by area: chapter 1 (the
archive hub), then chapter 2 (the Undercroft) with what's left over.

    python3 tools/balance_report.py

For each area it adds up the infected's health and what it takes to clear it
with Warden P9 body shots (26 damage), then the ammo the player has by then:
the starting 45 rounds, every ammo pickup and weapon found so far (as P9-shot
equivalents, by damage), plus the expected drops from kills (zombie drop
table). "Spare" is what's left over if every shot is a body shot; head shots
(x3) only make it easier. Exits 1 if any area runs short.

Chapter 2 counts the generator's crank waves (GeneratorSet.WAVE_MIX) and the
Warden (WardenBoss.HP, every shot a body shot; the growth on his back counts
triple, so this is the worst case). Its pickups in the muster room come after
his fight, so they count from the crank waves on.
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

def funcs(path):
    src = read(path)
    parts = re.split(r"\nfunc (_\w+)\(\) -> void:", src)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}

def gd_const(path, name):
    return re.search(r"const %s := ([\d.]+)" % name, read(path)).group(1)

hub = funcs("scripts/levels/archive_hub.gd")
ch1 = [(a[1:], [], hub.get(a, "")) for a in ["_street", "_courtyard", "_great_hall", "_west_corridor", "_reading_room", "_office_safe_room", "_records_vault", "_boiler_room"]]

uc = funcs("scripts/levels/undercroft.gd")
gen = read("scripts/world/generator_set.gd")
mix = re.search(r"const WAVE_MIX := \[(.*?)\n\]", gen, re.S).group(1)
waves = re.findall(r'"(\w+)"', mix)
warden_hp = float(gd_const("scripts/enemies/warden_boss.gd", "HP"))
muster = uc.get("_muster_room", "")
# In the order they're played: the engine hall is walked through first.
ch2 = [
    ("c2 lift pit", [], uc.get("_lift_pit", "")),
    ("c2 corridor", [], uc.get("_service_corridor", "")),
    ("c2 engine hall", [], uc.get("_engine_hall", "")),
    ("c2 lodge", [], uc.get("_keepers_lodge", "")),
    ("c2 survey room", [], uc.get("_survey_room", "")),
    ("c2 clock gallery", [], uc.get("_clock_gallery", "")),
    ("c2 coal yard", [], uc.get("_coal_yard", "") + uc.get("_fuel_shed", "")),
    ("c2 the Warden", [("warden", warden_hp)], re.sub(r"place_pickup\(", "#", muster)),
    ("c2 crank waves", waves, "".join(re.findall(r"place_pickup\([^\n]*", muster))),
    ("c2 deep stacks", [], uc.get("_deep_stacks", "")),
]

have = 45.0  # P9: 15 in the gun, 30 spare
short = False
print("%-18s %6s %6s %8s %8s %7s" % ("area", "foes", "health", "needs", "has", "spare"))
for name, extra, body in ch1 + ch2:
    foes = re.findall(r'place_zombie\("[^"]+", Vector3\([^)]*\), [-\d.]+, "(\w+)"', body)
    boss_hp = 0.0
    for f in extra:
        if isinstance(f, tuple):
            boss_hp += f[1]
        else:
            foes.append(f)
    for item in re.findall(r'place_pickup\("([^"]+)"', body):
        kind, _, what = item.partition(":")
        if kind == "ammo":
            have += pickup.get(what, 0) * PER_ROUND.get(what, 0)
        elif kind == "weapon" and what in WEAPON_MAG:
            t, n = WEAPON_MAG[what]
            have += n * PER_ROUND[t]
    health = sum(hp[f] * AVG_HP + shield.get(f, 0) for f in foes) + boss_hp
    need = health / P9 * MISS
    spare = have - need
    print("%-18s %6d %6d %8.0f %8.0f %7.0f" % (name, len(foes) + len([f for f in extra if isinstance(f, tuple)]), health, need, have, spare))
    if spare < 0:
        short = True
    have = spare + sum(DROP_SHOTS.get(drops.get(f, "none"), 0) for f in foes)
print("\nneeds/has/spare in P9 body shots (26 dmg each), %d%% misses included." % ((MISS - 1) * 100))
sys.exit(1 if short else 0)
