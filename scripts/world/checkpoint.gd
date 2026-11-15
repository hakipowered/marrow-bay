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
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _on_enter(b: Node3D) -> void:
	if not b is Player:
		return
	_inside[b.peer_id] = true
	if is_safe_room and b.is_multiplayer_authority():
		Music.in_safe_room = true
	_check()

func _on_exit(b: Node3D) -> void:
	if not b is Player:
		return
	_inside.erase(b.peer_id)
	if is_safe_room and b.is_multiplayer_authority():
		Music.in_safe_room = false

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
	# A place they haven't been saved at yet, or a new chapter's first spot.
	# Not the spot a loaded game or a Continue puts them back at: that
	# would write over the autosave before they've done anything.
	var autosave := GameState.shared_checkpoint != checkpoint_id or SaveSystem.autosave_on_arrival
	GameState.set_shared_checkpoint(checkpoint_id)
	SaveSystem.mark_checkpoint()
	if autosave:
		# The host writes it (and sends the partner a copy), quietly, since
		# this toast already says so.
		SaveSystem.autosave_now()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast(("Checkpoint reached together" if Net.is_coop() else "Checkpoint reached") + (". Autosaved" if autosave else ""))

## Whether this player is standing in it now.
func holds(p: Node) -> bool:
	return p is Player and _inside.has(p.peer_id)

func spawn_transform(index: int) -> Transform3D:
	return global_transform.translated_local(Vector3((index * 2 - 1) * 0.8, 0, 0))
