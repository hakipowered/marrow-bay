class_name Checkpoint
extends Area3D
## A spot both players have to reach together (safe rooms, story beats).
## When every player is inside, it becomes the shared checkpoint that Save uses.

@export var checkpoint_id := "start"
@export var is_safe_room := false
var _inside := {}

func _ready() -> void:
	add_to_group("checkpoints")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(func(b): if b is Player: _inside[b.peer_id] = true; _check())
	body_exited.connect(func(b): if b is Player: _inside.erase(b.peer_id))

func _check() -> void:
	if not multiplayer.is_server():
		return
	var all := get_tree().get_nodes_in_group("players")
	for p in all:
		if not _inside.has(p.peer_id):
			return
	_rpc_reached.rpc()

@rpc("authority", "reliable", "call_local")
func _rpc_reached() -> void:
	GameState.set_shared_checkpoint(checkpoint_id)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Checkpoint reached together" if Net.is_coop() else "Checkpoint reached")

func spawn_transform(index: int) -> Transform3D:
	return global_transform.translated_local(Vector3((index * 2 - 1) * 0.8, 0, 0))
