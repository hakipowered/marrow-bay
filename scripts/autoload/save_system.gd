extends Node
## Save slots, RE style: the autosave plus MANUAL_SLOTS slots the players pick
## on the save screen (scripts/ui/save_slots.gd), from the pause menu or Load
## Game at the title. A save is the run (bags, world flags, looks, play time)
## with the place to come back at: the last checkpoint both survivors reached
## together.
##
## Files, all in user://saves:
##   slot1.json .. slot8.json   the manual slots
##   autosave.json              its own slot: written when both survivors reach
##                              a checkpoint together and every AUTOSAVE_INTERVAL
##   <slot>.jpg                 the slot's picture: the view when it was saved
## user:// is never touched by the in-game updater (it only swaps packs under
## user://content) or a new APK, and on the browser version it is the page's
## IndexedDB, which the shell asks the browser to keep (storage.persist). So
## saves outlive every update. Builds before save slots wrote only slot1.json
## and autosave.json (version 1: no chapter, place or picture); those still
## load and show up as Slot 1 and the Autosave.
##
## Co-op: the host owns the save. Either phone can press Save; the host writes
## the slot and sends the same save to the partner, so either of them can host
## that run later. The copy lands in the same slot number on the partner's
## phone unless that slot holds one of the partner's other games: then it goes
## into a free slot, never over a different run.

signal saved(slot: String)
signal loaded(slot: String)
## The slot list for the save screen (from the host when this phone joined).
signal slot_infos_received(infos: Array)

const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := "autosave"
const MANUAL_SLOTS := 8
const AUTOSAVE_INTERVAL := 240.0
const SNAPSHOT_VERSION := 2
const THUMB_SIZE := Vector2i(480, 270)

