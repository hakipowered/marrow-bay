# In-game updater: thin app + content packs

The Android app (and the browser version) is a **thin base**: the Godot engine,
`project.godot`, the audio bus layout and the `boot/` folder (the update
screen). Everything else (scripts, scenes, models, sounds, films) ships as
**content packs** that the app downloads on first start and keeps up to date
by itself. A new build of the game normally means uploading a few changed
packs, not a new APK.

```
APK (about 28 MB)                     download server (download/worker.js)
  boot/pack_mount.gd   PackMount  ──── GET /packs/manifest.json
  boot/boot.tscn       update screen   GET /packs/<name>-<sha12>.pck
  boot/content_updater.gd
                       │
user://content/installed.json        the set that's installed
user://content/packs/*.pck           the packs themselves
```

## How a phone updates

1. `PackMount` is the **first autoload**. In `_init()` it reads
   `user://content/installed.json` and mounts every pack in it
   (`ProjectSettings.load_resource_pack`). Godot loads autoloads one at a time,
   so GameState, Net, Music... then load from the packs.
2. The main scene is `boot/boot.tscn`. It fetches the manifest, works out which
   packs are missing (packs are named after their SHA-256, so an unchanged pack
   is never downloaded twice), downloads them with a progress bar, checks each
   SHA-256, writes the new `installed.json`, deletes packs the new set doesn't
   use, and restarts the app (`OS.create_instance` on Android) so every script
   loads from the new packs. When nothing changed it goes straight to the
   title screen. Offline, it plays what's installed.
3. Updates over 150 MB ask first when there's an older version to play.

Run from the project folder (editor, tests, playtest bot), the game is already
in `res://`: PackMount mounts nothing and the boot screen goes straight to the
title screen. Nothing changes for development.

## The base id: when players need a new APK

Content only mounts on the app it was made for. The **base id** is a hash of
the Godot version, `project.godot` and `default_bus_layout.tres` (the things
Godot reads from the APK at startup). `tools/build_android.sh` stamps it into
`boot/build_info.json`; the manifest carries the base id the content needs.

So a new APK is needed only when one of these changed:
- `project.godot` (autoloads, input map, physics layers, settings, main scene)
- `default_bus_layout.tres`
- anything in `boot/` (the updater itself)
- the Godot version

If the base changed, players see "Update X needs the new app" with a button to
the download page, and can keep playing the version they have meanwhile. After
they install the new APK, packs already on the phone are reused.

## Co-op

Both phones must run the same content build. When a friend joins, their game
sends its build id (`scripts/net/version_check.gd`); a host on another build
turns them away and both players are told who needs to close and reopen the
game to update. Don't change the RPCs in that file: older and newer versions
must be able to call them.

## Releasing a build

```sh
python3 tools/fetch_assets.py && godot --headless --path . --import    # as before
tools/playtest.sh                                                     # the gate, as before
tools/build_content.sh 0.12             # packs + manifest in build/content/
tests/updater_e2e.sh                    # optional: the updater end to end, ~2 min

python3 tools/content/packs.py upload build/content
```

`upload` sends only packs the server doesn't have, then reads back every pack
players don't already get (the new ones, and any an earlier run sent but
stopped before checking) and checks its SHA-256. KV can serve a value that was
just written stale for a minute, so a mismatch is read again after 15, 45 and
90 s, and a pack that still doesn't match is uploaded once more. Only then does
it switch the manifest (players never see a half-uploaded set), and then it
deletes packs nothing uses any more. If it stops, run it again: it picks up
where it left off and checks what the stopped run sent.

Before sending anything, `upload` deletes packs that neither the live set nor
the new one uses (left by a stopped run) and checks the room on the server:
the packs there, the APK, the browser version and the new packs together must
stay under 1 GB, the free Workers KV storage. Old packs are only deleted once
the new set is live, so for a moment both sets are stored. If it says there
isn't enough room, nothing was uploaded. `--kv-limit 0` turns the check off
(for a paid KV plan). It signs with `UPLOAD_TOKEN` if set,
otherwise with the content upload key
(`/mnt/project-files/.signing/content_upload_ed25519.pem`).

