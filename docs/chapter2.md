# Chapter 2: The Count (the Undercroft)

The second chapter, playable from where the vault elevator stops at the end of
chapter 1. Original setting and story; the world bible is `docs/lore.md`.

- Level: `scenes/levels/undercroft.tscn`, built in code by
  `scripts/levels/undercroft.gd` (class `Undercroft`).
- Story and cutscenes: `scripts/story/chapter2_story.gd` (class `Chapter2Story`).
- Boss: `scripts/enemies/warden_boss.gd` (class `WardenBoss`).
- Puzzles: `scripts/world/generator_set.gd`, `master_clock.gd`, `flood_door.gd`,
  lights on the generator in `undercroft_power.gd`, shared builders in
  `undercroft_kit.gd`.
- Cheat menu: "Go to chapter 2: the Undercroft" jumps both players there
  (`Cheats.jump_to_chapter`).

## The place

The Undercroft is the Archive's old service level, two floors under the records
vault: brick tunnels from 1902, the night keeper's lodge, the survey office
with the 1891 river map, the clock gallery whose master clock once drove every
clock in the building, the shelter staff's muster room, the engine hall with a
dead diesel generator and the flood door, and a sunken coal yard open to the
rain. The power is out; red emergency lamps and whatever the survivors carry
are the only light until the generator runs.

| Room | Floor corner (x, z) | Size | What happens there |
|---|---|---|---|
| Lift pit | (0, 0) | 7 x 6 | The lift arrives in its west wall. Checkpoint `ch2_lift`. |
| Service corridor | (7, 1.5) | 32 x 3 | The spine, west to east. A ceiling drop scare past the muster door. |
| Keeper's lodge | (8, 4.5) | 7 x 6 | Safe room (`ch2_lodge`): typewriter, box, Orrin Vell's night ledger. |
| Survey room | (9, -9.5) | 12 x 11 | The 1891 river map, the brass winding key, the survey memo. |
| Clock gallery | (21, -9.5) | 14 x 11 | The master clock and its wall of slave dials. The fuse. |
| Back stair | (31.5, -12.5) | 3 x 3 | Caved in. The Tallyman comes down it. |
| Muster room | (19, 4.5) | 14 x 10 | Barred from inside. The Warden's arena. |
| Engine hall | (39, -6) | 16 x 18 | The generator and the flood door. Checkpoint `ch2_hall`. |
| Coal yard | (55, -6) | 22 x 18 | Outdoors in the rain: coal heaps, a burning ambulance wreck, the fuel shed with the diesel. |
| Deep stacks | (43, 12) | 8 x 8 | Behind the flood door. Nasri's staff card and his chalk. The end. |

## The flow

1. **Arrival** (`c2_arrival`): the car's battery lamp, the doors grind open on
   the service level. Objective: find a way out.
2. **Engine hall** (`c2_hall`, walking in): the flood door is the way on, dead
   on its motor. The generator that runs it is dry, has no fuse in its cabinet
   and no starting handle. The cabinet's three lamps show what is missing and
   the objective lists it.
3. **The fuse**: the brass winding key is in the survey room. Wind the master
   clock in the gallery; every dial in the tunnels jolts forward to 11:44, the
   clock strikes and the drawer in its plinth opens on the fuse.
4. **The hunt** (`c2_hunt`, taking the fuse): the chime carries. The Tallyman
   comes down the back stair and hunts them through the tunnels (he cannot be
   killed; safe rooms and locked doors stop him).
5. **The diesel**: the jerrycan is in the coal yard's fuel shed. Pour it in and
   fit the fuse (in either order).
6. **The intercom** (`c2_intercom`, diesel and fuse in): Hardass on the tannoy.
   The handle is on his belt, he is in the muster room, he has unbarred the
   door.
7. **The Warden** (`c2_warden`, walking into the muster room): Hardass counts
   the shelter one last time and turns in front of them. The door bars behind
   them; the Tallyman's hunt ends here.
8. **The handle** drops where the Warden falls; the muster door unbars.
9. **Cranking**: fit the handle and crank. One survivor heaves while the other
   holds off the infected the noise brings in at 15, 40, 65 and 85 percent
   (from the yard, the coal chute and the corridor, never in view). Let go and
   the flywheel slows, but never below the last wave they held off.
