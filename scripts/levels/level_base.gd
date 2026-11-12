class_name LevelBase
extends Node3D
## Shared level logic: spawns both survivors at the shared checkpoint,
## replicates dynamic pickups, and owns the HUD.

var _pickup_counter := 0
var hud: Node

func _ready() -> void:
	add_to_group("level")
	Music.enter_game()
	build()
	_bake_navigation()
	_spawn_players()
	var director := HorrorDirector.new()
	director.name = "HorrorDirector"
	add_child(director)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			hud.bind_player(p)
	Net.partner_left.connect(_on_partner_left)
	# Story: tell the host this phone has the level, so cutscenes start for
	# both players together.
	Cutscenes.level_ready()

func _exit_tree() -> void:
	Cutscenes.level_left()

func _bake_navigation() -> void:
	var nav := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.cell_size = 0.15
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav.navigation_mesh = nm
	add_child(nav)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	nav.navigation_mesh = nm

## Override in each level.
func build() -> void:
	pass

func _spawn_players() -> void:
	var cp := _checkpoint(GameState.shared_checkpoint)
	var ids := GameState.character_by_peer.keys()
	ids.sort()
	var i := 0
	for id in ids:
		var p := Player.new()
		p.name = "Player_%d" % id
		p.peer_id = id
		p.character = GameState.character_by_peer[id]
		add_child(p)
		p.global_transform = cp.spawn_transform(i) if cp else Transform3D(Basis(), Vector3(i, 0.1, 0))
		i += 1

func _checkpoint(id: String) -> Checkpoint:
	for c in get_tree().get_nodes_in_group("checkpoints"):
		if c.checkpoint_id == id:
			return c
	var all := get_tree().get_nodes_in_group("checkpoints")
	return all[0] if not all.is_empty() else null

@rpc("authority", "reliable", "call_local")
func spawn_pickup(item: String, pos: Vector3, amount: int) -> void:
	_pickup_counter += 1
	var p := Pickup.new()
	p.name = "Drop_%d" % _pickup_counter
	p.item = item
	p.amount = max(amount, 0)
	add_child(p)
	p.global_position = pos

## Anyone can ask for something to be put on the floor (a dropped item, a
## gift the partner had no room for); the host spawns it for everyone.
func request_drop(item: String, pos: Vector3, amount: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		spawn_pickup.rpc(item, pos + Vector3(0, 0.05, 0), amount)
	else:
		_rpc_request_drop.rpc_id(1, item, pos, amount)

@rpc("any_peer", "reliable")
func _rpc_request_drop(item: String, pos: Vector3, amount: int) -> void:
	if multiplayer.is_server():
		spawn_pickup.rpc(item, pos + Vector3(0, 0.05, 0), amount)

## Host-requested spawn of a new enemy on every peer (window break-ins, brood larvae).
@rpc("authority", "reliable", "call_local")
func spawn_zombie_synced(name_: String, pos: Vector3, variant := "shambler") -> void:
	if has_node(name_):
		return
	var z := Zombie.new()
	z.name = name_
	z.variant = variant
	add_child(z)
	z.global_position = pos
	if multiplayer.is_server():
		z.state = Zombie.S.CHASE

## Lingering area damage (bloater gas, fire pools).
@rpc("authority", "reliable", "call_local")
func spawn_hazard(kind: String, pos: Vector3, radius: float, duration: float) -> void:
	var h := Hazard.new()
	h.kind = kind
	h.radius = radius
	h.duration = duration
	add_child(h)
	h.global_position = pos

func place_scare(id: String, kind: String, at: Vector3, size: Vector3, opts := {}) -> void:
	var t := ScareTrigger.new()
	t.scare_id = id
	t.kind = kind
	t.name = "Scare_" + id
	for k in opts:
		t.set(k, opts[k])
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position.y = size.y / 2
	t.add_child(cs)
	t.position = at
	add_child(t)

func place_stalker(at: Vector3, active := false) -> Stalker:
	var s := Stalker.new()
	s.name = "Tallyman"
	s.active = active
	s.position = at
	add_child(s)
	return s

## Everyone is down: back to the last checkpoint both players reached together.
func request_retry() -> void:
	if multiplayer.is_server():
		_rpc_retry.rpc()
	else:
		_rpc_ask_retry.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_ask_retry() -> void:
	var all_down := true
	for p in get_tree().get_nodes_in_group("players"):
		if not p.downed:
			all_down = false
	if multiplayer.is_server() and all_down:
		_rpc_retry.rpc()

@rpc("authority", "reliable", "call_local")
func _rpc_retry() -> void:
	var data := SaveSystem.read_slot(SaveSystem.AUTOSAVE_SLOT)
	if data.is_empty():
		data = SaveSystem.read_slot("slot1")
	if not data.is_empty():
		SaveSystem.apply_snapshot(data)
	get_tree().reload_current_scene()

func _on_partner_left(_id: int) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not GameState.character_by_peer.has(p.peer_id):
			p.queue_free()
	if hud:
		hud.toast("Your partner disconnected. Save to keep your progress.")

# ---- helpers for level scripts ----

func place_door(at: Vector3, rot_deg: float, kind: Door.Kind, style := "wood_panel", width := 1.1, height := 2.2, id := "", key := "") -> Door:
	var d := Door.new()
	d.kind = kind
	d.style = style
	d.width = width
	d.height = height
	d.door_id = id
	d.key_id = key
	d.name = "Door_" + (id if id != "" else str(get_child_count()))
	d.position = at
	d.rotation_degrees.y = rot_deg
	add_child(d)
	return d

func place_pickup(item: String, at: Vector3, id: String, amount := 0) -> void:
	var p := Pickup.new()
	p.item = item
	p.pickup_id = id
	p.amount = amount
	p.name = "Pickup_" + id
	p.position = at
	add_child(p)

func place_zombie(name_: String, at: Vector3, rot_deg := 0.0, variant := "shambler", asleep := false, look := "") -> void:
	if GameState.has_flag("dead:" + name_):
		return
	var z := Zombie.new()
	z.name = name_
	z.variant = variant
	z.look = look
	z.start_asleep = asleep
	z.position = at
	z.rotation_degrees.y = rot_deg
	add_child(z)

func place_checkpoint(id: String, at: Vector3, size: Vector3, safe := false) -> void:
	var c := Checkpoint.new()
	c.checkpoint_id = id
	c.is_safe_room = safe
	c.name = "CP_" + id
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position.y = size.y / 2
	c.add_child(cs)
	c.position = at
	add_child(c)
