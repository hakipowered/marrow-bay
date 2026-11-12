extends Node
## Shot resolution. The shooter raycasts locally for instant feedback
## (tracers, sparks, blood); the host applies damage so zombies stay in sync.

const HITBOX_MASK := 1 | 8   # world + hitboxes

## Shot sounds that share a recording, and how loud each class carries.
const SOUND_FOR := {"vk18": "weapon_p9", "flash": "weapon_throw", "frag": "weapon_throw", "knife": "weapon_knife", "hatchet": "weapon_hatchet"}
var _flame_sound_at := 0

static func shot_sound(weapon_id: String) -> String:
	return SOUND_FOR.get(weapon_id, "weapon_" + weapon_id)

func fire(shooter: Node3D, weapon_id: String, origin: Vector3, dirs: Array, muzzle_pos: Vector3) -> void:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	play_shot_sound(weapon_id, muzzle_pos)
	var loud := 0.0 if w.get("silent", false) else (6.0 if w["kind"] in ["melee", "throwable"] else 25.0)
	_alert_zombies(muzzle_pos, loud)
	match w["kind"]:
		"melee":
			melee_hit(shooter, weapon_id, null)
		"hitscan", "pellets":
			for d in dirs:
				_ray(shooter, weapon_id, w, origin, d, muzzle_pos)
		"flame":
			_flame(shooter, weapon_id, w, origin, dirs[0])
		"projectile":
			_rpc_projectile.rpc(weapon_id, muzzle_pos, _from_muzzle(shooter, origin, dirs[0], muzzle_pos), shooter.peer_id)
		"throwable":
			# Lobbed: aim direction tipped upward so it arcs over cover.
			var d: Vector3 = (dirs[0] + Vector3.UP * 0.35).normalized()
			_rpc_projectile.rpc(weapon_id, muzzle_pos, d, shooter.peer_id)

## Projectiles leave the gun, not the camera: aim them from the muzzle at the
## point the camera line meets. Flying parallel to that line put crossbow bolts
## half a metre beside whatever the dot was on, so they missed.
func _from_muzzle(shooter: Node3D, origin: Vector3, dir: Vector3, muzzle_pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0, HITBOX_MASK, [shooter.get_rid()])
	q.collide_with_areas = true
	var hit := shooter.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else origin + dir * 80.0
	var d := at - muzzle_pos
	# Something right in front of the camera (a wall at her shoulder): keep
	# the camera's line rather than firing sideways or back.
	if d.length() < 0.6 or d.normalized().dot(dir) < 0.5:
		return dir
	return d.normalized()

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
			Effects.blood(hit.position, hit.normal, dir, _gore(w))
			_request_damage(col, w["damage"], weapon_id, hit.position, dir)
			exclude.append(col.get_rid())
			from = hit.position + dir * 0.05
		else:
			Effects.impact(hit.position, hit.normal, col)
			break
	Effects.tracer(muzzle_pos, end_point, 0.7 if w["kind"] == "pellets" else 1.0)