10. **Power**: the engine catches, the lights come on room by room, the klaxon
    sounds and the flood door rises.
11. **The end** (`c2_end`, in the deep stacks): Nasri's staff card on the floor,
    "THE COUNT IS WRONG" chalked on the wall with tally marks, the Tallyman
    counting somewhere far off. *End of chapter 2.*

All scenes are in-engine with the real character models, moving cameras and
voiced lines (`assets/audio/voice/story/`, 32 lines). Skipping is always safe:
the world changes in `on_cutscene_end()`. Scenes wait while anyone is downed,
pinned, working or has chasing infected in sight; only the intercom and the
Warden scene go ahead with the Tallyman close behind (he freezes for the scene
like everything else).

## The Warden (boss 1, "The Last Warden")

Warden Jackson Hardass, bitten in the Archive, turned on the way down, still in
his shelter riot gear: a scanned and rigged model with his own clips (idle,
walks, swing, slash, combos, shield shove, charge, slam, ground slam, stomp,
kneel, roar, deaths).

- **1500 HP.** Hit zones: head x2, torso x1, arms x0.6, legs x0.8, the growth
  on his back x3.
- **Phase one:** the riot shield (260 HP) stops everything from the front but
  the legs. Truncheon swing, slash, a three-hit combo, a shield shove, and a
  charge that leaves him dazed if it ends in a wall.
- **The growth:** his bite has swollen into a glowing growth on his back. 170
  damage there drops him to his knees, holding his head, for a few seconds;
  on his knees the shield doesn't cover him and every hit does half again.
  In co-op one survivor draws him while the other gets behind him.
- **Phase two (half health):** he roars, tears the shield off and runs:
  faster combos, an overhead slam, a ground slam that knocks both survivors
  back, a stomp.
- Duck-types the infected (group `zombies`, plus `boss`): every weapon, blast
  and fire hurts him, and the boss music plays.

## Items and files

- Key items: Brass Winding Key (`clock_key`), Field Fuse (`fuse`), Jerrycan of
  Diesel (`diesel_can`), Starting Handle (`crank_handle`). Their models are
  Meshy scans in `assets/props/`.
- Files: Orrin Vell's night ledger (`keeper_ledger`, in the lodge) and the
  Survey Office Memo, 1891 (`survey_note`).
- Ammo and herbs are placed so a player who leaves chapter 1 with the usual
  leftovers has more than the chapter needs (see `tools/balance_report.py`).

## Story flags

Saved in `GameState.world_flags`:

- Scenes: `story_c2_arrival`, `story_c2_hall`, `story_c2_hunt`,
  `story_c2_intercom`, `story_c2_warden`, `story_c2_end`.
- World state: `c2_arrival`, `c2_clock_open` (the clock drawer), `taken:c2_fuse`,
  `c2_hunt` and `c2_hunt_over` (the Tallyman), `unlocked:muster_door`,
  `c2_warden_dead`, `c2_flood_open`, `power:undercroft`.

A game loaded part way through puts everything back: the lift doors open, the
Warden in his room, the handle where he dropped it, the objective on the
banner.

## Tests (all in the playtest gate, `tools/playtest.sh`)

- `tests/chapter2_flow.gd`: the whole chapter by its rules, start to end.
- `tests/warden_fight.gd`: the boss fight with real pistol shots at his hit
  zones.
- `tests/playtest.gd -- only route2`: the bot plays chapter 2 like a player
  (walking, fighting, picking up, solving, cranking), straight on from the
  elevator ride when it runs after chapter 1.
- `tests/playtest.gd -- only probe2`: walks every room looking for spots where
  she gets stuck.
- `tests/wall_overlap.gd -- res://scenes/levels/undercroft.tscn`: no two walls
  in one plane.
- `tests/undercroft_shots.gd`: screenshots of every room (`torch`, `lit` and
  `power:undercroft` flags) for a look at the art.

## Notes for later chapters

- Doors are walls to the navmesh (it is baked with them shut), so infected
  don't path through them; the Tallyman opens ordinary doors when he reaches
  them. The playtest bot uses `cross()` for every doorway with a door.
- The coal yard's moonlight is on its own render layer (`YARD_LAYER`) so it
  doesn't leak into the tunnels.
- Chapter 3 ("Paper Trail") picks up in the deep stacks.
