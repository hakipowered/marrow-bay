extends SceneTree
## Renders one model on its own for a look: -- <model> <out.png> <cam x,y,z> <target x,y,z>
func _initialize() -> void:
	pass

var f := 0
func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		var node: Node3D = (load("res://assets/polyhaven/models/%s/%s.gltf" % [a[0], a[0]]) as PackedScene).instantiate()
		root.add_child(node)
		var cam := Camera3D.new()
		root.add_child(cam)
		var c := a[2].split_floats(",")
		var t := a[3].split_floats(",")
		cam.position = Vector3(c[0], c[1], c[2])
		cam.look_at(Vector3(t[0], t[1], t[2]))
		cam.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		root.add_child(sun)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.3, 0.35, 0.4)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
		root.add_child(we)
	if f == 12:
		root.get_texture().get_image().save_png(a[1])
		quit(0)
	return false
