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
	["cabinet", Vector3(49.0, 1.6, 2.0), Vector3(48.2, 1.1, 0.3)],
	["cabinet_close", Vector3(48.3, 1.5, 1.15), Vector3(48.2, 1.35, 0.4)],
	["flood_box", Vector3(47.9, 1.55, 10.6), Vector3(48.62, 1.15, 11.8)],
	["pump_door", Vector3(37.0, 1.6, 2.0), Vector3(34.6, 1.1, 4.6)],
	["pump", Vector3(34.3, 1.75, 5.2), Vector3(36.9, -0.5, 9.6)],
	["pump_valves", Vector3(36.3, 1.6, 6.2), Vector3(33.5, 1.3, 8.4)],
	["pump_board", Vector3(35.4, 1.7, 8.4), Vector3(33.4, 2.3, 8.4)],
	["pump_pit", Vector3(37.9, 1.9, 6.3), Vector3(36.0, -1.5, 10.2)],
	["pump_back", Vector3(36.5, 1.8, 11.6), Vector3(35.0, 0.6, 5.0)],
	["yard", Vector3(56.5, 1.8, 4.0), Vector3(72.0, 2.0, 4.0)],
	["yard_shed", Vector3(62.0, 1.8, 3.0), Vector3(58.5, 1.2, 9.5)],
	["yard_back", Vector3(74.0, 1.9, 6.0), Vector3(56.0, 3.0, 2.0)],
	["stacks", Vector3(46.0, 1.7, 13.0), Vector3(48.5, 1.2, 18.5)],
	["stacks_chalk", Vector3(48.0, 1.6, 16.4), Vector3(51.0, 1.4, 17.0)],
	["backstair_door", Vector3(30.6, 1.7, -5.2), Vector3(33.0, 1.7, -11.8)],
	["backstair", Vector3(32.4, 1.6, -9.85), Vector3(33.3, 1.9, -13.5)],
	["backstair_up", Vector3(33.6, 0.9, -9.8), Vector3(32.8, 3.6, -13.8)],
	["backstair_landing", Vector3(31.9, 1.7, -10.0), Vector3(33.4, 1.9, -14.8)],
	["backstair_hunt", Vector3(31.3, 1.75, -6.5), Vector3(32.9, 2.15, -9.8)],
	["sign_lift", Vector3(4.6, 1.7, 4.2), Vector3(5.4, 2.7, 0.0)],
	["sign_lift_arrow", Vector3(3.6, 1.7, 3.6), Vector3(6.9, 2.6, 4.4)],
	["sign_lift_door", Vector3(3.9, 1.7, 3.0), Vector3(0.2, 2.1, 3.0)],
	["sign_survey_door", Vector3(12.6, 1.65, 4.2), Vector3(12.0, 2.3, 1.6)],
	["sign_arrows", Vector3(18.0, 1.65, 4.2), Vector3(18.0, 1.95, 1.6)],
	["sign_keeper", Vector3(11.0, 1.65, 1.9), Vector3(11.0, 2.3, 4.4)],
	["sign_muster_door", Vector3(26.6, 1.65, 1.9), Vector3(26.5, 2.3, 4.4)],
	["sign_pump_door", Vector3(35.4, 1.65, 1.9), Vector3(35.6, 2.2, 4.4)],
	["sign_gallery_door", Vector3(31.1, 1.65, 4.2), Vector3(31.1, 2.3, 1.6)],
	["sign_survey_title", Vector3(15.0, 1.8, -4.4), Vector3(15.0, 2.9, -9.4)],
	["sign_tally", Vector3(12.2, 1.7, -1.9), Vector3(9.1, 1.85, -1.9)],
	["sign_clock", Vector3(25.8, 1.8, -5.4), Vector3(26.0, 2.4, -9.4)],
	["sign_clock_close", Vector3(24.6, 2.1, -7.5), Vector3(24.5, 2.4, -9.4)],
	["sign_muster", Vector3(26.0, 1.8, 10.6), Vector3(26.0, 2.7, 14.4)],
	["sign_staff_only", Vector3(29.4, 1.7, 11.9), Vector3(32.9, 2.5, 11.9)],
	["sign_pump", Vector3(37.0, 1.8, 7.4), Vector3(37.2, 2.9, 4.9)],
	["sign_drill", Vector3(34.2, 1.5, 6.3), Vector3(33.6, 1.15, 4.9)],
	["sign_engine", Vector3(45.6, 2.0, 0.6), Vector3(45.8, 3.7, -5.9)],
	["sign_tank", Vector3(48.0, 2.2, -2.2), Vector3(48.0, 2.6, -4.4)],
	["sign_flood", Vector3(46.0, 1.7, 7.0), Vector3(46.0, 2.8, 12.0)],
	["sign_chute", Vector3(51.4, 2.0, -0.6), Vector3(53.6, 3.3, -3.6)],
	["sign_shed", Vector3(58.5, 1.7, 2.4), Vector3(58.5, 2.2, 6.1)],
	["sign_annex", Vector3(46.4, 1.7, 17.4), Vector3(43.1, 2.0, 17.6)],
	["stacks_chalk", Vector3(48.0, 1.6, 16.4), Vector3(51.0, 1.4, 17.0)],
	["cabinet_close", Vector3(48.3, 1.5, 1.15), Vector3(48.2, 1.35, 0.4)],
	["flood_box", Vector3(47.9, 1.55, 10.6), Vector3(48.62, 1.15, 11.8)],
	["pump_valves", Vector3(36.3, 1.6, 6.2), Vector3(33.5, 1.3, 8.4)],
	["pump_board", Vector3(35.4, 1.7, 8.4), Vector3(33.4, 2.3, 8.4)],
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
		# "doors": every door stood open (to look into rooms past them).
		if "doors" in fl.split(","):
			for d in get_nodes_in_group("doors"):
				if d.has_method("_set_open"):
					d._set_open(true, Vector3(0, 0, 1), false)
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
