extends SceneTree
## Every explosive in the first area goes off from every gun, fired the way
## a player fires it: through the survivor's own trigger (hip-fire spread,
## hip-fire aim help, pellets), standing a few metres off with the crosshair
## on it. Half the shots have an infected standing right beside the drum,
## where hip-fire aim help used to bend the shot onto the infected instead.
## Rounds: every drum with each gun in turn, hip and aimed; then grenades,
## a frag and the flamethrower.
## Prints BARRELS OK, or BARRELS FAIL with each miss and what the shot hit.
## godot --headless --fixed-fps 60 --path . --script tests/barrels_every_gun.gd
const GUNS := ["p9", "m12", "breacher", "vk18", "bastion", "hornet", "carbine", "longshot"]
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var fails := []
var round_i := 0
var queue := []      # [breakable id, weapon, aimed, with infected]
var cur := []
var shots := 0
var _z_template: Node = null
var _zs := []
var _pending := {}

func _initialize() -> void:
	pass

func _bk(col: Object) -> Node:
	if col and col.has_meta("breakable"):
		var b: Variant = col.get_meta("breakable")
		if is_instance_valid(b):
			return b
	return null

func _W() -> Dictionary:
	return load("res://scripts/weapons/weapon_db.gd").WEAPONS

func _b(id: String) -> Node:
	return current_scene.find_child("Breakable_" + id, true, false)

func _explosives() -> Array:
	var out := []
	for b in get_nodes_in_group("breakables"):
		if b.explosive():
			out.append(b.breakable_id)
	out.sort()
	return out

## Somewhere 4.5-7 m off with a clear line from eye height to the drum.
func _spot_for(b: Node) -> Variant:
	var c: Vector3 = b.global_transform * b.center
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	for dist in [6.0, 5.0, 4.5, 7.0, 3.5]:
		for i in 16:
			var a := TAU * i / 16.0
			var at := Vector3(c.x + sin(a) * dist, 0.05, c.z + cos(a) * dist)
			# Floor under her, nothing in the way at her eyes or at the camera.
			var fq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6, 1)
			if space.intersect_ray(fq).is_empty():
				continue
			var ok := true
			for h in [0.4, 1.0, 1.6]:
				var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * h, c, 1 | 8)
				q.collide_with_areas = true
				var hit: Dictionary = space.intersect_ray(q)
				if not hit.is_empty() and _bk(hit.collider) != b:
					ok = false
					break
			# Room for her body.
			var sq := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.35
			cap.height = 1.7
			sq.shape = cap
			sq.collision_mask = 1
			sq.transform = Transform3D(Basis(), at + Vector3.UP * 0.95)
			if ok and space.intersect_shape(sq, 1).is_empty():
				return at
	return null

## Turn her (and the camera rig) until the crosshair sits on the point.
func _aim_at(target: Vector3) -> float:
	var cam: Camera3D = p.camera
	for i in 6:
		var d: Vector3 = (target - cam.global_position).normalized()
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = clampf(asin(d.y), -1.2, 0.9)
		p.body.rotation.y = p.yaw
		p.pivot.rotation = Vector3(p.pitch, p.yaw, 0)
	var d2: Vector3 = (target - cam.global_position).normalized()
	return rad_to_deg((-cam.global_transform.basis.z).angle_to(d2))

func _what_the_dot_is_on() -> String:
	var cam: Camera3D = p.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_transform.basis.z * 60.0, 1 | 8, [p.get_rid()])
	q.collide_with_areas = true
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "nothing"
	var b: Node = _bk(hit.collider)
	if b:
		return "Breakable_" + b.breakable_id
	var n: Node = hit.collider
	return "%s at %s" % [n.name, hit.position.snapped(Vector3.ONE * 0.01)]

## Every gun hip and aimed (16 pulls), spread over the drums; odd rounds walk
## the drums the other way, so ones a neighbour set off get their own shot.
var _combos := []

