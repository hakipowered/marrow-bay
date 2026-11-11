extends Node
## Shot resolution. The shooter raycasts locally for instant feedback
## (tracers, sparks, blood); the host applies damage so zombies stay in sync.

const HITBOX_MASK := 1 | 8   # world + hitboxes

func fire(shooter: Node3D, weapon_id: String, origin: Vector3, dirs: Array, muzzle_pos: Vector3) -> void:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	Sfx.play_at("weapon_" + weapon_id, muzzle_pos, "gunshot")
	_alert_zombies(muzzle_pos, 0.0 if w.get("silent", false) else 25.0)
	match w["kind"]:
		"melee":
			_melee(shooter, weapon_id, w)
		"hitscan", "pellets":
			for d in dirs:
				_ray(shooter, weapon_id, w, origin, d, muzzle_pos)
		"flame":
			_flame(shooter, weapon_id, w, origin, dirs[0])
		"projectile":
			_rpc_projectile.rpc(weapon_id, muzzle_pos, dirs[0], shooter.peer_id)

func _ray(shooter: Node3D, weapon_id: String, w: Dictionary, origin: Vector3, dir: Vector3, muzzle_pos: Vector3) -> void:
	var space := shooter.get_world_3d().direct_space_state
	var exclude: Array[RID] = [shooter.get_rid()]
	var pierce: int = w.get("pierce", 1)
	var from := origin
	var end_point := origin + dir * 80.0
	for i in pierce:
		var q := PhysicsRayQueryParameters3D.create(from, origin + dir * 80.0, HITBOX_MASK, exclude)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		end_point = hit.position
		var col: Object = hit.collider
		if col.has_meta("hit_zone"):
			Effects.blood(hit.position, hit.normal)
			_request_damage(col, w["damage"], weapon_id, hit.position, dir)
			exclude.append(col.get_rid())
			from = hit.position + dir * 0.05
		else:
			Effects.impact(hit.position, hit.normal, col)
			break
	Effects.tracer(muzzle_pos, end_point)

func _melee(shooter: Node3D, weapon_id: String, w: Dictionary) -> void:
	var space := shooter.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 8
	q.collide_with_areas = true
	q.transform = Transform3D(Basis(), shooter.body.global_transform * Vector3(0, 1.2, -w["range"] * 0.6))
	var seen := {}
	for r in space.intersect_shape(q, 8):
		var col: Object = r.collider
		var owner_id := col.get_meta("owner_path", "")
		if col.has_meta("hit_zone") and not seen.has(owner_id):
			seen[owner_id] = true
			_request_damage(col, w["damage"], weapon_id, col.global_position, -shooter.body.global_transform.basis.z)

func _flame(shooter: Node3D, weapon_id: String, w: Dictionary, origin: Vector3, dir: Vector3) -> void:
	Effects.flame(shooter.muzzle.global_position, dir, w["range"])
	for z in get_tree().get_nodes_in_group("zombies"):
		var to: Vector3 = z.global_position + Vector3.UP - origin
		if to.length() < w["range"] and to.normalized().dot(dir) > 0.9:
			_request_damage_node(z, w["damage"], weapon_id, "torso", dir)

func _request_damage(col: Object, dmg: float, weapon_id: String, pos: Vector3, dir: Vector3) -> void:
	var enemy: Node = col.get_meta("enemy")
	if enemy:
		_request_damage_node(enemy, dmg, weapon_id, col.get_meta("hit_zone"), dir)

func _request_damage_node(enemy: Node, dmg: float, weapon_id: String, zone: String, dir: Vector3) -> void:
	if Cheats.on("one_hit_kills"):
		dmg = 99999.0
	var path := enemy.get_path()
	if multiplayer.is_server():
		_rpc_damage(path, dmg, weapon_id, zone, dir)
	else:
		_rpc_damage.rpc_id(1, path, dmg, weapon_id, zone, dir)

@rpc("any_peer", "reliable")
func _rpc_damage(path: NodePath, dmg: float, weapon_id: String, zone: String, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var enemy := get_node_or_null(path)
	if enemy and enemy.has_method("take_hit"):
		enemy.take_hit(dmg, weapon_id, zone, dir)

@rpc("any_peer", "reliable", "call_local")
func _rpc_projectile(weapon_id: String, pos: Vector3, dir: Vector3, owner_peer: int) -> void:
	var p := Projectile.new()
	p.weapon_id = weapon_id
	p.direction = dir
	p.owner_peer = owner_peer
	p.authoritative = multiplayer.is_server()
	get_tree().current_scene.add_child(p)
	p.global_position = pos

func explode(pos: Vector3, dmg: float, radius: float, weapon_id: String) -> void:
	Effects.explosion(pos, radius)
	Sfx.play_at("explosion", pos, "explosion")
	_alert_zombies(pos, 40.0)
	if not multiplayer.is_server():
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		var d: float = z.global_position.distance_to(pos)
		if d < radius:
			z.take_hit(dmg * (1.0 - d / radius * 0.6), weapon_id, "torso", (z.global_position - pos).normalized())

func _alert_zombies(pos: Vector3, radius: float) -> void:
	if radius <= 0:
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(pos) < radius:
			z.hear_noise(pos)
