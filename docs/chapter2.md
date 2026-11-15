# Chapter 2: The Count (the Undercroft)

The second chapter, playable from where the vault elevator stops at the end of
chapter 1. Original setting and story; the world bible is `docs/lore.md`.

- Level: `scenes/levels/undercroft.tscn`, built in code by
  `scripts/levels/undercroft.gd` (class `Undercroft`).
- Story and cutscenes: `scripts/story/chapter2_story.gd` (class `Chapter2Story`).
- Boss: `scripts/enemies/warden_boss.gd` (class `WardenBoss`).
- Puzzles: `scripts/world/generator_set.gd`, `master_clock.gd`, `pump_room.gd`,
  `flood_door.gd`, lights on the generator in `undercroft_power.gd`, shared
  builders in `undercroft_kit.gd`.
- Cheat menu: "Go to chapter 2: the Undercroft" jumps both players there
  (`Cheats.jump_to_chapter`).

## The place

The Undercroft is the Archive's old service level, two floors under the records
vault: brick tunnels from 1902, the night keeper's lodge, the survey office
with the 1891 river map, the clock gallery whose master clock once drove every
clock in the building, the shelter staff's muster room, the river pump room
with its flooded sump, the engine hall with a dead diesel generator and the
flood door, and a sunken coal yard open to the rain. The power is out; red emergency lamps and whatever the survivors carry
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
| Pump room | (33, 4.5) | 6 x 7.5 | Sump B, flooded: three valves, the drill board, the starting handle at the bottom. |
| Engine hall | (39, -6) | 16 x 18 | The generator and the flood door. Checkpoint `ch2_hall`. |
| Coal yard | (55, -6) | 22 x 18 | Outdoors in the rain: coal heaps, a burning ambulance wreck, the fuel shed with the diesel. |
| Deep stacks | (43, 12) | 8 x 8 | Behind the flood door. Nasri's staff card and his chalk. The end. |

## The flow

1. **Arrival** (`c2_arrival`): the car's battery lamp, the doors grind open on
   the service level. Objective: find a way out.
2. **Engine hall** (`c2_hall`, walking in): the flood door is the way on, dead
   on its motor. The generator that runs it is dry, has no fuse in its cabinet
   and no starting handle. The control cabinet (a 1950s steel panel: volts,
   amps and frequency meters, lamps for fuel, field, handle and running, the
   fuse carrier, the main breaker) shows what is missing, and the keeper's
   note left in the bottom of it says where each part went. The objective lists
   every part still missing with where it is, and updates as each goes in.
3. **The fuse**: the brass winding key is in the survey room. Wind the master
   clock in the gallery; every dial in the tunnels jolts forward to 11:44, the
   clock strikes and the drawer in its plinth opens on the fuse.
4. **The hunt** (`c2_hunt`, taking the fuse): the chime carries. The Tallyman
   comes down the back stair and hunts them through the tunnels. He cannot be
   killed (enough damage drops him to one knee). He follows them through an
   open door. A shut door keeps him out: he waits outside it, then gives up
   and walks back the way he came, and comes again when someone is out where
   he can reach them. Safe rooms stop
   him. Once all three parts are in, he gives up for good (he turns and walks
   off if they can see him, or is simply gone).
5. **The diesel**: the jerrycan is in the coal yard's fuel shed.
6. **The starting handle** (the pump room, off the tunnel beside the engine
   hall): the keeper threw it into Sump B and opened the river inlet over it.
   The drill card by the door and the board on the wall give the 1974 drill:
   shut the river inlet (V1), shut the sewer bypass on a high river (V3), then
   open the sump suction (V2). Every other setting fills it, holds it or backs
   the sewer up into it, and the water, the level gauge, the sounds and the
   survivors say which. Turning a wheel puts the gun away for a moment. Once
   it's dry the chained gate unhooks and the steps go down. The man who went
   in after the handle lies face down by the drain and gets up as they come
   down.
7. **Cranking**: diesel, fuse and handle in (any order), crank. One survivor
   heaves while the other holds off the infected the noise brings in at 15,
   40, 65 and 85 percent (from the yard, the coal chute and the corridor,
   never in view). Let go and the flywheel slows, but never below the last
   wave they held off.
8. **Power**: the engine catches, the lights come on room by room, the klaxon
   sounds. The flood door's control box lights LOCKED OUT: the door won't
   lift without the Warden's key.
9. **The intercom** (`c2_intercom`, the lights on and it quiet): Hardass on the
   tannoy. He heard the engine; the key is on his belt; he is in the muster
   room and has unbarred the door.