## What the partner sees of a shot fired on the other phone: the tracer, the
## sparks or blood where it lands, the flamethrower's stream and who it sets
## alight. Visual only: the shooter's own game sends the damage to the host.
func remote_shot_fx(shooter: Node3D, weapon_id: String, from: Vector3, dir: Vector3) -> void:
	var w: Dictionary = WeaponDB.WEAPONS.get(weapon_id, {})
	match w.get("kind", ""):
		"hitscan", "pellets":
			var space := shooter.get_world_3d().direct_space_state
			var spread := deg_to_rad(float(w.get("spread", 0.0)))
			var pellets: bool = w.get("kind") == "pellets"
			for i in int(w.get("pellets", 1)):
				var d := dir.rotated(Vector3.UP, randf_range(-spread, spread) * 0.5)
				d = d.rotated(shooter.global_transform.basis.x.normalized(), randf_range(-spread, spread) * 0.5)
				var q := PhysicsRayQueryParameters3D.create(from, from + d * 80.0, HITBOX_MASK, [shooter.get_rid()])
				q.collide_with_areas = true
				var hit := space.intersect_ray(q)
				var end := from + d * 80.0
				if not hit.is_empty():
					end = hit.position
					if hit.collider.has_meta("hit_zone"):
						Effects.blood(hit.position, hit.normal, d, _gore(w))
					else:
						Effects.impact(hit.position, hit.normal, hit.collider)
				Effects.tracer(from, end, 0.7 if pellets else 1.0)
		"flame":
			Effects.flame_stream(shooter, from, dir, w["range"])
			for z in get_tree().get_nodes_in_group("zombies"):
				var to: Vector3 = z.global_position + Vector3.UP - from
				if to.length() < w["range"] and to.normalized().dot(dir) > 0.9 and z.get("state") != Zombie.S.DEAD \
						and not z.get("data").get("fire_immune", false):
					Effects.ignite(z, float(w.get("burn", 4.0)))

## How much blood a hit throws: a pistol round about 1, a magnum or rifle
## round more, each shotgun pellet less.
static func _gore(w: Dictionary) -> float:
	if w.get("kind") == "pellets":
		return 0.45
	return clampf(float(w.get("damage", 25)) / 28.0, 0.7, 2.2)

## Gun, swing and throw sounds. The flamethrower plays its roar once per
## couple of seconds rather than on every tick of fuel.
func play_shot_sound(weapon_id: String, pos: Vector3) -> void:
	var w: Dictionary = WeaponDB.WEAPONS.get(weapon_id, {})
	if w.get("kind") == "flame":
		if Time.get_ticks_msec() - _flame_sound_at < 1800:
			return
		_flame_sound_at = Time.get_ticks_msec()
		Sfx.play_at("flamer_loop", pos, "", -2.0, 8.0)
		return
	var quiet: bool = w.get("kind") in ["melee", "throwable"]
	Sfx.play_at(shot_sound(weapon_id), pos, "" if quiet else "weapon_p9", -4.0 if quiet else 0.0, 4.0 if quiet else 14.0)

## A knife or hatchet swing landing. Checks in front of the swing at chest,
## knee and floor height (so crawlers and legless ones get hit too), and falls
## back to the soft-locked target if it is within reach. The knife cuts one
## body, the hatchet up to two. Returns whether anything was hit.
func melee_hit(shooter: Node3D, weapon_id: String, target: Node3D) -> bool:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	var space := shooter.get_world_3d().direct_space_state
	var xf: Transform3D = shooter.body.global_transform
	var fwd := -xf.basis.z
	var reach: float = w.get("range", 1.8)
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 8
	q.collide_with_areas = true
	var hits := {}   # enemy -> [collider, zone]
	for h in [1.2, 0.55, 0.22]:
		var center := xf * Vector3(0, h, -reach * 0.55)
		q.transform = Transform3D(Basis(), center)
		var best: Object = null
		var best_d := INF
		for r in space.intersect_shape(q, 12):
			var col: Object = r.collider
			if not col.has_meta("hit_zone"):
				continue
			var enemy: Node = col.get_meta("enemy")
			if enemy == null or hits.has(enemy):
				continue
			var d: float = (col as Node3D).global_position.distance_to(center)
			if d < best_d:
				best_d = d
				best = col
		if best:
			hits[best.get_meta("enemy")] = [best, best.get_meta("hit_zone")]
	if hits.is_empty() and is_instance_valid(target) and target.has_method("take_hit"):
		var to := target.global_position - shooter.global_position
		to.y = 0.0
		if to.length() <= reach + 0.45 and fwd.dot(to.normalized()) > 0.3:
			hits[target] = [null, "torso"]
	var cap := 2 if weapon_id == "hatchet" else 1
	var n := 0
	for enemy in hits:
		if n >= cap:
			break
		n += 1
		var col: Object = hits[enemy][0]
		var at: Vector3 = (col as Node3D).global_position if col else enemy.global_position + Vector3.UP
		Effects.blood(at, -fwd, fwd, 1.3 if weapon_id == "hatchet" else 0.9)
		_request_damage_node(enemy, w["damage"], weapon_id, hits[enemy][1], fwd)
	if n > 0:
		Sfx.play_at("melee_hit", xf * Vector3(0, 1.2, -reach * 0.5), "", -2.0, 6.0)
		_alert_zombies(shooter.global_position, 6.0)
	return n > 0

