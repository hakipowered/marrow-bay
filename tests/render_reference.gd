extends SceneTree
## Renders a survivor head to toe in the rest A-pose on a plain studio
## backdrop, front or back, for outfit concept references and previews.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1024x1536 \
##   --script tests/render_reference.gd -- <id> <out.png> <front|back|three_quarter> [outfit] [anim] [slider=value ...]
var f := 0
var cm: CharacterModel

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		root.size = Vector2i(1024, 1536)
		cm = CharacterModel.new()
		cm.character = a[0]
		var c: Dictionary = root.get_node("GameState").default_customization(a[0])
		if a.size() > 3 and a[3] != "":
			c["outfit"] = a[3]
		for kv in a.slice(5):
			c[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
		cm.customization = c
		root.add_child(cm)
		var view: String = a[2]
		cm.rotation_degrees.y = {"front": 180.0, "back": 0.0, "three_quarter": 215.0}.get(view, 0.0)
		if a.size() > 4 and a[4] != "":
			cm.play(a[4], false)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.0
		root.add_child(cam)
		cam.position = Vector3(0, 0.92, 6.0)
		cam.look_at(Vector3(0, 0.92, 0))
		cam.make_current()
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-25, 20, 0)
		key.light_energy = 1.1
		root.add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-10, -40, 0)
		fill.light_energy = 0.55
		root.add_child(fill)
		var back := DirectionalLight3D.new()
		back.rotation_degrees = Vector3(-20, 180, 0)
		back.light_energy = 0.6
		root.add_child(back)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.82, 0.82, 0.83)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
		we.environment.ambient_light_energy = 0.9
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		root.add_child(we)
	if f == 30:
		root.get_texture().get_image().save_png(a[1])
		quit(0)
	return false
