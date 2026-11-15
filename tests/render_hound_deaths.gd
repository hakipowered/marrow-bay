extends SceneTree
## The hound's death clips as contact sheets: one PNG per clip, ten moments
## of the fall in two rows, through the game's own renderer and the clip as
## imported (hound_anims.res). The camera follows the body, so a skid stays
## in frame.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 480x360 --script tests/render_hound_deaths.gd -- <out_dir> [clip,clip...] [side|front|q34|top]
var out := "/tmp"
var clips: PackedStringArray = []
var view := "q34"
const TIMES := [0.0, 0.2, 0.45, 0.65, 0.8, 1.0, 1.3, 1.6, 2.2, 3.0]
const COLS := 5
var frames := 0
var world: Node3D
var cam: Camera3D
var m: Node3D
var sk: Skeleton3D
var _clip := 0
var _k := 0
var _wait := 0
var _sheet: Image = null

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1 and a[1] != "-":
		clips = a[1].split(",")
	if a.size() > 2:
		view = a[2]

func _build() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	floor.material_override = StandardMaterial3D.new()
	floor.material_override.albedo_color = Color(0.2, 0.2, 0.21)
	world.add_child(floor)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 45
	m = load("res://scripts/enemies/zombie_model.gd").new()
	m.variant = "hound"
	m.look = "hound"
	m.data = load("res://scripts/enemies/enemy_db.gd").get_type("hound")
	world.add_child(m)

func _aim() -> void:
	var c := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine2"))).origin
	c.y = 0.3
	var dirs := {"side": Vector3(1, 0.15, 0), "front": Vector3(0, 0.3, -1), "q34": Vector3(0.75, 0.5, -0.75), "top": Vector3(0.01, 1, 0.2)}
	cam.position = c + (dirs.get(view, dirs["q34"]) as Vector3).normalized() * 2.6
	cam.look_at(c, Vector3.UP)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		_build()
		if clips.is_empty():
			clips = ["death", "death_left", "death_slump", "death_slump_left", "death_collapse", "death_collapse_left"]
	if frames < 4:
		return false
	if sk == null:
		sk = m.find_children("*", "Skeleton3D", true, false)[0]
	if _clip >= clips.size():
		quit(0)
		return true
	var ap: AnimationPlayer = m._anim
	if _wait == 0:
		ap.play(clips[_clip], 0.0)
		ap.seek(minf(TIMES[_k], ap.current_animation_length), true)
		ap.pause()
		_aim()
	elif _wait == 3:
		var img := root.get_viewport().get_texture().get_image()
		if _sheet == null:
			_sheet = Image.create(img.get_width() * COLS, img.get_height() * ceili(TIMES.size() / float(COLS)), false, img.get_format())
		_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((_k % COLS) * img.get_width(), (_k / COLS) * img.get_height()))
		_k += 1
		_wait = -1
		if _k >= TIMES.size():
			_sheet.save_png("%s/hound_%s_%s.png" % [out, clips[_clip], view])
			print("saved ", clips[_clip])
			_sheet = null
			_k = 0
			_clip += 1
	_wait += 1
	return false
