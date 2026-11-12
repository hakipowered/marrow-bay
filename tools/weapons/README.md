# Weapons, melee clips, item icons and weapon sounds

Everything here was made on 2026-11-12 for the weapon and inventory update.
The original job ids and source image URLs are in the project files
(`weapons/model_jobs.txt`, `weapons/icon_sources.txt`, `weapons/sfx_jobs.txt`).

## Weapon models: `assets/weapons/<id>/<id>.glb`

Concept art for each weapon (original designs) was painted with
`generate_image`, then turned into a textured model with Meshy image-to-3D on
fal. `pack_weapons.py` repacks the downloaded GLBs smaller for phones
(albedo 1024 JPG, normal and ORM 512, single-sided materials):

    python3 tools/weapons/pack_weapons.py build_tmp/weapons assets/weapons
    python3 tools/fix_imports.py && godot --headless --import

Meshy models come out about 1.9 units long with the muzzle or blade tip at
-X. `scripts/player/held_weapon.gd` (`MODELS`) scales each to its real length
and records where the hand closes on it. The Warden P9, Longshot rifle, Fire
Hatchet and Frag grenade use CC0 Poly Haven models instead (fetched by
`tools/fetch_assets.py`).

## Melee and throw clips: `assets/characters/<id>/<id>_combat.res`

Meshy rigs of the two survivors with these animation presets: 219 (knife
slash), 240 (stab), 97 (backhand slash), 237 (axe chop), 421 (over-shoulder
throw), 89 (combat stance). Download the six clip GLBs to
`build_tmp/melee/<id>/a0..a5.glb`, then:

    godot --headless --path . --script tools/weapons/import_combat_clips.gd -- zegan obcera

The importer trims each clip to its useful part (see `TRIM`) and keeps the
rig's bone rest with the library. At run time `CombatClips` retargets the
clips onto whichever skeleton plays them, so they fit both survivors and every
outfit model.

## Item icons: `assets/ui/items/*.jpg`

512 px renders made with `generate_image`, one per weapon, ammo type, supply,
key and file. `ItemInfo.icon()` maps item ids to these files (`ammo:9mm` is
`ammo_9mm.jpg`; key items without their own icon use `key.jpg`).

## Sounds: `assets/audio/sfx/`

ElevenLabs sound effects on fal (`start_audio` kind `sfx`): gunshots per
weapon, knife and hatchet swings, melee hits, reloads, dry fire, equip, the
bag's open, close, select and combine sounds, pickups, healing, explosions
and the flashbang. Converted to mono Ogg Vorbis and peak-normalised to -1 dB:

    ffmpeg -i in.mp3 -af "volume=<gain>dB,aresample=44100" -ac 1 -c:a libvorbis -q:a 5 out.ogg

Numbered files (`weapon_knife_1.ogg`, `weapon_knife_2.ogg`) are variations
that `Sfx` picks between at random.

Nineteen of the first batch's files held only their first hundredth of a
second (every gun but the pistol, SMG and grenade launcher, the explosion,
flashbang, flamethrower, reloads, dry fire, equip and the bag's clicks). They
were rebuilt from the same takes and levelled against the pistol: the loudest
100 ms sits near -2 dBFS RMS for guns and explosions, -6 for the flamethrower,
-10 to -15 for clicks and reloads. Gun blasts are pushed through a soft
(tanh) clip, only over the opening blast, so the room tail stays below it.
The pump shotgun is its take's blast and room tail with the pump rack pulled
forward to 0.65 s, before the next shot. `python3 tools/sfx/check_sfx.py`
fails on any sound that is silent or cut to a click.
