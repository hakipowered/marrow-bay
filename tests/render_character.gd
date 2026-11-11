extends SceneTree
## Renders one survivor alone for checking body shape and clips.
## -- <id> <out.png> <anim> <yaw_deg> [slider=value ...]
var f := 0
var cm: CharacterModel
func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		cm = CharacterModel.new()
		cm.character = a[0]
		var c: Dictionary = root.get_node("GameState").default_customization(a[0])
		for kv in a.slice(4):
			c[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
		cm.customization = c
		root.add_child(cm)
		cm.rotation_degrees.y = float(a[3])
		cm.play(a[2], false)
		var cam := Camera3D.new()
		cam.fov = 35
		root.add_child(cam)
		cam.position = Vector3(0, 1.05, 3.6)
		cam.look_at(Vector3(0, 0.95, 0))
		cam.make_current()
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-30, 35, 0)
		key.light_energy = 1.4
		root.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-20, 200, 0)
		rim.light_energy = 0.8
		root.add_child(rim)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.16, 0.17, 0.2)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.4, 0.4, 0.45)
		we.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		root.add_child(we)
	if f == 40:
		root.get_texture().get_image().save_png(a[1])
		quit(0)
	return false
