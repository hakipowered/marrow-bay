extends SceneTree
## Renders every outfit of both survivors: the rest pose from the front and
## from behind, plus a clip pose from three-quarters, one PNG each.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 768x1152 \
##   --script tests/render_outfits.gd -- <out_dir> [clip] [character:outfit ...]
var f := 0
var jobs: Array = []
var cm: CharacterModel
var out := "/tmp"
var clip := "idle"   # with aiming on: the aim pose
var step := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "/tmp"
	clip = a[1] if a.size() > 1 else "idle"
	var only := a.slice(2)
	for c in ["zegan", "obcera"]:
		for o in CharacterModel.outfits(c):
			if only.is_empty() or "%s:%s" % [c, o] in only:
				for view in [["front", 180.0, ""], ["back", 0.0, ""], ["pose", 215.0, clip]]:
					jobs.append([c, o, view[0], view[1], view[2]])
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
	we.environment.background_color = Color(0.2, 0.2, 0.22)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	we.environment.ambient_light_energy = 0.8
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(we)

func _process(_d: float) -> bool:
	f += 1
	if jobs.is_empty():
		quit(0)
		return false
	var j: Array = jobs[0]
	if step == 0:
		cm = CharacterModel.new()
		cm.character = j[0]
		var c: Dictionary = root.get_node("GameState").default_customization(j[0])
		c["outfit"] = j[1]
		cm.customization = c
		root.add_child(cm)
		cm.rotation_degrees.y = j[3]
		if j[4] != "":
			cm.play(j[4], true)
	step += 1
	if step == 24:
		root.get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, j[0], j[1], j[2]])
		cm.queue_free()
		jobs.pop_front()
		step = 0
	return false
