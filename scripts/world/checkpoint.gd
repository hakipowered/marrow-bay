class_name Checkpoint
extends Area3D
## A spot both players have to reach together (safe rooms, story beats).
## When every player is inside, it becomes the shared checkpoint that Save uses.

@export var checkpoint_id := "start"
@export var is_safe_room := false
var _inside := {}
## Reached while infected are on them: the checkpoint waits until the fight
## is over (or they leave). Taken mid-fight it remembered whatever had died
## by then: Bulmaim crossed the Great Hall's checkpoint with the vault brute
## after her, died to him, and came back to a vault where the shield cop and
## the grappler were already gone. Continue goes back to before the fight.
var _pending := false
var _recheck_t := 0.0

func _ready() -> void:
	add_to_group("checkpoints")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	set_physics_process(false)

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
	if _inside.is_empty():
		_pending = false
	if is_safe_room and b.is_multiplayer_authority():
		Music.in_safe_room = false

func _check() -> void:
	if not multiplayer.is_server():
		return
	var all := get_tree().get_nodes_in_group("players")
	for p in all:
		# (Never with someone down: a pending checkpoint taken once the
		# infected lost interest in her body kept the fight's dead.)
		if not _inside.has(p.peer_id) or p.downed or p.dead:
			return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl and lvl.get("game_over"):
		return
	if hunted(all) and _has_fallback():
		_pending = true
		_recheck_t = 0.5
		set_physics_process(true)
		return
	_pending = false
	_rpc_reached.rpc()

## Only wait when Continue already has somewhere in this level to go back
## to: the first checkpoint of a run or of a level is taken even mid-fight,
## or Continue would fall back to an old save from another run.
func _has_fallback() -> bool:
	var snap: Dictionary = SaveSystem.checkpoint_snapshot
	return not snap.is_empty() and snap.get("level", "") == GameState.level_path

func _physics_process(delta: float) -> void:
	if not _pending:
		set_physics_process(false)
		return
	_recheck_t -= delta
	if _recheck_t <= 0.0:
		_recheck_t = 0.5
		_check()

## Infected on the survivors right now: hunting them and close by or in
## plain sight (one clawing at a shut door elsewhere doesn't count), or the
## Tallyman awake and near.
static func hunted(players: Array) -> bool:
	for p in players:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
		for z in p.get_tree().get_nodes_in_group("zombies"):
			if not z.get("state") in [Zombie.S.CHASE, Zombie.S.CRAWL, Zombie.S.ATTACK, Zombie.S.CHARGE, Zombie.S.PINNING, Zombie.S.STAGGER]:
				continue
			var d: float = p.global_position.distance_to(z.global_position)
			if d < 5.0:
				return true
			if d < 22.0:
				var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.4, z.global_position + Vector3.UP * 1.3, 1)
				q.exclude = [p.get_rid(), z.get_rid()]
				if space.intersect_ray(q).is_empty():
					return true
		for s in p.get_tree().get_nodes_in_group("stalker"):
			if s.get("active") and p.global_position.distance_to(s.global_position) < 14.0:
				return true
	return false

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
