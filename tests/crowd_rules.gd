extends SceneTree
## Headless checks for the 0.9 playtest fixes on the zombie side:
##  1. Dodge roll: carries her about 3.4 m along the stick in about a second
##     with the roll clip, and a swing that lands mid-roll does nothing.
##  2. No stun lock: three shamblers on her with a wall at her back land
##     blows at least 1.25 s apart, and the one that hits steps back.
##  3. No hits through walls: a shambler behind a wall a metre from her
##     never swings.
##  4. Groans: a chasing pack takes turns, never two starting within 1.5 s.
## Prints CROWD OK, or CROWD FAIL with the reasons.
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var lvl: Node = null
var fails := []
var notes := []
var start := Vector3.ZERO
var fwd := Vector3.ZERO
var side := Vector3.ZERO
var hits := []
var last_hp := 0.0
var zs := []
var swings := 0
var groans := []
var last_groan := 0
var max_roll_anim := false
var roll_hp := 0.0
var _wall: StaticBody3D = null
var recoil_seen := false

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				p = get_first_node_in_group("players")
				lvl = get_first_node_in_group("level")
				_clear()
				start = p.global_position
				fwd = -p.body.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				side = fwd.cross(Vector3.UP).normalized()
				stage = 2
				t = 0.0
		# --- 1. the roll -------------------------------------------------
		2:
			p.move_input = Vector2.ZERO
			p.roll()
			if not p.rolling:
				fails.append("roll did not start")
				stage = 10
			else:
				t = 0.0
				stage = 3
				lvl.spawn_zombie_synced("RollZ", p.global_position + fwd * 0.6 + side * 0.9, "shambler")
				var z: Node = lvl.get_node("RollZ")
				z.look_at(p.global_position, Vector3.UP)
				z._begin_attack()
				z._atk["windup"] = 0.2   # lands while she is mid-roll
				z.target = p
				roll_hp = p.hp
		3:
			t += d
			if p.model._current == "combat/roll":
				max_roll_anim = true
			if not p.rolling:
				var moved: float = (p.global_position - start).length()
				notes.append("roll: %.2f m in %.2f s, clip played %s, hp %d -> %d" % [moved, t, str(max_roll_anim), roll_hp, p.hp])
				if moved < 2.8 or moved > 4.0:
					fails.append("roll covered %.2f m" % moved)
				if t < 0.8 or t > 1.4:
					fails.append("roll took %.2f s" % t)
				if not max_roll_anim:
					fails.append("roll clip never played")
				if p.hp < roll_hp:
					fails.append("hit during the roll")
				stage = 4
				t = 0.0
			elif t > 3.0:
				fails.append("roll never ended")
				stage = 4
		# --- 2. crowd against a wall -----------------------------------
		4:
			_clear()
			p.global_position = start
			p.hp = 5000.0
			last_hp = p.hp
			_wall = _make_wall(start - fwd * 0.75, fwd)
			for i in 3:
				var off: Vector3 = [fwd, fwd * 0.7 + side * 0.7, fwd * 0.7 - side * 0.7][i] * 1.05
				lvl.spawn_zombie_synced("CrowdZ%d" % i, start + off, "shambler")
				var z: Node = lvl.get_node("CrowdZ%d" % i)
				z.look_at(start, Vector3.UP)
				z.state = z.S.CHASE
				zs.append(z)
			t = 0.0
			stage = 5
		5:
			t += d
			p.move_input = Vector2.ZERO
			if p.hp < last_hp - 0.01:
				hits.append(t)
				last_hp = p.hp
			for z in zs:
				if is_instance_valid(z) and z._recoil_t > 0.0 and z.velocity.length() > 1.0:
					recoil_seen = true
			if t > 7.0:
				var gaps := []
				for i in range(1, hits.size()):
					gaps.append(snappedf(hits[i] - hits[i - 1], 0.01))
				notes.append("crowd against a wall: %d blows in 7 s, gaps %s, recoil seen %s" % [hits.size(), str(gaps), str(recoil_seen)])
				if hits.is_empty():
					fails.append("the crowd never hit (test setup?)")
				for g in gaps:
					if g < 1.25:
						fails.append("two blows %.2f s apart" % g)
				if not recoil_seen:
					fails.append("no zombie stepped back after hitting")
				stage = 6
				t = 0.0
		# --- 3. through a wall ---------------------------------------------
		6:
			_clear()
			p.global_position = start
			p.hp = 5000.0
			last_hp = p.hp
			# Wall between her and the zombie, a metre apart.
			_wall = _make_wall(start + fwd * 0.5, fwd)
			lvl.spawn_zombie_synced("WallZ", start + fwd * 1.0, "shambler")
			var wz: Node = lvl.get_node("WallZ")
			wz.look_at(start, Vector3.UP)
			wz.state = wz.S.CHASE
			zs = [wz]
			swings = 0
			stage = 7
			t = 0.0
		7:
			t += d
			p.move_input = Vector2.ZERO
			p.global_position = start
			var wz: Node = zs[0]
			if is_instance_valid(wz) and wz.state == wz.S.ATTACK:
				swings += 1
			if t > 4.0:
				notes.append("zombie behind a wall: %d frames swinging, hp %d -> %d" % [swings, last_hp, p.hp])
				if swings > 0 or p.hp < last_hp:
					fails.append("swung through the wall")
				stage = 8
				t = 0.0
		# --- 4. groans take turns ------------------------------------------
		8:
			_clear()
			p.global_position = start
			for i in 6:
				var pos: Vector3 = start + fwd * (6.0 + i) + side * (i - 3)
				lvl.spawn_zombie_synced("PackZ%d" % i, pos, "shambler")
				var z: Node = lvl.get_node("PackZ%d" % i)
				z.state = z.S.CHASE
				z._groan_t = 0.0
				zs.append(z)
			last_groan = zs[0]._last_groan_ms
			stage = 9
			t = 0.0
		9:
			t += d
			p.global_position = start
			if zs[0]._last_groan_ms != last_groan:
				groans.append(t)
				last_groan = zs[0]._last_groan_ms
			if t > 15.0:
				var gaps := []
				for i in range(1, groans.size()):
					gaps.append(snappedf(groans[i] - groans[i - 1], 0.1))
				notes.append("six chasing: %d groans in 15 s, gaps %s" % [groans.size(), str(gaps)])
				for g in gaps:
					if g < 1.5:
						fails.append("two groans %.1f s apart" % g)
				if groans.size() < 2:
					fails.append("the pack stayed silent")
				stage = 10
		10:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("CROWD OK")
			else:
				print("CROWD FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _clear() -> void:
	for zz in get_nodes_in_group("zombies"):
		zz.queue_free()
	zs.clear()
	if _wall:
		_wall.queue_free()
		_wall = null

func _make_wall(at: Vector3, normal: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(6.0, 3.0, 0.3)
	cs.shape = b
	w.add_child(cs)
	lvl.add_child(w)
	w.global_position = at + Vector3.UP * 1.5
	w.look_at(w.global_position + normal, Vector3.UP)
	return w
