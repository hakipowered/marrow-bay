extends SceneTree
## Contact frames of raw Meshy death clips (GLBs straight from the rig job),
## to see what each one does before wiring it in.
## xvfb-run -a godot --path . --rendering-driver opengl3 \
##   --script tests/render_death_src.gd -- <glb_dir> <out_dir> [samples]
var dir := ""
var out := ""
var samples := 8
var files: Array = []
var fi := 0
var si := 0
var frames := 0
var cur: Node3D
var ap: AnimationPlayer
var clip := ""
var cam: Camera3D
var wait := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	dir = a[0]
	out = a[1]
	if a.size() > 2:
		samples = int(a[2])
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "glb" and f != "rigged.glb":
			files.append(f)
	files.sort()
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.12, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.3)
	fl.material_override = fm
	world.add_child(fl)
	# a 1 m grid so travel can be read off the frames
	for i in range(-5, 6):
		for axis in 2:
			var l := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(12, 0.004, 0.015) if axis == 0 else Vector3(0.015, 0.004, 12)
			l.mesh = bm
			l.position = Vector3(0, 0.002, i) if axis == 0 else Vector3(i, 0.002, 0)
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.6, 0.6, 0.2) if i == 0 else Color(0.45, 0.45, 0.45)
			l.material_override = lm
			world.add_child(l)
	cam = Camera3D.new()
	cam.fov = 55
	world.add_child(cam)
	cam.look_at_from_position(Vector3(4.6, 2.0, 0.0), Vector3(0, 0.5, -0.6))
	cam.make_current()

func _load(f: String) -> void:
	if cur:
		cur.queue_free()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(dir + "/" + f, st)
	cur = doc.generate_scene(st)
	root.get_child(root.get_child_count() - 1).add_child(cur)
	ap = cur.find_children("*", "AnimationPlayer", true, false)[0]
	clip = ""
	for n in ap.get_animation_list():
		if n != "RESET":
			clip = n
	var a := ap.get_animation(clip)
	var sk: Skeleton3D = cur.find_children("*", "Skeleton3D", true, false)[0]
	for t in a.get_track_count():
		var p := str(a.track_get_path(t))
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and p.ends_with("Hips"):
			var line := ""
			for i in 11:
				var tm := a.length * i / 10.0
				line += " %s" % [a.position_track_interpolate(t, tm)]
			print(f, " ", clip, " len=", snappedf(a.length, 0.01), " hips:", line)
	ap.play(clip)
	ap.pause()

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if cur == null or (si >= samples and wait == 0):
		if cur != null:
			fi += 1
		if fi >= files.size():
			quit(0)
			return false
		_load(files[fi])
		si = 0
		wait = 0
	if wait == 0:
		var a := ap.get_animation(clip)
		var tm := a.length * si / float(samples - 1)
		ap.seek(tm, true)
		wait = 2
		return false
	wait -= 1
	if wait == 0:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%02d.png" % [out, files[fi].get_basename(), si])
		si += 1
	return false