func _build_round() -> void:
	if _combos.is_empty() and round_i == 0:
		for w in GUNS:
			_combos.append([w, false])
			_combos.append([w, true])
	queue.clear()
	var ids := _explosives()
	if round_i % 2 == 1:
		ids.reverse()
	for i in ids.size():
		queue.append([ids[i], "", false, (i + round_i) % 2 == 0])

## The gun for the next trial, taken only when a drum is really shot at.
func _next_combo() -> Array:
	if not _combos.is_empty():
		return _combos.pop_front()
	shots_extra += 1
	return [GUNS[(shots_extra * 3) % GUNS.size()], shots_extra % 2 == 0]

var shots_extra := 0

func _reset_level() -> void:
	for id in _explosives():
		root.get_node("GameState").set_flag("broken:" + id, false)
	for k in root.get_node("GameState").world_flags.keys():
		if str(k).begins_with("broken:"):
			root.get_node("GameState").world_flags.erase(k)
	reload_current_scene()

func _setup_player() -> void:
	p = get_first_node_in_group("players")
	var inv = p.inventory
	for w in GUNS + ["gl", "flamer", "frag"]:
		inv.add_weapon(w)
	for a in ["9mm", "shells", "50cal", "rifle", "grenades", "fuel", "frag"]:
		inv.add_ammo(a, 200)
	_zs.clear()
	for zz in get_nodes_in_group("zombies"):
		_zs.append(zz)
		# Out of the way and still until a trial stands one by a drum.
		zz.global_position = Vector3(0, -40, 0) + Vector3(_zs.size() * 3.0, 0, 0)
		zz.process_mode = Node.PROCESS_MODE_DISABLED

func _z_beside(b: Node, from: Vector3) -> Node:
	for zz in _zs:
		if not is_instance_valid(zz) or zz.get("state") == zz.get_script().get_script_constant_map()["S"]["DEAD"]:
			continue
		if zz.global_position.y > -20.0:
			continue
		var c: Vector3 = b.global_transform * b.center
		var side := (c - from).cross(Vector3.UP).normalized()
		zz.global_position = Vector3(c.x, 0.0, c.z) + side * 1.0
		zz.look_at(Vector3(from.x, 0.0, from.z), Vector3.UP, true)
		return zz
	return null