## Chapter titles by level. A level not listed shows its file name.
const CHAPTERS := {
	"res://scenes/levels/archive_hub.tscn": [1, "Shelter"],
	"res://scenes/levels/undercroft.tscn": [2, "The Count"],
}
## Where they come back, by checkpoint id (docs/lore.md, docs/chapter2.md).
const PLACES := {
	"start": "Ashgrove Street",
	"hall": "The Great Hall",
	"safe_office": "Archivist's Office",
	"ch2_lift": "Lift Pit",
	"ch2_lodge": "Keeper's Lodge",
	"ch2_hall": "Engine Hall",
}
const SAFE_ROOMS := ["safe_office", "ch2_lodge"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Where the files go. Tests point a second copy of the game elsewhere (two
## copies on one machine share user://).
var save_dir := SAVE_DIR
var _autosave_timer := 0.0
var autosave_enabled := true
## The run as it stood when the survivors last reached a checkpoint together
## (they reach the one they spawn at when a level loads). Continue after a
## game over goes back to this. Kept in memory for this run only.
var checkpoint_snapshot := {}
## A line for the "saved" toast when a co-op copy had to go into another slot.
var last_note := ""
## Set on the way into a new chapter's level: the first checkpoint there
## autosaves even though it's the one they were sent to.
var autosave_on_arrival := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)

func _process(delta: float) -> void:
	if not autosave_enabled or not _in_game() or _is_client():
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL and _can_autosave():
		_autosave_timer = 0.0
		save_game(AUTOSAVE_SLOT)

func _in_game() -> bool:
	return get_tree().get_first_node_in_group("level") != null

func _is_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()

## Not mid-cutscene or on the game over screen: the timer waits for that to end.
func _can_autosave() -> bool:
	var level := get_tree().get_first_node_in_group("level")
	if level == null or level.get("game_over"):
		return false
	return not Cutscenes.active

static func manual_slots() -> Array[String]:
	var out: Array[String] = []
	for i in MANUAL_SLOTS:
		out.append("slot%d" % (i + 1))
	return out

## What the save screen calls a slot.
static func slot_title(slot: String) -> String:
	if slot == AUTOSAVE_SLOT:
		return "Autosave"
	if slot.begins_with("slot"):
		return "Slot " + slot.trim_prefix("slot")
	return slot.capitalize()

# ---------------------------------------------------------------- saving

## Called by whoever presses Save. The host writes the file and mirrors it to
## the partner so both phones can resume the run.
func request_save(slot: String = "slot1") -> void:
	if _is_client():
		_rpc_request_save.rpc_id(1, slot)
	else:
		save_game(slot)

@rpc("any_peer", "reliable")
func _rpc_request_save(slot: String) -> void:
	if multiplayer.is_server() and _valid_slot(slot):
		save_game(slot)

func _valid_slot(slot: String) -> bool:
	return slot == AUTOSAVE_SLOT or slot in manual_slots()

## The autosave right now (both survivors just reached a checkpoint). Host or
## solo only; the partner gets the copy. quiet = no "Autosaved" toast (the
## checkpoint toast says it).
func autosave_now(quiet := true) -> void:
	autosave_on_arrival = false
	if _is_client() or not autosave_enabled:
		return
	_autosave_timer = 0.0
	save_game(AUTOSAVE_SLOT, quiet)

func build_snapshot() -> Dictionary:
	# What each survivor wears (outfit + body sliders), by character.
	var looks := {}
	var party: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		var who: String = GameState.character_by_peer.get(p.peer_id, p.character)
		GameState.inventories[who] = p.inventory.to_dict()
		looks[who] = GameState.customization_by_peer.get(p.peer_id, GameState.look(who)).duplicate()
		if not who in party:
			party.append(who)
	if party.is_empty():
		party = GameState.character_by_peer.values()
	if GameState.run_id == "":
		GameState.run_id = GameState.new_run_id()
	return {
		"looks": looks,
		"version": SNAPSHOT_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"unix": Time.get_unix_time_from_system(),
		"level": GameState.level_path,
		"checkpoint": GameState.shared_checkpoint,
		"flags": GameState.world_flags.duplicate(true),
		"inventories": GameState.inventories.duplicate(true),
		"play_time": GameState.play_time_sec,
		"mode": GameState.mode,
		"run_id": GameState.run_id,
		"party": party,
		"host_character": GameState.character_by_peer.get(1, party[0] if not party.is_empty() else "zegan"),
		"objective": GameState.world_flags.get("objective", ""),
		"game_version": PackMount.version_name,
	}

func mark_checkpoint() -> void:
	checkpoint_snapshot = build_snapshot()

func save_game(slot: String, quiet := false) -> void:
	var data := build_snapshot()
	last_note = ""
	_store(slot, data, quiet)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_mirror_save.rpc(slot, JSON.stringify(data), quiet)

## The host's save, copied onto this phone.
@rpc("authority", "reliable")
func _rpc_mirror_save(slot: String, json: String, quiet := false) -> void:
	var data = JSON.parse_string(json)
	if not data is Dictionary:
		return
	last_note = ""
	var target := mirror_target(slot, data)
	if target == "":
		last_note = "No free slot on this phone for a copy. Your partner has the save."
		if not quiet:
			saved.emit("")
		return
	if target != slot:
		last_note = "On this phone it went into %s: %s holds your other game." % [slot_title(target), slot_title(slot)]
	_store(target, data, quiet)

## Where a copy of the partner's save goes on this phone: the same slot when
## it's free or already holds this run; else the first free slot; else the
## oldest slot of this same run; else nowhere ("").
func mirror_target(slot: String, data: Dictionary) -> String:
	if slot == AUTOSAVE_SLOT or not slot in manual_slots():
		return slot
	var run: String = str(data.get("run_id", ""))
	var here := read_slot(slot)
	if here.is_empty() or (run != "" and str(here.get("run_id", "")) == run):
		return slot
	for s in manual_slots():
		if read_slot(s).is_empty() and not FileAccess.file_exists(_json_path(s)):
			return s
	var oldest := ""
	var oldest_key := INF
	for s in manual_slots():
		var d := read_slot(s)
		if run != "" and str(d.get("run_id", "")) == run and sort_key(d) < oldest_key:
			oldest_key = sort_key(d)
			oldest = s
	return oldest

## Writes the save, then its picture (a couple of frames later).
func _store(slot: String, data: Dictionary, quiet := false) -> void:
	# The old picture goes first, so a slot never shows a picture from an
	# older save next to the new one's details.
	DirAccess.remove_absolute(_thumb_path(slot))
	if not _write(slot, data):
		last_note = "Couldn't write the save on this phone."
	if not quiet:
		saved.emit(slot)
	_save_thumbnail(slot)

func _json_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]

