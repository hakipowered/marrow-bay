extends SceneTree
## Close-up body checks, one picture per cell, for the shaping regions:
##   shape:  <out_dir> shape <character> <outfit> <view> <chest>
##   face:   <out_dir> face <character> <outfit> <view>
##   jiggle: <out_dir> jiggle <character> <outfit> <view>   (writes _still and
##           _moved, the same frozen pose with the chest springs pushed 4 cm up,
##           so the difference shows exactly what the jiggle moves)
## view: front | side | three_quarter. Run under xvfb with opengl3, 640x800.
var f := 0
var cm: CharacterModel
var a: PackedStringArray

func _initialize() -> void:
	a = OS.get_cmdline_user_args()

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		root.size = Vector2i(640, 800)
		cm = CharacterModel.new()
		cm.character = a[2]
		var c: Dictionary = root.get_node("GameState").default_customization(a[2])
		c["outfit"] = a[3]
		if a[1] == "shape":
			# a number sets Chest; "waist=0.1,hips=0.9" sets any sliders
			if "=" in a[5]:
				for kv in a[5].split(","):
					c[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
			else:
				c["chest"] = float(a[5])
		cm.customization = c
		root.add_child(cm)
		cm.rotation_degrees.y = {"front": 180.0, "side": 235.0, "three_quarter": 205.0}[a[4]]
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.85 if a[1] != "face" else 0.36
		root.add_child(cam)
		var top: float = 1.3 if a[2] == "obcera" else 1.38
		if a[1] == "face":
			top = 1.6 if a[2] == "obcera" else 1.7
		if a[1] == "shape" and "=" in a[5]:
			top = 1.05 if a[2] == "obcera" else 1.1
			cam.size = 1.0
		cam.position = Vector3(0, top, 6.0)
		cam.look_at(Vector3(0, top, 0))
		cam.make_current()
		for spec in [[Vector3(-25, 20, 0), 1.1], [Vector3(-10, -40, 0), 0.55], [Vector3(-20, 180, 0), 0.6]]:
			var l := DirectionalLight3D.new()
			l.rotation_degrees = spec[0]
			l.light_energy = spec[1]
			root.add_child(l)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.82, 0.82, 0.83)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
		we.environment.ambient_light_energy = 0.9
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		root.add_child(we)
	if cm and f > 2 and f < 20:
		cm.play("idle", false)
	if a[1] == "face" and f == 24:
		root.get_texture().get_image().save_png("%s/%s_%s_face.png" % [a[0], a[3], a[4]])
		quit(0)
	if a[1] == "shape" and f == 24:
		root.get_texture().get_image().save_png("%s/%s_%s_%s_%s.png" % [a[0], a[3], a[4], a[1], a[5]])
		quit(0)
	if a[1] == "jiggle":
		if f == 20:
			cm._anim.speed_scale = 0.0
			cm.set_process(false)
			cm._update_regions(0.0)
		if f == 24:
			root.get_texture().get_image().save_png("%s/%s_%s_still.png" % [a[0], a[3], a[4]])
			var offs: PackedVector3Array = cm._body_mat.get_shader_parameter("r_offset")
			for i in cm._regions.size():
				if cm._regions[i]["def"].get("slider") == "chest":
					offs[i] = cm._skel.global_transform.basis.inverse() * Vector3(0, 0.04, 0)
			cm._body_mat.set_shader_parameter("r_offset", offs)
		if f == 28:
			root.get_texture().get_image().save_png("%s/%s_%s_moved.png" % [a[0], a[3], a[4]])
			quit(0)
	return false
