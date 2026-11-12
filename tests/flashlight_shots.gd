extends SceneTree
## Frames of the flashlight from the player's camera, to judge the beam:
## walking, aiming level, aiming down at the floor, and with the light off.
## xvfb-run -a -s "-screen 0 1400x1000x24" godot --path . --rendering-driver vulkan \
##   --resolution 1280x900 --script tests/flashlight_shots.gd -- <out_dir> [yaw_degrees] [place]
## Add --rendering-method mobile to see it the way the phones draw it.
## place: "corridor" stands her in the dark west corridor looking down its
## length; "wall" puts her 0.8 m from the corridor's wall, facing it (the
## 0.9 bug: a small hard disc beside her shoulder), which sets off the
## corridor's lights-out scare, so only the flashlights are on; "wall_lit"
## faces the other corridor wall with the lights on; "street" on Ashgrove
## Street facing the Archive gate; "vault" in the Great Hall facing the co-op
## vault door; default is wherever the level starts her.
var out := "/tmp"
var turn := 0.0
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var shots := [
	{"tag": "1_walk", "aim": false, "pitch": -0.1, "light": true},
	{"tag": "2_aim", "aim": true, "pitch": -0.05, "light": true},
	{"tag": "3_aim_down", "aim": true, "pitch": -0.55, "light": true},
	{"tag": "4_off", "aim": false, "pitch": -0.1, "light": false},
]
var i := 0
var place := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: turn = deg_to_rad(float(a[1]))
	place = a[2] if a.size() > 2 else ""

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 60:
				p = get_first_node_in_group("players")
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				p.equip("p9")
				var spot: Array = {
					"corridor": [Vector3(-13.6, 0.05, 6.5), PI / 2],
					"wall": [Vector3(-20.6, 0.05, 5.95), 0.0],
					"wall_lit": [Vector3(-15.0, 0.05, 7.0), PI],
					"street": [Vector3(1.2, 0.05, -24.5), PI],
					"vault": [Vector3(-6.0, 0.05, 13.4), PI],
				}.get(place, [])
				if not spot.is_empty():
					p.global_position = spot[0]
					p.yaw = spot[1]
					p.body.rotation.y = spot[1]
				p.yaw += turn
				stage = 2
				t = 0.0
		2:
			var s: Dictionary = shots[i]
			p.aiming = s["aim"]
			p.pitch = s["pitch"]
			p.flashlight.visible = s["light"]
			t += d
			if t > 1.2:
				root.get_texture().get_image().save_png("%s/%s.png" % [out, s["tag"]])
				print("saved ", s["tag"])
				i += 1
				t = 0.0
				if i >= shots.size():
					quit()
	return false
