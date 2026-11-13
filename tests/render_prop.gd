extends SceneTree
## Renders an imported model (a prop, weapon or any GLB) framed to fit, for a look.
##   godot --path . --rendering-driver opengl3 --script tests/render_prop.gd -- <res://path.glb> <out.png> [yaw_deg] [pitch_deg]
var f := 0
func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		var n: Node3D = load(a[0]).instantiate()
		root.add_child(n)
		n.rotation_degrees.y = float(a[2]) if a.size() > 2 else 30.0
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var pitch := deg_to_rad(float(a[3]) if a.size() > 3 else 20.0)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.fov = 40
		cam.position = c + Vector3(0, sin(pitch), -cos(pitch)) * r / tan(deg_to_rad(20.0)) * 1.1
		cam.look_at(c)
		cam.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 150, 0)
		sun.light_energy = 1.3
		root.add_child(sun)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.3, 0.32, 0.35)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
		root.add_child(we)
		print("size ", box.size)
	if f == 12:
		root.get_texture().get_image().save_png(a[1])
		quit(0)
	return false
