extends SceneTree
## Renders views of chapter 2, the Undercroft, to PNG (for checking the look
## without a phone).
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/undercroft_shots.gd -- <out_dir> [shots,...|all] [flag,flag...]
## Flags are set before the level loads, e.g. power:undercroft (the lights
## on), c2_arrival (the lift doors open), c2_clock_open, c2_flood_open.
var frames := 0
var shots := [
	["lift", Vector3(5.8, 1.7, 4.8), Vector3(0.5, 1.4, 2.6)],
	["lift_car", Vector3(-2.2, 1.6, 3.0), Vector3(6.0, 1.5, 3.0)],
	["corridor_w", Vector3(8.0, 1.7, 3.0), Vector3(30.0, 1.4, 3.0)],
	["corridor_e", Vector3(37.5, 1.7, 3.0), Vector3(12.0, 1.4, 3.0)],
	["lodge", Vector3(13.8, 1.7, 9.8), Vector3(9.0, 1.0, 6.5)],
	["lodge_desk", Vector3(11.5, 1.6, 6.0), Vector3(8.6, 0.9, 9.0)],
	["survey", Vector3(19.5, 1.8, -0.2), Vector3(12.0, 1.6, -8.5)],
	["survey_map", Vector3(15.0, 1.7, -3.0), Vector3(15.0, 2.0, -9.5)],
	["gallery", Vector3(33.5, 1.8, -0.5), Vector3(25.0, 2.2, -9.0)],
	["clock", Vector3(26.4, 1.7, -4.5), Vector3(26.4, 2.2, -9.4)],
	["muster", Vector3(26.1, 1.8, 5.4), Vector3(26.0, 1.0, 13.5)],
	["muster_back", Vector3(26.0, 1.8, 13.8), Vector3(26.0, 1.4, 5.0)],
	["hall", Vector3(40.0, 2.0, 3.0), Vector3(50.0, 1.6, 0.0)],
	["hall_door", Vector3(46.0, 2.2, 1.0), Vector3(46.0, 2.0, 12.0)],
	["hall_north", Vector3(46.0, 2.2, 9.0), Vector3(50.0, 2.5, -6.0)],
	["generator", Vector3(43.5, 1.9, 1.6), Vector3(47.5, 0.8, -1.0)],
	["yard", Vector3(56.5, 1.8, 4.0), Vector3(72.0, 2.0, 4.0)],
	["yard_shed", Vector3(62.0, 1.8, 3.0), Vector3(58.5, 1.2, 9.5)],
	["yard_back", Vector3(74.0, 1.9, 6.0), Vector3(56.0, 3.0, 2.0)],
	["stacks", Vector3(46.0, 1.7, 13.0), Vector3(48.5, 1.2, 18.5)],
	["stacks_chalk", Vector3(48.0, 1.6, 16.4), Vector3(51.0, 1.4, 17.0)],
	["top", Vector3(38.0, 70.0, 3.5), Vector3(38.0, 0.0, 3.4)],
]
var idx := -1
var cam: Camera3D
var out := "/tmp"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1 and a[1] != "all":
		var keep: PackedStringArray = a[1].split(",")
		shots = shots.filter(func(sh): return sh[0] in keep)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var gs = root.get_node("GameState")
		var a := OS.get_cmdline_user_args()
		gs.set_flag("story_c2_arrival")
		if a.size() > 2:
			for f in a[2].split(","):
				gs.set_flag(f)
		gs.level_path = "res://scenes/levels/undercroft.tscn"
		gs.shared_checkpoint = "ch2_lift"
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
	if frames == 50:
		for z in get_nodes_in_group("zombies"):
			z.set_physics_process(false)
		cam = Camera3D.new()
		cam.fov = 70
		current_scene.add_child(cam)
		cam.make_current()
		for h in get_nodes_in_group("hud"):
			h.visible = false
		for p in get_nodes_in_group("players"):
			p.global_position = Vector3(-2.0, 0.1, 3.0)
			p.set_physics_process(false)
		var cs = root.get_node_or_null("Cutscenes")
		if cs:
			cs.cover(false)
		var fl: String = OS.get_cmdline_user_args()[2] if OS.get_cmdline_user_args().size() > 2 else ""
		# "torch": the view a survivor gets, with her flashlight on the camera.
		if "torch" in fl.split(","):
			var t := SpotLight3D.new()
			t.spot_range = 22.0
			t.spot_angle = 38.0
			t.spot_attenuation = 0.35
			t.spot_angle_attenuation = 1.5
			t.light_projector = load("res://assets/textures/fx/flashlight_cookie.png")
			t.light_energy = 3.4
			t.light_color = Color(1.0, 0.95, 0.86)
			t.shadow_enabled = true
			t.position = Vector3(0.15, -0.25, 0)
			cam.add_child(t)
		# "lit": flat bright ambient, to check the geometry and props.
		if "lit" in fl.split(","):
			for we in current_scene.find_children("*", "WorldEnvironment", true, false):
				we.environment.ambient_light_energy = 3.0
				we.environment.fog_enabled = false
	if frames > 50 and (frames - 50) % 12 == 0:
		if idx >= 0:
			root.get_texture().get_image().save_png("%s/%s.png" % [out, shots[idx][0]])
		idx += 1
		if idx >= shots.size():
			quit(0)
			return false
		var sh: Array = shots[idx]
		cam.fov = 70 if sh[0] != "top" else 50
		cam.position = sh[1]
		var up := Vector3.UP if sh[0] != "top" else Vector3.FORWARD
		cam.look_at(sh[2], up)
	return false