10. **The Warden** (`c2_warden`, walking into the muster room): Hardass counts
    the shelter one last time and turns in front of them. The door bars
    behind them.
11. **The key** drops where the Warden falls; the muster door unbars. Turn it
    in the flood door's control box and the door rises.
12. **The end** (`c2_end`, in the deep stacks): Nasri's staff card on the floor,
    "THE COUNT IS WRONG" chalked on the wall with tally marks, the Tallyman
    counting somewhere far off. *End of chapter 2.*

A save from update 0.13 made after the tannoy scene but before the power
(`story_c2_intercom` set, the generator not running) keeps the old order: the
Warden drops the handle and the flood door rises on the power alone
(`c2_old_flow`).

All scenes are in-engine with the real character models, moving cameras and
voiced lines (`assets/audio/voice/story/`). Skipping is always safe:
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
  Diesel (`diesel_can`), Starting Handle (`crank_handle`), Warden's Flood Door
  Key (`flood_key`). Their models are Meshy scans in `assets/props/`.
- Files: Orrin Vell's night ledger (`keeper_ledger`, in the lodge), the Survey
  Office Memo, 1891 (`survey_note`), the keeper's note in the generator
  cabinet (`gen_note`) and the Sump B drill card, 1974 (`pump_drill`).
- Ammo and herbs are placed so a player who leaves chapter 1 with the usual
  leftovers has more than the chapter needs (see `tools/balance_report.py`).

## Story flags

Saved in `GameState.world_flags`:

- Scenes: `story_c2_arrival`, `story_c2_hall`, `story_c2_hunt`,
  `story_c2_intercom`, `story_c2_warden`, `story_c2_end`.
- World state: `c2_arrival`, `c2_clock_open` (the clock drawer), `taken:c2_fuse`,
  `c2_hunt` and `c2_hunt_over` (the Tallyman), `c2_valve_0` to `c2_valve_2`
  (the pump room's valves, set when open), `c2_sump_drained`, `c2_sump_gate`,
  `unlocked:muster_door`, `c2_warden_dead`, `c2_flood_key_in` (the Warden's
  key in the flood door's box), `c2_flood_open`, `power:undercroft`,
  `c2_old_flow` (a 0.13 save past the tannoy).

A game loaded part way through puts everything back: the lift doors open, the
valves as they were (a part-drained sump comes back full), the Warden in his
room, the key where he dropped it, the objective on the banner.

## Tests (all in the playtest gate, `tools/playtest.sh`)

- `tests/chapter2_flow.gd`: the whole chapter by its rules, start to end
  (including the valves in the wrong order first, and reloads part way).
- `tests/stalker_doors.gd`: the hunting Tallyman comes out of the clock
  gallery, waits outside the pump room door, gives up, and comes back when
  she is out in the tunnel.
- `tests/warden_fight.gd`: the boss fight with real pistol shots at his hit
  zones.
- `tests/playtest.gd -- only route2`: the bot plays chapter 2 like a player
  (walking, fighting, picking up, solving, cranking), straight on from the
  elevator ride when it runs after chapter 1.
- `tests/playtest.gd -- only probe2`: walks every room looking for spots where
  she gets stuck.
- `tests/playtest.gd -- only warden2`: the bot fights the Warden its own way
  (`WARDEN_DEBUG=1` prints its aim and line of fire every second).
- `tools/content/check_excludes.py`: every prop model the game uses goes into
  the content packs.
- `tests/wall_overlap.gd -- res://scenes/levels/undercroft.tscn`: no two walls
  in one plane.
- `tests/undercroft_shots.gd`: screenshots of every room (`torch`, `lit` and
  `power:undercroft` flags) for a look at the art.

## Notes for later chapters

- Doors are baked shut into the navmesh; each door's link joins the two
  sides while it stands open (`Door.NAV_REACH`). The Tallyman checks whether
  the navmesh reaches whoever he hunts and gives up on someone behind a shut
  door (`Stalker._can_reach`). The playtest bot uses `cross()` for every
  doorway with a door.
- The Tallyman's model is 2.45 m tall but his body is 2.2 m, so he fits under
  2.3 m door heads; he stoops (the model scales down a touch) where the
  ceiling is low.
- The "Android Content" export preset leaves out Poly Haven models nothing
  used, by hand (`exclude_filter` in `export_presets.cfg`). A level that
  starts using one of them has to take it off that list, or the phone build
  has an empty node where the prop should be. Chapter 2 took 16 off it.
- The coal yard's moonlight is on its own render layer (`YARD_LAYER`) so it
  doesn't leak into the tunnels.
- Chapter 3 ("Paper Trail") picks up in the deep stacks.
