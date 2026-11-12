extends Node
## Shared run state: who plays whom, customization, and the shared checkpoint.

signal shared_checkpoint_changed(checkpoint_id: String)

enum Mode { SOLO, COOP }
const CHARACTERS := ["zegan", "obcera"]

var mode: Mode = Mode.SOLO
## peer_id -> character id ("zegan" / "obcera")
var character_by_peer: Dictionary = {}
## peer_id -> customization Dictionary (see default_customization)
var customization_by_peer: Dictionary = {}
## Last checkpoint that every player in the session was standing at together.
var shared_checkpoint: String = "start"
var level_path: String = "res://scenes/levels/archive_hub.tscn"
## Persistent world flags (opened doors, picked items, solved puzzles).
var world_flags: Dictionary = {}
## peer_id -> inventory snapshot, filled from the players on save.
var inventories: Dictionary = {}
var play_time_sec: float = 0.0
## This phone's own look per character (outfit + body sliders), kept between
## sessions in LOOKS_PATH. The character select edits these; co-op sends
## them to the host, and saves carry the look each survivor had.
var looks: Dictionary = {}
const LOOKS_PATH := "user://looks.json"

func _ready() -> void:
	if FileAccess.file_exists(LOOKS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
		if d is Dictionary:
			looks = d

func _process(delta: float) -> void:
	play_time_sec += delta

## The saved look for a character, filled out with defaults.
func look(character: String) -> Dictionary:
	var c := default_customization(character)
	var saved: Variant = looks.get(character, {})
	if saved is Dictionary:
		for k in saved:
			if c.has(k):
				c[k] = saved[k]
	c["outfit"] = Outfits.resolve(character, c.get("outfit", Outfits.DEFAULT))
	return c

func set_look(character: String, c: Dictionary) -> void:
	looks[character] = c.duplicate()
	var f := FileAccess.open(LOOKS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(looks, "\t"))

static func default_customization(character: String) -> Dictionary:
	return {
		"outfit": "default",
		# Body-shape sliders, 0..1, 0.5 = base model.
		"height": 0.5, "shoulders": 0.5, "chest": 0.5,
		"waist": 0.5, "hips": 0.5, "legs": 0.5, "muscle": 0.5,
		"hair": "default", "hair_color": Color(0.1, 0.07, 0.05).to_html(),
	}

func local_character() -> String:
	return character_by_peer.get(multiplayer.get_unique_id(), "zegan")

func partner_character(of_character: String) -> String:
	return "obcera" if of_character == "zegan" else "zegan"

func set_flag(key: String, value: Variant = true) -> void:
	world_flags[key] = value

func has_flag(key: String) -> bool:
	return world_flags.get(key, false) != false

func set_shared_checkpoint(id: String) -> void:
	if shared_checkpoint == id:
		return
	shared_checkpoint = id
	shared_checkpoint_changed.emit(id)

func reset_run() -> void:
	shared_checkpoint = "start"
	world_flags.clear()
	inventories.clear()
	play_time_sec = 0.0
	SaveSystem.checkpoint_snapshot = {}
