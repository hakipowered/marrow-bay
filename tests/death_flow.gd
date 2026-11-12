extends SceneTree
## Headless checks for the 0.7 playtest fixes:
##  1. Her legs follow her real speed: full stick runs, an ankle grab drops
##     her to a walk, aiming walks with the gun up (stance/aim_walk), and the
##     clip's playback speed matches the ground speed.
##  2. The riot cop's shield cracks and breaks off after about four pistol
##     rounds, and he can be hurt once it's gone.
##  3. Solo death: she falls, the game over screen comes up with Continue,
##     and Continue reloads the checkpoint with everything reset.
## Prints DEATH FLOW OK, or DEATH FLOW FAIL with the reasons.
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var riot: Node = null
var fails := []
var notes := []
var first_level: Node = null
var shots_dir := ""   # "shots <dir>" with a display: save frames along the way
var _side: Camera3D = null
var _took := {}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2 and a[0] == "shots":
		shots_dir = a[1]

func _shot(tag: String, side := false) -> void:
	if shots_dir == "":
		return
	if side:
		if _side == null:
			_side = Camera3D.new()
			get_first_node_in_group("level").add_child(_side)
		var fwd: Vector3 = -p.body.global_transform.basis.z
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		_side.global_position = p.global_position + right * 2.6 + fwd * 0.6 + Vector3.UP * 1.3
		_side.look_at(p.global_position + Vector3.UP * 1.0, Vector3.UP)
		_side.current = true
		await process_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, tag])
	if side and _side:
		_side.current = false
		p.camera.current = true

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and stage < 20 and cs and cs.active:
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
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				p.move_input = Vector2(0, -1)
				p.running = true
				stage = 2
				t = 0.0
		2:
			t += d
			if t > 0.6:
				_check_move("full stick", "run", 4.0)
				p.slowed_for = 3.0
				stage = 3
				t = 0.0
		3:
			t += d
			if t > 0.5:
				_check_move("ankle grabbed", "walk", 1.6)
				p.slowed_for = 0.0
				p.aiming = true
				stage = 4
				t = 0.0
		4:
			t += d
			if t > 0.6:
				_shot("1_aim_walk", true)
				_check_move("aiming", "walk", 1.7)
				if p.model._current != "stance/aim_walk":
					fails.append("aim walk clip is %s" % p.model._current)
				p.aiming = false
				p.running = false
				p.move_input = Vector2.ZERO
				stage = 5
				t = 0.0
		5:
			t += d
			if t > 0.3:
				var lvl = get_first_node_in_group("level")
				var fwd: Vector3 = -p.body.global_transform.basis.z
				lvl.spawn_zombie_synced("TestRiot", p.global_position + fwd * 4.0, "riot")
				riot = lvl.get_node("TestRiot")
				riot.look_at(p.global_position, Vector3.UP)
				stage = 6
				t = 0.0
		6:
			t += d
			if t > 0.2:
				var hp0: float = riot.hp
				var shots := 0
				var dir: Vector3 = (riot.global_position - p.global_position).normalized()
				while riot._shield_hp > 0.0 and shots < 20:
					riot.take_hit(26.0, "p9", "torso", dir)
					shots += 1
					if shots == 3:
						_shot("2_shield_cracked")
				notes.append("riot shield broke after %d pistol rounds (riot hp untouched: %s)" % [shots, str(is_equal_approx(riot.hp, hp0))])
				if shots > 5:
					fails.append("shield took %d rounds" % shots)
				if riot.state != riot.S.STAGGER:
					fails.append("riot not reeling after the shield broke")
				riot.take_hit(26.0, "p9", "torso", dir)
				if riot.hp >= hp0:
					fails.append("no damage after the shield broke")
				stage = 7
				t = 0.0
		7:
			t += d
			if t > 0.8:
				riot.queue_free()
				first_level = get_first_node_in_group("level")
				p.hp = 5.0
				p.apply_damage(20.0, null)
				if not p.dead:
					fails.append("solo death did not start (downed %s)" % str(p.downed))
				stage = 8
				t = 0.0
		8:
			t += d
			var lvl = get_first_node_in_group("level")
			if t > 0.3 and not _took.has("fall"):
				_took["fall"] = true
				_shot("3_falling")
			if t > 0.9 and not _took.has("cam"):
				_took["cam"] = true
				_shot("4_death_cam")
			if t > 6.5 and not _took.has("go"):
				_took["go"] = true
				_shot("5_game_over")
			if t > 0.5 and t < 0.6:
				if not lvl.game_over:
					fails.append("no game over")
				if p.model._current != "knockdown":
					fails.append("no death fall (anim %s)" % p.model._current)
			if t > 7.0:
				var go: Node = null
				for c in lvl.get_children():
					if c.has_method("show_votes"):
						go = c
				if go == null:
					fails.append("no game over screen")
					stage = 30
				else:
					notes.append("game over screen: \"%s\" / \"%s\", buttons shown %s" % [go._title.text, go._line.text, str(go._buttons.visible)])
					if not go._buttons.visible:
						fails.append("Continue never appeared")
					go._on_continue()
					stage = 9
					t = 0.0
		9:
			t += d
			var lvl = get_first_node_in_group("level")
			if lvl != null and lvl != first_level and t > 1.0:
				var np = get_first_node_in_group("players")
				if np == null:
					return false
				notes.append("continued: hp %d, dead %s, time scale %.2f" % [np.hp, str(np.dead), Engine.time_scale])
				if np.dead or np.downed or np.hp <= 0:
					fails.append("still dead after Continue")
				if Engine.time_scale != 1.0:
					fails.append("slow motion left on")
				if root.get_node("Music").override_track != "":
					fails.append("music left silenced")
				stage = 30
			elif t > 8.0:
				fails.append("Continue did not reload")
				stage = 30
		30:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("DEATH FLOW OK")
			else:
				print("DEATH FLOW FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _check_move(what: String, want_anim: String, want_speed: float) -> void:
	var gs: float = p.sync_speed
	var scale: float = p.model._anim.speed_scale if p.model._anim else 1.0
	notes.append("%s: %.2f m/s, anim %s (%s) at x%.2f" % [what, gs, p.sync_anim, p.model._current, scale])
	if p.sync_anim != want_anim:
		fails.append("%s plays %s" % [what, p.sync_anim])
	if absf(gs - want_speed) > 0.4:
		fails.append("%s speed %.2f, expected %.1f" % [what, gs, want_speed])
	if scale < 0.95 and gs > 1.0:
		fails.append("%s clip not sped up to match (x%.2f)" % [what, scale])
