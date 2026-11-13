extends SceneTree
## Renders the chapter 2 boss (WardenBoss) from four sides, with his
## truncheon, shield, the growth on his back and (optionally) his hitboxes.
##   godot --path . --rendering-driver opengl3 --script tests/render_boss.gd -- <out_prefix> [clip] [time] [hitboxes 0|1] [views e.g. front,back]
## Writes <out_prefix>_front.png, _right.png, _back.png, _left.png.
var f := 0
var boss: Node3D
var cam: Camera3D
var views := [["front", 0.0], ["right", 90.0], ["back", 180.0], ["left", 270.0]]
var vi := 0

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		boss = load("res://scripts/enemies/warden_boss.gd").new()
		boss.name = "Warden"
		root.add_child(boss)
		var floor := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(8, 8)
		floor.mesh = pm
		root.add_child(floor)
		cam = Camera3D.new()
		root.add_child(cam)
		cam.fov = 45
		cam.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 150, 0)
		sun.light_energy = 1.3
		root.add_child(sun)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.3, 0.32, 0.36)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
		root.add_child(we)
	if f == 3 and a.size() > 4:
		views = views.filter(func(v): return v[0] in a[4].split(","))
	if f == 6:
		var anim: AnimationPlayer = boss.actor._anim
		var clip := a[1] if a.size() > 1 else "idle"
		anim.play(clip, 0.0)
		if a.size() > 2:
			anim.seek(float(a[2]), true)
		anim.pause()
		if a.size() > 3 and a[3] == "1":
			for h in boss._hitboxes:
				var cs: CollisionShape3D = h.get_child(0)
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = (cs.shape as BoxShape3D).size
				mi.mesh = bm
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(1, 0.2, 0.9, 0.35) if h.get_meta("hit_zone") != "wound" else Color(1, 1, 0, 0.5)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.material_override = m
				h.add_child(mi)
	if f >= 10 and (f - 10) % 6 == 0:
		if vi > 0:
			root.get_texture().get_image().save_png("%s_%s.png" % [a[0], views[vi - 1][0]])
		if vi >= views.size():
			quit(0)
			return false
		var yaw := deg_to_rad(views[vi][1])
		# He faces -Z: the front view looks at him from -Z.
		cam.position = Vector3(-sin(yaw) * 4.2, 1.25, -cos(yaw) * 4.2)
		cam.look_at(Vector3(0, 1.05, 0))
		vi += 1
	return false
