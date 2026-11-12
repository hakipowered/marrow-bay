extends SceneTree
## Renders a few views of the hub to PNG (for checking the look without a phone).
## xvfb-run godot --path . --rendering-driver opengl3 --script tests/screenshots.gd -- <out_dir>
var frames := 0
var shots := [
	["street", Vector3(-4, 1.7, -20), Vector3(14, 1.2, -27)],
	["street_signs", Vector3(-10, 1.7, -22), Vector3(-4, 2.8, -29.5)],
	["street_east", Vector3(-14, 1.8, -24), Vector3(15, 2.0, -20)],
	["kerb", Vector3(0, 1.8, -24.5), Vector3(2, 0.0, -28.5)],
	["courtyard", Vector3(0, 1.7, -12.5), Vector3(0, 1.5, -2)],
	["great_hall", Vector3(3, 1.8, -1.0), Vector3(-4, 2.2, 12)],
	["great_hall_north", Vector3(2, 1.8, 13), Vector3(-2, 4.0, -2)],
	["reading_room", Vector3(-14, 1.7, 3), Vector3(-22, 1.2, -5)],
	["safe_room", Vector3(13, 1.7, 2.6), Vector3(18, 0.9, 1)],
	["vault", Vector3(-8, 1.7, 17.5), Vector3(0, 1.0, 24)],
	["characters", Vector3(-1.6, 1.25, 7.4), Vector3(-1.6, 1.0, 4.0)],
	["characters_side", Vector3(1.4, 1.3, 4.2), Vector3(-1.6, 1.05, 4.0)],
	["obcera_profile", Vector3(1.0, 1.15, 4.0), Vector3(-0.9, 1.05, 4.0)],
	["obcera_front", Vector3(-0.9, 1.3, 5.9), Vector3(-0.9, 1.05, 4.0)],
]
var idx := -1
var cam: Camera3D
var out := "/tmp"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		# Optional comma list of shot names to render.
		var keep: PackedStringArray = a[1].split(",")
		shots = shots.filter(func(sh): return sh[0] in keep)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(root.get_node("GameState").level_path)
	if frames == 40:
		for z in get_nodes_in_group("zombies"):
			z.set_physics_process(false)
		cam = Camera3D.new()
		cam.fov = 70
		current_scene.add_child(cam)
		cam.make_current()
		for h in get_nodes_in_group("hud"):
			h.visible = false
		# Line-up of the two survivors under the hall chandelier.
		for c in [["zegan", Vector3(-2.3, 0, 4)], ["obcera", Vector3(-0.9, 0, 4)]]:
			var cm := CharacterModel.new()
			cm.character = c[0]
			cm.customization = root.get_node("GameState").default_customization(c[0])
			current_scene.add_child(cm)
			cm.global_position = c[1]
			cm.rotation.y = PI
			cm.play("idle", false)
		var key := OmniLight3D.new()
		key.light_energy = 1.6
		key.omni_range = 6.0
		current_scene.add_child(key)
		key.global_position = Vector3(-1.6, 2.4, 6.0)
		idx = 0
	if idx >= 0 and idx < shots.size():
		var s = shots[idx]
		cam.global_position = s[1]
		cam.look_at(s[2])
		if frames % 20 == 10:
			var img := root.get_texture().get_image()
			img.save_png("%s/%s.png" % [out, s[0]])
			print("saved ", s[0])
			idx += 1
	if idx >= shots.size():
		quit(0)
	return false
