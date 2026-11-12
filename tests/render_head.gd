extends SceneTree
## Close-ups of a survivor's head from several angles in one picture, for
## checking the face, hairline, neck seam and ponytail.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1500x500 \
##   --script tests/render_head.gd -- <character> <outfit> <out.png> [low]
## "low" frames the neck and upper back instead of the face. Angles go
## from the front (0) round her left side to behind her.
var f := 0
var cm: CharacterModel
var cams: Array[Camera3D] = []
var vps: Array[SubViewport] = []
const ANGLES := [0.0, 35.0, 80.0, 150.0, 215.0]

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		root.size = Vector2i(1500, 500)
		cm = CharacterModel.new()
		cm.character = a[0]
		var c: Dictionary = root.get_node("GameState").default_customization(a[0])
		c["outfit"] = a[1]
		cm.customization = c
		root.add_child(cm)
		cm.rotation_degrees.y = 180.0
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.16, 0.15, 0.16)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
		we.environment.ambient_light_energy = 0.7
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		root.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-25, 25, 0)
		key.light_energy = 1.0
		root.add_child(key)
		var back := DirectionalLight3D.new()
		back.rotation_degrees = Vector3(-20, 180, 0)
		back.light_energy = 0.5
		root.add_child(back)
		for i in ANGLES.size():
			var vp := SubViewport.new()
			vp.size = Vector2i(300, 500)
			vp.world_3d = root.world_3d
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var cam := Camera3D.new()
			cam.fov = 30.0
			vp.add_child(cam)
			cams.append(cam)
			vps.append(vp)
	if f == 6:
		var low := a.size() > 3 and a[3] == "low"
		var head: Vector3 = cm.bone_position("Head")
		var target := head + Vector3(0, -0.12 if low else 0.07, 0)
		var dist := 1.0 if low else 0.62
		for i in ANGLES.size():
			var ang := deg_to_rad(ANGLES[i])
			cams[i].position = target + Vector3(sin(ang), 0.05, cos(ang)) * dist
			cams[i].look_at(target)
	if f == 30:
		var out := Image.create(300 * ANGLES.size(), 500, false, Image.FORMAT_RGBA8)
		for i in vps.size():
			var img := vps[i].get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			out.blit_rect(img, Rect2i(0, 0, 300, 500), Vector2i(300 * i, 0))
		out.save_png(a[2])
		quit(0)
	return false
