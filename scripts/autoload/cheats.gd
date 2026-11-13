extends Node
## Cheat menu flags. The host owns them in co-op and syncs them to the partner.

signal changed(name: String, value: bool)

const LIST := {
	"god_mode": "God mode",
	"infinite_ammo": "Infinite ammo",
	"no_reload": "No reload",
	"one_hit_kills": "One-hit kills",
	"all_weapons": "Unlock all weapons",
	"unlock_doors": "Unlock all doors",
	"solo_coop_doors": "Open co-op doors alone",
	"noclip": "Noclip",
	"slow_zombies": "Slow zombies",
	"show_hitboxes": "Show hitboxes",
	"infinite_heals": "Infinite healing",
	"rocket_launcher": "Infinite rocket launcher",
	"no_explosive_ff": "No explosive friendly fire",
}

## Chapter select (cheat menu): both phones load a chapter's first level
## together, each survivor keeping their bag. [button text, level, checkpoint]
const CHAPTERS := [
	["Go to chapter 1: the Archive", "res://scenes/levels/archive_hub.tscn", "start"],
	["Go to chapter 2: the Undercroft", "res://scenes/levels/undercroft.tscn", "ch2_lift"],
]

var flags: Dictionary = {}

func _ready() -> void:
	for k in LIST:
		flags[k] = false

func on(name: String) -> bool:
	return flags.get(name, false)

func set_cheat(name: String, value: bool) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_request.rpc_id(1, name, value)
		return
	_apply(name, value)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_rpc_apply.rpc(name, value)

@rpc("any_peer", "reliable")
func _rpc_request(name: String, value: bool) -> void:
	if multiplayer.is_server():
		set_cheat(name, value)

@rpc("authority", "reliable")
func _rpc_apply(name: String, value: bool) -> void:
	_apply(name, value)

func _apply(name: String, value: bool) -> void:
	if not flags.has(name):
		return
	flags[name] = value
	if name == "show_hitboxes":
		get_tree().debug_collisions_hint = value
	changed.emit(name, value)

func jump_to_chapter(i: int) -> void:
	if i < 0 or i >= CHAPTERS.size():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_jump_request.rpc_id(1, i)
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_rpc_jump.rpc(i)
	_jump(i)

@rpc("any_peer", "reliable")
func _rpc_jump_request(i: int) -> void:
	if multiplayer.is_server():
		jump_to_chapter(i)

@rpc("authority", "reliable")
func _rpc_jump(i: int) -> void:
	_jump(i)

func _jump(i: int) -> void:
	get_tree().paused = false
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("change_level"):
		level.change_level(CHAPTERS[i][1], CHAPTERS[i][2])
