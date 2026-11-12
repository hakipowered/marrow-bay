extends SceneTree
## Story test (solo). Starts the hub, checks the intro starts by itself, then
## walks into each story trigger and checks the scene runs and leaves the world
## in the right state.
##   godot --headless --path . --script tests/story_test.gd -- skip
##       skips each scene a few seconds in (fast)
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/story_test.gd -- full <out_dir>
##       plays every scene to the end and saves a frame every 1.5 s of the
##       in-engine shots to <out_dir>
var mode := "skip"
var out := ""
var cs: Node
var gs: Node
var t0 := 0
var step := 0
var shot_t := 0.0
var shots := 0
var failures := []

const SCENES := [
	["gates", Vector3(0.0, 0.1, -16.6)],
	["warden", Vector3(13.4, 0.1, 2.6)],
	["glass", Vector3(-15.8, 0.1, 6.5)],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		mode = a[0]
	if a.size() > 1:
		out = a[1]
		DirAccess.make_dir_recursive_absolute(out)
	t0 = Time.get_ticks_msec()

func _secs() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0

func _all_zombies_shown() -> bool:
	for z in get_nodes_in_group("zombies"):
		if not z.visible:
			return false
	return root.get_node("Cutscenes")._hidden.is_empty()

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failures.append(what)

var _wait_until := 0.0
var _scene_i := 0
var _scene_start := 0.0

func _process(delta: float) -> bool:
	if _secs() > 900.0:
		print("TIMEOUT")
		quit(1)
	if cs == null and root.has_node("Cutscenes"):
		cs = root.get_node("Cutscenes")
		gs = root.get_node("GameState")
	_maybe_shot(delta)
	match step:
		0:
			if _secs() > 0.2:
				gs.reset_run()
				root.get_node("Net").start_solo("zegan")
				change_scene_to_file(gs.level_path)
				step = 1
				_wait_until = _secs() + 2.0
		1:
			if _secs() > _wait_until:
				print("intro:")
				_check(cs.active and cs.current == "intro", "intro starts on its own")
				_check(cs._video.visible, "intro film is on screen")
				var p = get_first_node_in_group("players")
				_check(p.input_locked, "player can't move during the scene")
				print("  infected kept out of shot: ", root.get_node("Cutscenes")._hidden.size())
				step = 2
				_wait_until = _secs() + (4.0 if mode == "skip" else 9999.0)
		2:
			if mode == "full" and cs._video.visible and int(_secs()) % 10 == 0 and _secs() - _scene_start > 1.0:
				_scene_start = _secs()
				print("  video at ", snappedf(cs._video.stream_position, 0.1), " s, playing ", cs._video.is_playing())
			if mode == "skip" and _secs() > _wait_until:
				print("  video at ", snappedf(cs._video.stream_position, 0.1), " s after ~4 s")
				_check(cs._video.stream_position > 1.0, "the video clock is running")
				cs._on_skip_pressed()
			if not cs.active:
				step = 3
				_wait_until = _secs() + 1.5
		3:
			if _secs() > _wait_until:
				var p = get_first_node_in_group("players")
				_check(gs.has_flag("story_intro"), "intro flag set")
				_check(gs.world_flags.get("objective", "") != "", "objective set: " + str(gs.world_flags.get("objective", "")))
				_check(not p.input_locked and not p.cutscene_pose, "player released")
				_check(get_viewport_camera() == p.camera, "player camera back")
				_check(_all_zombies_shown(), "zombies back in view after the intro")
				var moving := true
				for z in get_nodes_in_group("zombies"):
					moving = moving and z.is_physics_processing()
				_check(moving, "zombies moving again after the intro")
				step = 4
		4:
			# Walk into the next story trigger (with the infected held still,
			# since an infected chasing you holds a scene back).
			if _scene_i >= SCENES.size():
				step = 10
				return false
			for z in get_nodes_in_group("zombies"):
				z.set_physics_process(false)
				z.state = 0
			var sc: Array = SCENES[_scene_i]
			print(sc[0], ":")
			var p = get_first_node_in_group("players")
			p.global_position = sc[1]
			step = 5
			_wait_until = _secs() + 3.0
		5:
			var sc: Array = SCENES[_scene_i]
			if cs.active:
				_check(cs.current == sc[0], "scene '%s' started" % sc[0])
				_scene_start = _secs()
				_wait_until = _secs() + (3.0 if mode == "skip" else 9999.0)
				step = 6
			elif _secs() > _wait_until:
				_check(false, "scene '%s' started" % sc[0])
				_scene_i += 1
				step = 4
		6:
			if _secs() > _wait_until:
				cs._on_skip_pressed()
			if not cs.active:
				var sc: Array = SCENES[_scene_i]
				print("  ran for ", snappedf(_secs() - _scene_start, 0.1), " s")
				_check(gs.has_flag("story_" + sc[0]), "flag story_%s" % sc[0])
				if sc[0] == "warden":
					var p = get_first_node_in_group("players")
					_check(p.inventory.key_items.has("vault_card"), "got the vault key card")
					var h = current_scene.find_child("WardenHardass", true, false)
					_check(h != null and h.global_position.distance_to(Vector3(18.9, 0, 6.0)) < 0.3, "Hardass moved to his corner")
				if sc[0] == "glass":
					_check(current_scene.get_node("Story")._tally == null, "Tallyman puppet removed")
				_check(_all_zombies_shown(), "zombies back in view after '%s'" % sc[0])
				_scene_i += 1
				step = 7
				_wait_until = _secs() + 1.0
		7:
			if _secs() > _wait_until:
				step = 4
		10:
			print("objective now: ", gs.world_flags.get("objective", ""))
			print("STORY OK" if failures.is_empty() else "STORY FAILED: " + str(failures))
			quit(0 if failures.is_empty() else 1)
	return false

func get_viewport_camera() -> Camera3D:
	return root.get_viewport().get_camera_3d()

func _maybe_shot(delta: float) -> void:
	if out == "" or cs == null or not cs.active or cs._video.visible:
		return
	shot_t += delta
	if shot_t < 1.5:
		return
	shot_t = 0.0
	shots += 1
	var img := root.get_viewport().get_texture().get_image()
	img.save_jpg("%s/%s_%03d.jpg" % [out, cs.current, shots], 0.8)
