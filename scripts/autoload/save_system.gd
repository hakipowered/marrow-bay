extends Node
## Manual save = last checkpoint both players reached together.
## Autosave runs on the host every AUTOSAVE_INTERVAL seconds into its own slot.

signal saved(slot: String)
signal loaded(slot: String)

const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := "autosave"
const AUTOSAVE_INTERVAL := 240.0

var _autosave_timer := 0.0
var autosave_enabled := true

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _process(delta: float) -> void:
	if not autosave_enabled or not _in_game():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game(AUTOSAVE_SLOT)

func _in_game() -> bool:
	return get_tree().get_first_node_in_group("level") != null

## Called by whoever presses Save. The host writes the file and
## mirrors it to the partner so both phones can resume the run.
func request_save(slot: String = "slot1") -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		save_game(slot)
	else:
		_rpc_request_save.rpc_id(1, slot)

@rpc("any_peer", "reliable")
func _rpc_request_save(slot: String) -> void:
	if multiplayer.is_server():
		save_game(slot)

func build_snapshot() -> Dictionary:
	# What each survivor wears (outfit + body sliders), by character.
	var looks := {}
	for p in get_tree().get_nodes_in_group("players"):
		var who: String = GameState.character_by_peer.get(p.peer_id, p.character)
		GameState.inventories[who] = p.inventory.to_dict()
		looks[who] = GameState.customization_by_peer.get(p.peer_id, GameState.look(who)).duplicate()
	return {
		"looks": looks,
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"level": GameState.level_path,
		"checkpoint": GameState.shared_checkpoint,
		"flags": GameState.world_flags.duplicate(true),
		"inventories": GameState.inventories.duplicate(true),
		"play_time": GameState.play_time_sec,
		"mode": GameState.mode,
	}

func save_game(slot: String) -> void:
	var data := build_snapshot()
	_write(slot, data)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_mirror_save.rpc(slot, JSON.stringify(data))
	saved.emit(slot)

@rpc("authority", "reliable")
func _rpc_mirror_save(slot: String, json: String) -> void:
	var data = JSON.parse_string(json)
	if data is Dictionary:
		_write(slot, data)
		saved.emit(slot)

func _write(slot: String, data: Dictionary) -> void:
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, slot], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func read_slot(slot: String) -> Dictionary:
	var path := "%s/%s.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func list_slots() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(SAVE_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out

## Applies a snapshot to GameState; the level reads it when it spawns players.
func apply_snapshot(data: Dictionary) -> void:
	GameState.level_path = data.get("level", GameState.level_path)
	GameState.shared_checkpoint = data.get("checkpoint", "start")
	GameState.world_flags = data.get("flags", {})
	GameState.inventories = data.get("inventories", {})
	GameState.play_time_sec = data.get("play_time", 0.0)
	# Survivors come back dressed as they were saved.
	var looks: Variant = data.get("looks", {})
	if looks is Dictionary:
		for who in looks:
			if who in GameState.CHARACTERS and looks[who] is Dictionary:
				GameState.set_look(who, looks[who])
	loaded.emit(data.get("checkpoint", ""))
