extends SceneTree
## Headless check of how a zombie fight plays (0.6 playtest fixes):
##  1. A shambler's swing winds up, then lands on the strike frame (~0.75 s),
##     not the moment it starts; the survivor flinches, is shoved, stops for a
##     beat and the screen flashes.
##  2. Walking cuts the survivor's flinch short (no sliding in a frozen pose).
##  3. A knife hit during the wind-up breaks the swing off: no damage.
##  4. A runner keeps to its pace (no more sprinting at survivors).
## Prints COMBAT OK, or COMBAT FAIL with the reason.
var frames := 0
var stage := 0
var t := 0.0
var z: Node = null
var p: Node = null
var hp0 := 0.0
var attack_at := -1.0
var hit_at := -1.0
var fails := []
var notes := []
var runner_from := Vector3.ZERO
var shots_dir := ""   # pass "shots <dir>" (with a display) to save frames
var _shot_at := {}

func _shot(tag: String) -> void:
	if shots_dir == "" or _shot_at.has(tag):
		return
	_shot_at[tag] = true
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, tag])

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2 and a[0] == "shots":
		shots_dir = a[1]

func _process(d: float) -> bool:
	frames += 1
	var gs = root.get_node("GameState")
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(gs.level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				p = get_first_node_in_group("players")
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				stage = 2
				frames = 0
		2:
			if frames == 3:
				var lvl = get_first_node_in_group("level")
				var fwd: Vector3 = -p.body.global_transform.basis.z
				lvl.spawn_zombie_synced("TestShambler", p.global_position + fwd * 1.0, "shambler")
				z = lvl.get_node("TestShambler")
				z.look_at(p.global_position, Vector3.UP)
				if shots_dir != "":
					# A side-on camera so the swing isn't hidden behind her.
					var cam := Camera3D.new()
					lvl.add_child(cam)
					var mid: Vector3 = (p.global_position + z.global_position) * 0.5 + Vector3.UP * 1.1
					var side: Vector3 = fwd.cross(Vector3.UP).normalized()
					cam.global_position = mid + side * 3.2 + Vector3.UP * 0.3
					cam.look_at(mid, Vector3.UP)
					cam.fov = 55.0
					cam.current = true
				hp0 = p.hp
				t = 0.0
				stage = 3
		3:
			t += d
			if attack_at < 0 and z.state == z.S.ATTACK:
				attack_at = t
			if attack_at >= 0 and t - attack_at > 0.4:
				_shot("1_windup")
			if hit_at >= 0 and t - hit_at > 0.1:
				_shot("3_flinch_flash")
			if hit_at < 0 and p.hp < hp0:
				hit_at = t
				_shot("2_strike")
				notes.append("swing started %.2fs, landed %.2fs later; hp %d -> %d" % [attack_at, hit_at - attack_at, hp0, p.hp])
				if hit_at - attack_at < 0.6 or hit_at - attack_at > 0.95:
					fails.append("strike timing %.2f s" % (hit_at - attack_at))
				if p.model._current != "hit":
					fails.append("survivor did not flinch (anim %s)" % p.model._current)
				if p._hit_stun <= 0.0:
					fails.append("no hit stun")
				var post = get_first_node_in_group("horror").post_fx
				if post._flash <= 0.1:
					fails.append("no red flash")
				if p._knock.length() < 0.5:
					fails.append("no shove")
				# Walk away: the flinch must give way to walking soon after.
				p.move_input = Vector2(0, 1)
				stage = 4
				t = 0.0
			if t > 4.0:
				fails.append("shambler never landed a hit (state %s)" % z.S.keys()[z.state])
				stage = 9
		4:
			t += d
			if t > 0.08:
				_shot("3_flinch_flash")
			if p.model._current in ["walk", "run", "shoot_walk"]:
				_shot("4_walking_again")
				notes.append("flinch gave way to walking after %.2fs" % t)
				if t > 0.6:
					fails.append("flinch held the legs too long")
				p.move_input = Vector2.ZERO
				stage = 5
				t = 0.0
			elif t > 1.5:
				fails.append("stuck in the hit clip while walking (anim %s)" % p.model._current)
				p.move_input = Vector2.ZERO
				stage = 5
				t = 0.0
		5:
			# Next swing: knife it mid wind-up.
			t += d
			p.global_position = z.global_position + (-z.global_transform.basis.z) * 1.0
			if z.state == z.S.ATTACK and z._attack_t > 0.3:
				hp0 = p.hp
				z.take_hit(12.0, "knife", "torso", -z.global_transform.basis.z * -1.0)
				notes.append("knifed mid-swing: zombie now %s" % z.S.keys()[z.state])
				if z.state != z.S.STAGGER:
					fails.append("knife did not interrupt the swing")
				stage = 6
				t = 0.0
			elif t > 6.0:
				fails.append("no second swing")
				stage = 9
		6:
			t += d
			if t > 0.15:
				_shot("5_zombie_flinch")
			if t >= 0.9:
				if p.hp < hp0 - 0.1:
					fails.append("the broken-off swing still did damage")
				else:
					notes.append("no damage from the broken-off swing")
				z.queue_free()
				var lvl = get_first_node_in_group("level")
				var fwd: Vector3 = -p.body.global_transform.basis.z
				lvl.spawn_zombie_synced("TestRunner", p.global_position + Vector3(12, 0, 0), "runner")
				stage = 7
				t = 0.0
		7:
			t += d
			var r = get_first_node_in_group("level").get_node_or_null("TestRunner")
			if r == null:
				return false
			if t > 0.3 and runner_from == Vector3.ZERO:
				runner_from = r.global_position
			if t > 1.3:
				var v: float = (r.global_position - runner_from).length() / 1.0
				notes.append("runner pace %.2f m/s (survivor walks 2.4, runs 4.6)" % v)
				if v > 2.9:
					fails.append("runner too fast: %.2f" % v)
				stage = 9
		9:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("COMBAT OK")
			else:
				print("COMBAT FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false
