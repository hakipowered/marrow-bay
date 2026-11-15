extends SceneTree
## Contact sheet of a character's acting clips ("talk" library,
## tools/import_talk.gd): four moments of each clip, side view and front, so
## the clips can be checked without a phone.
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 640x480 --script tests/render_talk.gd -- hardass /tmp/talk
## (zegan and obcera load as survivors, with their default outfit.)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var who := a[0] if a.size() > 0 else "hardass"
	var out := a[1] if a.size() > 1 else "/tmp/talk"
	var only: PackedStringArray = a[2].split(",") if a.size() > 2 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.36)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	world.add_child(floor_mi)
	# A chair-height block behind the mark, where the seated clips sit.
	var seat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.46, 0.45)
	seat.mesh = bm
	world.add_child(seat)
	var anim: AnimationPlayer
	var actor: Node3D
	if who in ["zegan", "obcera"]:
		var m := CharacterModel.new()
		m.character = who
		m.customization = root.get_node("GameState").default_customization(who)
		world.add_child(m)
		await _frames(2)
		actor = m
		anim = m.find_children("*", "AnimationPlayer", true, false)[0]
		seat.visible = false
	else:
		var s := StoryActor.new(who)
		world.add_child(s)
		await _frames(2)
		actor = s
		anim = s.find_children("*", "AnimationPlayer", true, false)[0]
		# seat_back is in the rig's space; StoryActor turns the model half
		# round to face -Z, so the seat is at (-x, -z).
		var back: Vector3 = s.seat_back()
		seat.position = Vector3(-back.x, 0.23, -back.z + 0.08)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	cam.fov = 40
	var clips: Array = []
	for c in anim.get_animation_list():
		if str(c).begins_with("talk/") and (only.is_empty() or str(c).trim_prefix("talk/") in only):
			clips.append(str(c))
	print("clips: ", clips)
	for clip in clips:
		var len := anim.get_animation(clip).length
		var row: Array[Image] = []
		for view in [Vector3(4.2, 1.2, 0.0), Vector3(0.0, 1.2, -4.2)]:
			cam.look_at_from_position(view, Vector3(0, 0.95, 0))
			for f in [0.05, 0.35, 0.65, 0.95]:
				anim.play(clip, 0.0)
				anim.seek(len * f, true)
				anim.pause()
				await _frames(3)
				var img := root.get_viewport().get_texture().get_image()
				img.resize(320, 240)
				row.append(img)
		var sheet := Image.create(320 * 4, 240 * 2, false, row[0].get_format())
		for i in row.size():
			sheet.blit_rect(row[i], Rect2i(0, 0, 320, 240), Vector2i((i % 4) * 320, (i / 4) * 240))
		sheet.save_jpg("%s/%s_%s.jpg" % [out, who, clip.trim_prefix("talk/")], 0.8)
		print("sheet ", clip)
	quit(0)