func _park(zz: Node) -> void:
	if is_instance_valid(zz):
		zz.global_position = Vector3(0, -40, 0) + Vector3(randf() * 60.0, 0, 0)

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	t += d
	match stage:
		0:
			if frames > 2:
				root.get_node("GameState").reset_run()
				root.get_node("Net").start_solo("obcera")
				root.get_node("Cheats").set_cheat("god_mode", true)
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				t = 0.0
		1:
			if t > 1.0:
				_setup_player()
				_build_round()
				print("round %d: %d explosives" % [round_i, queue.size()])
				stage = 2
				t = 0.0
		2:
			# Next trial.
			if queue.is_empty():
				round_i += 1
				if round_i < 4:
					_reset_level()
					stage = 1
					t = 0.0
				else:
					stage = 10
					t = 0.0
				return false
			cur = queue.pop_front()
			var b := _b(cur[0])
			if b == null or b.broken:
				return false   # went up with a neighbour earlier this round
			var spot = _spot_for(b)
			if spot == null:
				fails.append("%s: nowhere to stand with a clear shot" % cur[0])
				return false
			var combo := _next_combo()
			cur[1] = combo[0]
			cur[2] = combo[1]
			p.global_position = spot
			p.velocity = Vector3.ZERO
			var z: Node = _z_beside(b, spot) if cur[3] else null
			set_meta("z", z)
			var w: String = cur[1]
			p.equip(w)
			p.inventory.mag[w] = _W()[w].get("mag", 1)
			p.aiming = cur[2]
			stage = 3
			t = 0.0
		3:
			# Let the camera settle (aiming zooms in), then fire one trigger pull.
			var b := _b(cur[0])
			var c: Vector3 = b.global_transform * b.center
			var off := _aim_at(c)
			if t > 0.45:
				var on := _what_the_dot_is_on()
				set_meta("on", on)
				# A tap on FIRE, through her own trigger code (bursts, pellets,
				# hip-fire turn and aim help).
				p._cooldown = 0.0
				p.fire_held = true
				shots += 1
				set_meta("off", off)
				stage = 4
				t = 0.0
		4:
			p.aiming = cur[2]
			if t > 0.03:
				p.fire_held = false
			if t > 1.1:
				var b := _b(cur[0])
				var how := "%s %s%s" % [cur[1], "aimed" if cur[2] else "hip", " (infected beside it)" if cur[3] else ""]
				if not b.broken:
					fails.append("%s didn't go up: %s; dot on %s, %.1f deg off" % [cur[0], how, get_meta("on"), get_meta("off")])
					print("  FAIL ", cur[0], " ", how, " dot on ", get_meta("on"))
				else:
					print("  ok   ", cur[0], " ", how)
				_park(get_meta("z"))
				p.aiming = false
				stage = 2
				t = 0.0
		10:
			# Thumper grenade, a thrown frag, the flamethrower.
			_reset_level()
			stage = 11
			t = 0.0
		11:
			if not get_meta("placed", false):
				if t > 1.0:
					_setup_player()
					_place_for("court_drum_gate", "gl")
					set_meta("placed", true)
					t = 0.0
			elif t > 0.5:
				_trial_explosive("court_drum_gate", "gl")
				stage = 12
				t = 0.0
		12:
			if frames % 6 == 0 and t < 1.0:
				for n in current_scene.get_children():
					if n.get_script() and str(n.get_script().resource_path).ends_with("projectile.gd"):
						print("    grenade at ", n.global_position, " t=%.2f" % t)
			if t > 2.5:
				_check_up("court_drum_gate", "Thumper grenade")
				_trial_explosive("vault_drum", "frag")
				stage = 13
				t = 0.0
		13:
			if t > 4.0:
				_check_up("vault_drum", "frag grenade")
				var b := _b("street_drum_east")
				var c: Vector3 = b.global_transform * b.center
				var dir := Vector3(1, 0, 0.3).normalized()
				p.global_position = Vector3(c.x, 0.05, c.z) - dir * 4.0
				p.equip("flamer")
				p.aiming = true
				stage = 14
				t = 0.0
		14:
			var b := _b("street_drum_east")
			_aim_at(b.global_transform * b.center)
			p.aiming = true
			if t > 0.4 and t < 2.4:
				p._cooldown = 0.0
				p._fire_once(_W()["flamer"])
			if t > 5.5:
				_check_up("street_drum_east", "flamethrower")
				stage = 20
		20:
			print("%d trigger pulls" % shots)
			print("BARRELS OK" if fails.is_empty() else "BARRELS FAIL: " + "; ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false

func _place_for(id: String, w: String) -> void:
	var b := _b(id)
	var spot = _spot_for(b)
	if spot == null:
		fails.append("%s: nowhere to stand for the %s" % [id, w])
		return
	p.global_position = spot
	p.equip(w)
	p.inventory.mag[w] = _W()[w].get("mag", 1)
	p.aiming = true
	_aim_at(b.global_transform * b.center + Vector3.UP * 0.2)

func _trial_explosive(id: String, w: String) -> void:
	var b := _b(id)
	if w != "gl":
		_place_for(id, w)
	p.aiming = true
	_aim_at(b.global_transform * b.center + Vector3.UP * 0.2)
	p._cooldown = 0.0
	if _W()[w]["kind"] == "throwable":
		var cam: Camera3D = p.camera
		var dir: Vector3 = (b.global_transform * b.center - cam.global_position)
		dir.y = 0.0
		# A lob that lands at its feet.
		root.get_node("Combat").fire(p, w, cam.global_position, [dir.normalized() * 0.55 + Vector3.DOWN * 0.1], p._muzzle_pos())
	else:
		p._fire_once(_W()[w])

func _check_up(id: String, what: String) -> void:
	var b := _b(id)
	if b and b.broken:
		print("  ok   ", id, " ", what)
	else:
		fails.append("%s didn't go up from the %s" % [id, what])
		print("  FAIL ", id, " ", what)
