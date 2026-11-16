extends SceneTree
## Renders a wall of sample signs (Signage) to PNG, to check the materials.
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/sign_samples.gd -- <out_dir>
var frames := 0
var out := "/tmp"
var cam: Camera3D
var idx := -1
var shots := [
	["wall", Vector3(3.0, 1.7, 3.6), Vector3(3.0, 1.75, 0.0)],
	["left", Vector3(1.3, 1.9, 1.3), Vector3(1.3, 2.0, 0.0)],
	["right", Vector3(4.6, 1.75, 1.3), Vector3(4.6, 1.75, 0.0)],
	["low", Vector3(3.0, 0.95, 1.4), Vector3(3.0, 0.95, 0.0)],
	["tank", Vector3(7.4, 1.6, 2.0), Vector3(7.4, 1.5, 0.5)],
	["graze", Vector3(0.6, 1.8, 1.0), Vector3(2.6, 1.9, 0.12)],
	["brass", Vector3(3.3, 2.35, 0.75), Vector3(3.2, 2.4, 0.0)],
	["cast", Vector3(3.1, 1.8, 0.8), Vector3(3.2, 1.85, 0.0)],
	["board", Vector3(3.3, 0.95, 0.8), Vector3(3.2, 0.9, 0.0)],
	["chalk", Vector3(1.3, 1.4, 1.0), Vector3(1.3, 1.4, 0.0)],
	["dial", Vector3(4.6, 1.0, 0.8), Vector3(4.6, 0.95, 0.0)],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1 and a[1] != "all":
		var keep: PackedStringArray = a[1].split(",")
		shots = shots.filter(func(sh): return sh[0] in keep)

func _build() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.52)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var r := RoomBuilder.build(world, {
		"id": "Samples", "pos": Vector3(-0.125, 0, -0.125), "size": Vector3(9.5, 4.0, 5),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor", "trim": Color(0.16, 0.15, 0.14),
		"wall_look": {"tile_size": 2.4, "grime_amount": 0.8, "grime_height": 1.6, "stain_amount": 0.6},
	})
	# The north wall's face is at z = 0 in world (room at -0.125, wall half 0.125).
	var w := Vector3(0.125, 0, 0.125)   # world -> room
	Signage.plate(r, w + Vector3(1.3, 2.4, 0.0), 0, {"size": Vector2(1.1, 0.26), "style": "enamel",
		"lines": ["ENGINE HALL"], "font": "sans", "border": 0.008, "wear": 0.55, "rust": 0.6, "track": 0.08})
	Signage.paint(r, w + Vector3(1.3, 1.75, 0.0), 0, {"size": Vector2(1.5, 0.3), "kind": "stencil",
		"lines": ["SURVEY  ROOM"], "color": Color(0.86, 0.82, 0.7), "wear": 0.5})
	Signage.paint(r, w + Vector3(1.3, 1.3, 0.0), 0, {"size": Vector2(1.2, 0.36), "kind": "chalk",
		"lines": ["THE COUNT", "IS WRONG"], "color": Color(0.85, 0.85, 0.82), "wear": 0.3})
	Signage.plate(r, w + Vector3(3.2, 2.4, 0.0), 0, {"size": Vector2(0.5, 0.22), "style": "brass",
		"lines": ["MASTER REGULATOR", ["KEEP WOUND", 0.8]], "font": "roman", "border": 0.003, "wear": 0.6})
	Signage.plate(r, w + Vector3(3.2, 1.85, 0.0), 0, {"size": Vector2(0.62, 0.3), "style": "cast",
		"lines": ["No. 2 STANDBY SET", ["ROTHWELL & SONS", 0.8], ["1958", 0.7]], "border": 0.006, "corner": 0.03, "wear": 0.5})
	Signage.plate(r, w + Vector3(3.2, 1.4, 0.0), 0, {"size": Vector2(0.3, 0.06), "style": "engraved",
		"lines": ["FIELD FUSE 60 A"], "wear": 0.4})
	Signage.plate(r, w + Vector3(4.6, 2.3, 0.0), 0, {"size": Vector2(0.9, 0.4), "style": "painted",
		"lines": ["FLOOD DOOR No. 3", ["KEEP CLEAR WHEN ALARM SOUNDS", 0.45]], "field": Color(0.75, 0.6, 0.12),
		"ink": Color(0.05, 0.05, 0.05), "border": 0.012, "wear": 0.6, "rust": 0.7})
	Signage.plate(r, w + Vector3(4.6, 1.6, 0.0), 0, {"size": Vector2(0.42, 0.3), "style": "card",
		"lines": ["LIFT DEAD AGAIN.", "Vault breaker tripped.", "Reset it in the BOILER ROOM", "- O.V."], "font": "hand",
		"align": "left", "wear": 0.5})
	Signage.plate(r, w + Vector3(4.6, 0.95, 0.0), 0, {"size": Vector2(0.44, 0.44), "style": "dial", "corner": 0.22,
		"items": [{"text": "XII", "at": Vector2(0, 0.155), "h": 0.03, "font": "roman"},
			{"text": "III", "at": Vector2(0.155, 0), "h": 0.03, "font": "roman"},
			{"text": "VI", "at": Vector2(0, -0.155), "h": 0.03, "font": "roman"},
			{"text": "IX", "at": Vector2(-0.155, 0), "h": 0.03, "font": "roman"}],
		"dial": Vector4(0.2, 0.185, 0.02, 1.0)})
	Signage.plate(r, w + Vector3(3.2, 0.9, 0.0), 0, {"size": Vector2(0.6, 0.28), "style": "board",
		"lines": ["MUSTER POINT B"], "font": "serif", "ink_metal": 1.0, "border": 0.005, "wear": 0.4})
	# A tank with a plate bent round it.
	var tank := UndercroftKit.bar(r, w + Vector3(7.4, 1.4, 0.75), 0.62, 2.0, Mats.trim(Color(0.2, 0.25, 0.2), 0.6, 0.6), "x", 32)
	tank.name = "Tank"
	Signage.plate(r, w + Vector3(7.4, 1.4, 0.75) + Vector3(0, 0.0, 0.62), 0, {"size": Vector2(0.7, 0.32), "style": "enamel",
		"lines": ["DIESEL DAY TANK", ["EMPTY", 0.6]], "bend": 0.62, "bend_axis": "x", "border": 0.008})
	# Light.
	var l := OmniLight3D.new()
	l.position = Vector3(3.0, 3.3, 2.2)
	l.light_energy = 0.7
	l.omni_range = 8.0
	l.shadow_enabled = true
	world.add_child(l)
	var l2 := OmniLight3D.new()
	l2.position = Vector3(7.4, 2.8, 2.4)
	l2.light_energy = 0.5
	l2.omni_range = 5.0
	l2.shadow_enabled = true
	world.add_child(l2)
	cam = Camera3D.new()
	cam.fov = 60
	world.add_child(cam)
	cam.make_current()
	var t := SpotLight3D.new()
	t.spot_range = 22.0
	t.spot_angle = 38.0
	t.light_energy = 3.0
	t.spot_attenuation = 0.35
	t.spot_angle_attenuation = 1.5
	t.shadow_enabled = true
	t.position = Vector3(0.15, -0.25, 0)
	cam.add_child(t)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		_build()
	if frames > 4 and (frames - 4) % 8 == 0:
		if idx >= 0:
			root.get_texture().get_image().save_png("%s/%s.png" % [out, shots[idx][0]])
		idx += 1
		if idx >= shots.size():
			quit(0)
			return false
		cam.position = shots[idx][1]
		cam.look_at(shots[idx][2])
	return false