If `upload` says the live content is for another app base, the base changed:
bump `version/code` and `version/name` in `export_presets.cfg`, then

```sh
tools/build_android.sh                       # thin APK, about 28 MB
UPLOAD_TOKEN=... tools/upload_build.sh 0.12  # APK first...
python3 tools/content/packs.py upload build/content --new-base   # ...then content
```

APK first, so players who are told to get the new app find it there.
`python3 tools/content/packs.py live` prints what the server offers now.

## Packs

`tools/build_content.sh` exports the **Android Content** preset (everything
except `boot/` and the root files; textures in ETC2/ASTC, which the browser
version uses too) as one pack, and `packs.py split` cuts it up:

- **core**: all scripts, scenes, shaders and the small index files
  (`.import`/`.remap`, UID and class caches). Changes almost every build; about
  1 MB.
- the rest by folder: a folder up to 24 MB is one pack, bigger folders split
  into their subfolders, small subfolders share a pack. Each infected type,
  outfit and character is its own pack, so a changed model downloads only
  that model's pack.
- `assets/story/video/` packs are stage `later`: the browser version may fetch
  them while the player is on the menu. The phone downloads everything up
  front.

**Players keep their packs.** `split` first reads which pack every file is in
on the download server (`--like live`, the default; it reads only the start
of each pack). A file that was in a pack stays in it, so a pack only changes
when one of its own files changes. Files that are new go into new packs, named
after their folder. It prints what players on the live build will download.
Without this, one new model in the middle of a folder would shift every pack
after it.

Godot doesn't import some models byte for byte the same on two machines, so a
build made in a fresh container would otherwise look like every model
changed. Each pack in the manifest carries `inputs`, a hash of the files it is
made from (source, import settings without the uid, a glTF's buffers and
images) plus the engine and the content export preset. When a rebuilt pack
differs from the live one but its `inputs` match, `split` keeps the live pack
(and downloads it into `build/content/packs/`).

Over many releases new files make many small packs. To start over with a
clean layout, `RAGOON_CONTENT_LIKE=none tools/build_content.sh <version>`
(players then download everything once). `RAGOON_CONTENT_LIKE=<dir>` keeps
the layout of another local build instead of the live one.

Manifest (`build/content/manifest.json`, served at `/packs/manifest.json`):

```json
{"format": 1, "version": "0.12", "build": "0.12-1a2b3c4d", "engine": "4.4.1.stable",
 "base": "fbd7a035327d", "app": {"version": "0.12", "code": 12},
 "packs": [{"name": "core", "file": "core-237d72f9ffdd.pck", "sha256": "…",
            "size": 912345, "stage": "boot", "files": 1119},
           {"name": "ui", "file": "ui-8686b8eab5de.pck", "sha256": "…",
            "size": 12477210, "stage": "boot", "files": 61, "inputs": "…"}]}
```

`build` is the version plus a hash of all the packs: two phones with the same
`build` have exactly the same game.

## Server

`download/worker.js` stores each pack as 20 MiB KV values `pack:<file>:<i>`
plus `packmeta:<file>` ({size, chunks, chunk, sha256}); the manifest is
`packs:manifest`. Packs are served with `Cache-Control: immutable` and Range
support; the manifest with `no-store`.

## Testing

- `tests/updater_e2e.sh`: exports the base as a pack, serves `build/content`
  locally and runs the base headless through first install, relaunch, the first
  level from packs, offline, new app needed, server behind, a one-pack update,
  a damaged download and content for another app.
- `tests/coop_version.gd`: two copies through the local relay; same build gets
  in, an older one is turned away with the right message (in `tools/playtest.sh`).
- `python3 tools/content/packs.py serve build/content` serves packs like the
  worker; point a build at it with `RAGOON_CONTENT_URL=http://127.0.0.1:8790/packs/`
  (or `[content] url=` in `user://settings.cfg`).
- Run a `--main-pack` test from outside the project folder, or Godot reads the
  source files and it looks like a full build.
