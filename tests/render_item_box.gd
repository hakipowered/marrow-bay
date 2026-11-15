extends SceneTree
## Pictures of the item boxes: the office's and the keeper's lodge's, shut and
## open, from the survivor's own camera, and the box screen with things in it.
## xvfb-run -a -s "-screen 0 1450x1208x24" godot --path . --rendering-driver vulkan \
##   --rendering-method mobile --resolution 1450x1208 --script tests/render_item_box.gd -- <out_dir> [office|lodge]
## Chapter 1's story so far (the office scene played, the vault not yet
## reached: "story_elevator" sends a chapter 1 load on to chapter 2), and
## chapter 2's opening scenes.
const CH1_BEATS := ["intro", "gates", "warden", "glass"]
const CH2_BEATS := ["c2_arrival", "c2_intercom", "c2_warden"]
var out := "/tmp"
var where := "office"
var frames := 0
var p: Node
var gs: Node
var box: Node
var hud: Node
var step := 0
var t := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		where = a[1]
	DirAccess.make_dir_recursive_absolute(out)

func _stand(dist: float, side := 0.0, pitch := -0.32) -> void:
	var n: Vector3 = box.global_transform.basis.z
	var r: Vector3 = box.global_transform.basis.x
	p.global_position = Vector3(box.global_position.x, 0.05, box.global_position.z) + n * dist + r * side
	p.velocity = Vector3.ZERO
	var to: Vector3 = box.global_position - p.global_position
	var face := atan2(-to.x, -to.z)
	p.body.global_rotation.y = face
	p.yaw = face
	p.pitch = pitch

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, where, name])
	print("saved ", where, "_", name, "  prompt: \"", p._prompt_text, "\"")

func _process(d: float) -> bool:
	frames += 1
	if frames == 3:
		gs = root.get_node("GameState")
		gs.reset_run()
		for beat in CH1_BEATS + (CH2_BEATS if where == "lodge" else []):
			gs.set_flag("story_" + beat)
			gs.world_flags["objective"] = "Find Nasri"
		if where == "lodge":
			gs.level_path = "res://scenes/levels/undercroft.tscn"
			gs.shared_checkpoint = "ch2_lodge"
		else:
			gs.shared_checkpoint = "safe_office"
		# Things in the box, so the screen has something to show.
		var st: Node = gs.item_box
		st._put("m12", 1, 4)
		st._put("ammo:shells", 22)
		st._put("ammo:9mm", 75)
		st._put("herb_green", 4)
		st._put("frag", 2)
		st._put("gunpowder", 3)
		st._put("longshot", 1, 5)
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
		return false
	if frames < 60:
		return false
	if p == null:
		p = get_first_node_in_group("players")
		hud = get_first_node_in_group("hud")
		for b in get_nodes_in_group("item_boxes"):
			if (where == "office" and "office" in str(b.name)) or (where == "lodge" and "lodge" in str(b.name)):
				box = b
		for z in get_nodes_in_group("zombies"):
			z.queue_free()
		for s in get_nodes_in_group("stalker"):
			s.queue_free()
		p.equip("p9")
		t = 0.0
		return false
	t += d
	match step:
		0:
			_stand(2.1, 0.5)
			if t > 2.5:
				p.interact_ray.force_raycast_update()
				p._update_focus()
				_shot("1_shut")
				step = 1
				t = 0.0
		1:
			_stand(2.6, -1.4, -0.42)
			if t > 1.0:
				_shot("2_wide")
				box.set_in_use(true)
				step = 2
				t = 0.0
		2:
			_stand(1.9, 0.6, -0.5)
			if t > 1.8:
				_shot("3_open")
				box.set_in_use(false)
				step = 3
				t = 0.0
		3:
			_stand(1.2, 0.0)
			if t > 1.2:
				p.interact_ray.force_raycast_update()
				p._update_focus()
				print("prompt at the box: ", p._prompt_text)
				p.interact()
				step = 4
				t = 0.0
		4:
			if t > 1.0:
				_shot("4_screen")
				var menu: Node = hud._box_menu
				menu._side = "box"
				menu._sel = -1
				menu._box_key = int(gs.item_box.sorted()[0]["k"])
				menu._refresh()
				step = 5
				t = 0.0
		5:
			if t > 1.0:
				_shot("5_screen_gun")
				var menu: Node = hud._box_menu
				menu._on_box_slot(2)
				menu._on_box_slot(2)
				step = 6
				t = 0.0
		6:
			if t > 1.0:
				_shot("6_took_shells")
				quit()
	return false
