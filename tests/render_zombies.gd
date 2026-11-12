extends SceneTree
## Line-up of rigged infected in different looks and clips, rendered to PNG.
## xvfb-run godot --path . --rendering-driver vulkan --script tests/render_zombies.gd -- <out_dir> [frame_seconds]
var out := "/tmp"
var t := 0.0
var frames := 0
var models: Array = []
var cam: Camera3D
var shots := [0.6, 1.4]
var shot := 0
var close_at := -1

const LINEUP := [
	# look, variant, state, speed
	["office", "shambler", "IDLE", 0.0],
	["mechanic", "shambler", "WANDER", 0.7],
	["cop", "shambler", "ATTACK", 0.0],
	["jogger", "runner", "CHASE", 4.5],
	["burnt", "burner", "CHASE", 0.8],
	["spitter", "spitter", "PINNING", 0.0],
	["office", "crawler", "CHASE", 0.5],
	["nurse", "shambler", "DEAD", 0.0],
]

const S := {"IDLE": 0, "WANDER": 1, "CHASE": 2, "ATTACK": 3, "STAGGER": 4, "DEAD": 6, "PINNING": 10, "CHARGE": 11}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		close_at = int(a[1])

## Built a few frames in, once the autoloads exist (the enemy scripts use them).
func _build() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.36, 0.42)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	floor.mesh = pm
	floor.material_override = StandardMaterial3D.new()
	floor.material_override.albedo_color = Color(0.2, 0.2, 0.2)
	world.add_child(floor)
	var enemy_db = load("res://scripts/enemies/enemy_db.gd")
	for i in LINEUP.size():
		var e: Array = LINEUP[i]
		var holder := Node3D.new()
		holder.name = "Z%d" % i
		world.add_child(holder)
		holder.position = Vector3((i - (LINEUP.size() - 1) / 2.0) * 1.5, 0, 0)
		holder.rotation.y = PI   # face the camera (enemies look down -Z)
		var m = load("res://scripts/enemies/zombie_model.gd").new()
		m.variant = e[1]
		m.look = e[0]
		m.data = enemy_db.TYPES.get(e[1], {})
		holder.add_child(m)
		models.append([m, e])
	cam = Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	cam.position = Vector3(0, 1.6, 9.5)
	cam.look_at(Vector3(0, 0.9, 0))
	if close_at >= 0:
		var x: float = (close_at - (LINEUP.size() - 1) / 2.0) * 1.5
		cam.position = Vector3(x + 0.75, 1.55, 2.6)
		cam.look_at(Vector3(x + 0.75, 1.15, 0))
	cam.make_current()

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		_build()
	if frames <= 3:
		return false
	t += delta
	for pair in models:
		var m = pair[0]
		var e: Array = pair[1]
		if e[2] == "DEAD":
			if frames == 6:
				m.die(false)
			continue
		m.animate(S[e[2]], e[3], false, false)
	if shot < shots.size() and t >= shots[shot]:
		root.get_texture().get_image().save_png("%s/zombies_%s%d.png" % [out, "" if close_at < 0 else "c%d_" % close_at, shot])
		print("saved zombies_", shot)
		shot += 1
	if shot >= shots.size():
		quit(0)
	return false
