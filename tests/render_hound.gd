extends SceneTree
## The infected hound in each of its clips, side by side, rendered to PNG.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 --script tests/render_hound.gd -- <out_dir> [lineup|head|boxes|turn]
##   lineup: idle, feed, trot, gallop, lunge (mid-leap), bite (snap), hit, dead
##   head:   close-up of the head (eyes, jaws, blood)
##   boxes:  its hitboxes drawn over it in idle and mid-leap
##   turn:   the idle hound from four sides
var out := "/tmp"
var mode := "lineup"
var t := 0.0
var frames := 0
var models: Array = []
var cam: Camera3D
var done := false

const LINEUP := [
	# label, state, speed, seconds into the state before the shot
	["idle", 0, 0.0, 1.0], ["feed", 7, 0.0, 1.1], ["trot", 2, 2.5, 0.9], ["gallop", 2, 4.0, 0.95],
	["lunge", 3, 0.0, 0.3, true], ["bite", 3, 0.0, 0.43], ["hit", 4, 0.0, 0.15], ["dead", 6, 0.0, 1.6],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		mode = a[1]

func _build() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.04, 0.04, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.46, 0.5)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	floor.mesh = pm
	floor.material_override = StandardMaterial3D.new()
	floor.material_override.albedo_color = Color(0.17, 0.17, 0.18)
	world.add_child(floor)
	var enemy_db = load("res://scripts/enemies/enemy_db.gd")
	var zones: Array = load("res://scripts/enemies/zombie.gd").get_script_constant_map()["HOUND_ZONES"]
	var list: Array = LINEUP
	if mode == "head":
		list = [["idle", 0, 0.0, 1.0]]
	elif mode == "boxes":
		list = [["idle", 0, 0.0, 1.0], ["lunge", 3, 0.0, 0.3, true]]
	elif mode == "turn":
		list = [["idle", 0, 0.0, 1.0], ["idle", 0, 0.0, 1.0], ["idle", 0, 0.0, 1.0], ["idle", 0, 0.0, 1.0]]
	var n := list.size()
	for i in n:
		var e: Array = list[i]
		var holder := Node3D.new()
		holder.name = "Hound%d" % i
		world.add_child(holder)
		holder.position = Vector3((i - (n - 1) / 2.0) * 1.6, 0, 0)
		holder.rotation.y = -PI / 2   # side on, nose to the left
		if mode == "turn":
			holder.rotation.y = -PI / 2 + i * PI / 2
		var m = load("res://scripts/enemies/zombie_model.gd").new()
		m.variant = "hound"
		m.look = "hound"
		m.data = enemy_db.TYPES["hound"]
		holder.add_child(m)
		if mode == "boxes":
			for z in zones:
				var box := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = z[3]
				box.mesh = bm
				var mat := StandardMaterial3D.new()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = {"head": Color(1, 0.2, 0.2, 0.45), "torso": Color(0.2, 1, 0.3, 0.35), "leg": Color(0.3, 0.5, 1, 0.45)}[z[0]]
				box.material_override = mat
				var a := Area3D.new()
				a.position = Vector3(0, z[2], 0)
				a.add_child(box)
				m.attach_hitbox(z[1], a)
		models.append([m, e])
	cam = Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	if mode == "head":
		cam.position = Vector3(1.05, 0.88, 0.6)
		cam.look_at(Vector3(0.6, 0.76, 0.0))
	else:
		var w := n * 1.6
		cam.position = Vector3(0, 1.1, w * 0.52 + 0.6)
		cam.look_at(Vector3(0, 0.45, 0))
	cam.make_current()
	if mode == "head":
		var spot := SpotLight3D.new()
		spot.position = Vector3(1.2, 1.1, 0.9)
		spot.look_at_from_position(spot.position, Vector3(0.62, 0.78, 0))
		spot.light_energy = 1.6
		spot.spot_range = 4.0
		world.add_child(spot)

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		_build()
	if frames <= 3:
		return false
	t += delta
	var shot_at := 0.0
	for pair in models:
		var m = pair[0]
		var e: Array = pair[1]
		shot_at = maxf(shot_at, e[3])
		if e[1] == 6:
			if frames == 5:
				m.die(false)
			continue
		if e.size() > 4 and frames < 12:
			m.animate(2, 4.0, false, false)   # coming in at a gallop
			continue
		if t < e[3] + (8.0 / 30.0 if e.size() > 4 else 0.0):
			m.animate(e[1], e[2], false, false)
		elif m._anim:
			m._anim.pause()
	if not done and t >= shot_at + 0.05:
		done = true
		var path := "%s/hound_%s.png" % [out, mode]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		quit(0)
	return false
