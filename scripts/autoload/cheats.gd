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
}

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
