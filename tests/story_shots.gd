extends SceneTree
## Storyboard of the in-engine cutscene shots: stages each story scene, puts a
## camera on every "cam" step of it and saves a frame, so the framing can be
## checked without a phone (real-time playback under software rendering is
## too slow to catch every shot).
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 1280x720 --script tests/story_shots.gd -- <out_dir> [scene,scene]
## (Vulkan, e.g. Mesa lavapipe: the Compatibility renderer has no screen
## texture, so the frosted pane renders black there.)
var out := "/tmp/story_shots"
var only: PackedStringArray = []

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		only = a[1].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	await _frames(3)
	var gs = root.get_node("GameState")
	gs.reset_run()
	# Mark the scenes as seen so nothing starts by itself.
	for f in ["story_intro", "story_gates", "story_warden", "story_glass"]:
		gs.set_flag(f)
	root.get_node("Net").start_solo("zegan")
	change_scene_to_file(gs.level_path)
	await _frames(40)
	for z in get_nodes_in_group("zombies"):
		z.set_physics_process(false)
	for h in get_nodes_in_group("hud"):
		h.visible = false
	var story = current_scene.get_node("Story")
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.make_current()
	for id in ["intro", "gates", "warden", "glass"]:
		if not only.is_empty() and not (id in only):
			continue
		var n := 0
		var steps: Array = story.cutscene(id)
		root.get_node("Cutscenes").hide_near_cameras(steps)
		for s in steps:
			match s.get("do", ""):
				"call":
					story.callv(s["fn"], s.get("args", []))
					await create_timer(0.3).timeout
				"wait":
					await create_timer(minf(float(s.get("t", 1.0)), 3.0)).timeout
				"say":
					await create_timer(0.6).timeout
				"cam":
					var at: Vector3 = s["pos"]
					var look: Vector3 = s["look"]
					cam.fov = float(s.get("fov", cam.fov))
					cam.global_transform = Transform3D(Basis(), at).looking_at(look, Vector3.UP)
					await _frames(6)
					n += 1
					var img := root.get_viewport().get_texture().get_image()
					img.save_jpg("%s/%s_%02d.jpg" % [out, id, n], 0.85)
					print("shot ", id, " ", n, " t=", s.get("t", 0.0))
		story._clear_scene_bits()
		for p in get_nodes_in_group("players"):
			p.cutscene_pose = false
	print("SHOTS DONE")
	quit(0)