func _flame(shooter: Node3D, weapon_id: String, w: Dictionary, origin: Vector3, dir: Vector3) -> void:
	var from: Vector3 = shooter._muzzle_pos() if shooter.has_method("_muzzle_pos") else shooter.muzzle.global_position
	Effects.flame_stream(shooter, from, dir, w["range"])
	for z in get_tree().get_nodes_in_group("zombies"):
		var to: Vector3 = z.global_position + Vector3.UP - origin
		if to.length() < w["range"] and to.normalized().dot(dir) > 0.9:
			_request_damage_node(z, w["damage"], weapon_id, "torso", dir)
			if z.get("state") != Zombie.S.DEAD and not z.get("data").get("fire_immune", false):
				Effects.ignite(z, float(w.get("burn", 4.0)))

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

## Share of explosive damage that players take (rockets, grenades, frags,
## barrels). Applies to the partner and to yourself, like real friendly fire.
const EXPLOSIVE_FF := 0.35

## Runs on every peer (projectiles are simulated everywhere): each peer hurts
## its own player, the host hurts zombies.
func explode(pos: Vector3, dmg: float, radius: float, weapon_id: String, owner_peer := 0) -> void:
	Effects.explosion(pos, radius)
	Sfx.play_at("explosion", pos, "explosion")
	_alert_zombies(pos, 40.0)
	if not Cheats.on("no_explosive_ff"):
		for p in get_tree().get_nodes_in_group("players"):
			if not p.is_multiplayer_authority():
				continue
			var pd: float = p.global_position.distance_to(pos)
			if pd >= radius:
				continue
			var blocked := _wall_between(p, pos)
			var amount := dmg * EXPLOSIVE_FF * (1.0 - pd / radius * 0.7) * (0.35 if blocked else 1.0)
			p.apply_damage(amount, null)
			var post := get_tree().get_first_node_in_group("horror")
			if post and post.get("post_fx"):
				post.post_fx.spike(0.8)
			# Hit by the partner's explosive: shout at them.
			if owner_peer != 0 and owner_peer != p.peer_id and not p.downed:
				var line := "z_wtf" if p.character == "zegan" else "o_zaga"
				CallOuts.call_partner(true, line)
	if not multiplayer.is_server():
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		var d: float = z.global_position.distance_to(pos)
		if d < radius:
			z.take_hit(dmg * (1.0 - d / radius * 0.6), weapon_id, "torso", (z.global_position - pos).normalized())

func _wall_between(p: Node3D, pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, p.global_position + Vector3.UP * 1.0, 1)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Flash grenade: blinds and staggers zombies, whites out nearby players.
func flash(pos: Vector3, radius: float) -> void:
	Effects.flash_burst(pos)
	Sfx.play_at("flashbang", pos, "explosion")
	_alert_zombies(pos, 30.0)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority() and p.global_position.distance_to(pos) < radius and not _wall_between(p, pos):
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("white_flash"):
				hud.white_flash(1.6)
	if multiplayer.is_server():
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.global_position.distance_to(pos) < radius and z.has_method("flashed"):
				z.flashed(4.0)

func _alert_zombies(pos: Vector3, radius: float) -> void:
	if radius <= 0:
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(pos) < radius:
			z.hear_noise(pos)
