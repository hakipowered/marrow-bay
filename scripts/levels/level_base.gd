class_name LevelBase
extends Node3D
## Shared level logic: spawns both survivors at the shared checkpoint,
## replicates dynamic pickups, and owns the HUD.

var _pickup_counter := 0
var hud: Node

func _ready() -> void:
	add_to_group("level")
	build()
	_bake_navigation()
	_spawn_players()
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			hud.bind_player(p)
	Net.partner_left.connect(_on_partner_left)

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

func place_zombie(name_: String, at: Vector3, rot_deg := 0.0, variant := "civilian", asleep := false) -> void:
	if GameState.has_flag("dead:" + name_):
		return
	var z := Zombie.new()
	z.name = name_
	z.variant = variant
	z.start_asleep = asleep
	z.drop_table = "brute" if variant == "brute" else "zombie"
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