func _thumb_path(slot: String) -> String:
	return "%s/%s.jpg" % [save_dir, slot]

## Written to a .tmp file and moved over the old one, so a phone that dies or
## a tab closed mid-write never leaves a half-written save.
func _write(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path := _json_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("save %s: can't write %s (%s)" % [slot, tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(tmp, path) != OK:
			push_warning("save %s: can't move %s into place" % [slot, tmp])
			return false
	return true

## The slot's picture: the scene from the active camera, drawn on its own at
## THUMB_SIZE (no HUD or menu over it). Skipped without a renderer (headless).
func _save_thumbnail(slot: String) -> void:
	var img := await capture_thumbnail()
	if img == null or img.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var tmp := _thumb_path(slot) + ".tmp.jpg"
	if img.save_jpg(tmp, 0.85) == OK:
		DirAccess.remove_absolute(_thumb_path(slot))
		DirAccess.rename_absolute(tmp, _thumb_path(slot))

func capture_thumbnail() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return null
	var vp := SubViewport.new()
	vp.size = THUMB_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.world_3d = cam.get_world_3d()
	vp.positional_shadow_atlas_size = 1024
	var c := Camera3D.new()
	c.projection = cam.projection
	c.fov = cam.fov
	c.size = cam.size
	c.near = cam.near
	c.far = cam.far
	c.cull_mask = cam.cull_mask
	c.environment = cam.environment
	c.attributes = cam.attributes
	c.keep_aspect = cam.keep_aspect
	c.h_offset = cam.h_offset
	c.v_offset = cam.v_offset
	vp.add_child(c)
	add_child(vp)
	c.global_transform = cam.global_transform
	c.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(vp):
		img = vp.get_texture().get_image()
		vp.queue_free()
	if img and not img.is_empty() and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img

# ---------------------------------------------------------------- reading

func read_slot(slot: String) -> Dictionary:
	var path := _json_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	# An instance parse: a damaged file is just "no save" here, without an
	# engine error every time the slot list is drawn.
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return j.data if j.data is Dictionary else {}

func has_slot(slot: String) -> bool:
	return not read_slot(slot).is_empty()

## Every .json in the save folder (test slots too).
func list_slots() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(save_dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out

## The order of saves in time: from the local date and time every save has
## carried since the first build (so old and new saves compare the same way).
static func sort_key(d: Dictionary) -> float:
	var ts: String = str(d.get("timestamp", ""))
	if ts == "":
		return 0.0
	return float(Time.get_unix_time_from_datetime_string(ts))

## The most recent save, the autosave included ("" when there's none).
func newest_slot(include_autosave := true) -> String:
	var best := ""
	var best_key := -1.0
	var slots := manual_slots()
	if include_autosave:
		slots.push_front(AUTOSAVE_SLOT)
	for s in slots:
		var d := read_slot(s)
		if d.is_empty():
			continue
		var k := sort_key(d)
		if k > best_key:
			best_key = k
			best = s
	return best

func has_any_save() -> bool:
	return newest_slot() != ""

## Everything the save screen shows for one slot.
func slot_info(slot: String) -> Dictionary:
	var d := read_slot(slot)
	var info := {"slot": slot, "title": slot_title(slot), "empty": d.is_empty()}
	if d.is_empty():
		info["damaged"] = FileAccess.file_exists(_json_path(slot))
		return info
	info.merge(describe(d))
	info["thumb"] = _thumb_path(slot) if FileAccess.file_exists(_thumb_path(slot)) else ""
	return info

## The autosave first, then the manual slots.
func all_slot_infos() -> Array:
	var out: Array = [slot_info(AUTOSAVE_SLOT)]
	for s in manual_slots():
		out.append(slot_info(s))
	return out

## The save screen's text for a save, old (version 1) saves included.
func describe(d: Dictionary) -> Dictionary:
	var cp: String = str(d.get("checkpoint", "start"))
	var flags: Dictionary = d.get("flags", {}) if d.get("flags", {}) is Dictionary else {}
	var party: Array = []
	var p: Variant = d.get("party", [])
	if p is Array and not p.is_empty():
		party = p
	elif d.get("looks", {}) is Dictionary:
		party = d.get("looks", {}).keys()
	# Zegan first, then Obcera, however the save listed them.
	var names := PackedStringArray()
	for who in GameState.CHARACTERS:
		if who in party:
			names.append(who.capitalize())
	for who in party:
		if not who in GameState.CHARACTERS:
			names.append(str(who).capitalize())
	var coop: bool = int(d.get("mode", 0)) == GameState.Mode.COOP or party.size() > 1
	var party_text := ""
	if not names.is_empty():
		party_text = ("Co-op: " if coop else "Solo: ") + " & ".join(names)
	return {
		"chapter": chapter_label(str(d.get("level", "")), flags),
		"place": PLACES.get(cp, cp.capitalize().replace("_", " ")),
		"safe_room": cp in SAFE_ROOMS,
		"play_time": float(d.get("play_time", 0.0)),
		"play_time_text": play_time_text(float(d.get("play_time", 0.0))),
		"when": when_text(str(d.get("timestamp", ""))),
		"key": sort_key(d),
		"party": party_text,
		"host_character": str(d.get("host_character", party[0] if not party.is_empty() else "")),
		"objective": str(d.get("objective", flags.get("objective", ""))),
		"run_id": str(d.get("run_id", "")),
	}

static func chapter_label(level: String, flags: Dictionary) -> String:
	var ch: Variant = CHAPTERS.get(level)
	if ch == null:
		return level.get_file().get_basename().capitalize()
	# Chapter 1's title card plays at the Archive gates: before that it's
	# still the prologue on Ashgrove Street.
	if ch[0] == 1 and not flags.get("story_gates", false):
		return "Prologue: Last Call"
	return "Chapter %d: %s" % [ch[0], ch[1]]

static func play_time_text(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]

static func when_text(ts: String) -> String:
	if ts == "":
		return ""
	var t := Time.get_datetime_dict_from_datetime_string(ts, false)
	var m: int = clamp(int(t.get("month", 1)), 1, 12)
	return "%d %s %d, %02d:%02d" % [t.get("day", 1), MONTHS[m - 1], t.get("year", 2026), t.get("hour", 0), t.get("minute", 0)]

## The slot list for the save screen. On the joining phone it comes from the
## host (the host's slots are the ones the save goes into); everywhere else
## it's this phone's own.
func request_slot_infos() -> void:
	if _is_client():
		_rpc_infos_request.rpc_id(1)
	else:
		slot_infos_received.emit.call_deferred(all_slot_infos())

@rpc("any_peer", "reliable")
func _rpc_infos_request() -> void:
	if multiplayer.is_server():
		_rpc_infos_reply.rpc_id(multiplayer.get_remote_sender_id(), all_slot_infos())

@rpc("authority", "reliable")
func _rpc_infos_reply(infos: Array) -> void:
	slot_infos_received.emit(infos)

## This phone's picture for a slot the host described: only when this phone's
## copy is that same save.
func local_thumb_for(info: Dictionary) -> String:
	var slot: String = str(info.get("slot", ""))
	if info.get("empty", true) or not FileAccess.file_exists(_thumb_path(slot)):
		return ""
	var here := read_slot(slot)
	if here.is_empty() or sort_key(here) != float(info.get("key", -1.0)):
		return ""
	return _thumb_path(slot)

# ---------------------------------------------------------------- loading

## Applies a snapshot to GameState; the level reads it when it spawns players.
func apply_snapshot(data: Dictionary) -> void:
	GameState.level_path = data.get("level", GameState.level_path)
	GameState.shared_checkpoint = data.get("checkpoint", "start")
	GameState.world_flags = data.get("flags", {})
	GameState.inventories = data.get("inventories", {})
	GameState.play_time_sec = data.get("play_time", 0.0)
	autosave_on_arrival = false
	# Older saves have no run id: this run gets a new one from here on.
	GameState.run_id = str(data.get("run_id", ""))
	if GameState.run_id == "":
		GameState.run_id = GameState.new_run_id()
	_autosave_timer = 0.0
	# Survivors come back dressed as they were saved.
	var looks: Variant = data.get("looks", {})
	if looks is Dictionary:
		for who in looks:
			if who in GameState.CHARACTERS and looks[who] is Dictionary:
				GameState.set_look(who, looks[who])
	loaded.emit(data.get("checkpoint", ""))
