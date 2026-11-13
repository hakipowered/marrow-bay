extends SceneTree
## Music in the level plays only for danger she can meet (0.10 feedback: a
## song played while exploring the reading room and the diner street, and
## she went looking for a threat that wasn't there; it was the sleeping
## Tallyman behind the reading-room glass).
##  1. Exploring the reading room, the hall's west end and the diner street
##     with the Tallyman asleep: no music.
##  2. Infected chasing her from behind a wall: no music.
##  3. A brute and two more chasing her in plain sight: the action track.
##  4. The Tallyman awake and on her: the action track.
## Prints MUSIC QUIET OK, or MUSIC QUIET FAIL with the reasons.
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var lvl: Node = null
var music: Node = null
var fails := []
var notes := []
var spots := [Vector3(-24, 0.05, -9), Vector3(-20, 0.05, -2), Vector3(-14, 0.05, 4), Vector3(7, 0.05, -26)]
var spot := 0
var heard := {}
var zs := []
var _wall: StaticBody3D = null
var start := Vector3.ZERO

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
				music = root.get_node("Music")
				var st = get_first_node_in_group("stalker")
				if st == null or st.active:
					fails.append("expected a sleeping Tallyman in the level")
				_clear()
				stage = 2
				t = 0.0
		# --- 1. exploring near the sleeping Tallyman, and the diner street ---
		2:
			_clear()
			p.global_position = spots[spot]
			p.velocity = Vector3.ZERO
			t += d
			var tr: String = music.current_track()
			if tr != "":
				heard[tr] = true
			if t > 4.0:
				notes.append("exploring at %s: threat %.1f, track '%s'" % [str(spots[spot]), music.threat, tr])
				if not heard.is_empty():
					fails.append("music %s while exploring at %s" % [str(heard.keys()), str(spots[spot])])
				heard.clear()
				spot += 1
				t = 0.0
				if spot >= spots.size():
					stage = 3
		# --- 2. a pack behind a wall -------------------------------------
		3:
			start = Vector3(-8, 0.05, 8)   # the Great Hall
			p.global_position = start
			var fwd := Vector3(0, 0, -1)
			_wall = _make_wall(start + fwd * 1.5, fwd)
			for i in 3:
				var at: Vector3 = start + fwd * 5.0 + Vector3(i - 1, 0, 0)
				lvl.spawn_zombie_synced("WallZ%d" % i, at, "brute" if i == 1 else "shambler")
				zs.append(lvl.get_node("WallZ%d" % i))
			t = 0.0
			stage = 4
		4:
			t += d
			p.global_position = start
			for z in zs:
				if is_instance_valid(z):
					z.global_position.z = minf(z.global_position.z, start.z - 4.5)   # held behind the wall, out of reach
					z.target = p
					if z.state != z.S.ATTACK:
						z.state = z.S.CHASE
			if music.current_track() != "":
				heard[music.current_track()] = true
			if t > 4.0:
				notes.append("brute and two shamblers behind a wall: threat %.1f, track '%s'" % [music.threat, music.current_track()])
				if not heard.is_empty():
					fails.append("music %s for infected behind a wall" % str(heard.keys()))
				heard.clear()
				_wall.queue_free()
				_wall = null
				t = 0.0
				stage = 5
		# --- 3. the same pack in plain sight -------------------------------
		5:
			t += d
			p.global_position = start
			for z in zs:
				if is_instance_valid(z):
					z.global_position.z = minf(z.global_position.z, start.z - 4.5)
					z.target = p
					if z.state != z.S.ATTACK:
						z.state = z.S.CHASE
			if t > 3.0:
				notes.append("brute and two shamblers in sight: threat %.1f, track '%s'" % [music.threat, music.current_track()])
				if music.current_track() != "action":
					fails.append("no action music for a brute in plain sight")
				_clear()
				t = 0.0
				stage = 6
		# --- 4. the Tallyman awake ----------------------------------------
		6:
			var st = get_first_node_in_group("stalker")
			st.active = true
			st.visible = true
			p.global_position = st.global_position + Vector3(4, 0, 0)
			music.enter_game()   # start from silence
			t = 0.0
			stage = 7
		7:
			t += d
			var st = get_first_node_in_group("stalker")
			p.global_position = st.global_position + Vector3(4, 0, 0)
			if t > 3.0:
				notes.append("Tallyman awake 4 m away: threat %.1f, track '%s'" % [music.threat, music.current_track()])
				if music.current_track() != "action":
					fails.append("no music with the Tallyman awake and on her")
				stage = 8
		8:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("MUSIC QUIET OK")
			else:
				print("MUSIC QUIET FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _clear() -> void:
	for zz in get_nodes_in_group("zombies"):
		zz.queue_free()
	zs.clear()

func _make_wall(at: Vector3, normal: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(8.0, 3.0, 0.3)
	cs.shape = b
	w.add_child(cs)
	lvl.add_child(w)
	w.global_position = at + Vector3.UP * 1.5
	w.look_at(w.global_position + normal, Vector3.UP)
	return w
