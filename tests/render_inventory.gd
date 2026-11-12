extends SceneTree
## Renders the bag and weapons in hand to PNG, to check the layout on the
## Fold's inner and cover screens without a phone.
## xvfb-run -s "-screen 0 2600x1900x24" godot --path . --rendering-driver opengl3 \
##   --resolution 2176x1812 --script tests/render_inventory.gd -- <out_dir> [zegan|obcera] [prefix] [weapons]
## "weapons" skips the bag and renders only the weapons in hand; "bag" stops
## after the bag.
var frames := 0
var out := "/tmp"
var who := "zegan"
var prefix := ""
var step := 0
var t := 0
var p
var hud: Node
var menu
var skip_bag := false
var bag_only := false

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: who = a[1]
	if a.size() > 2: prefix = a[2]
	skip_bag = a.size() > 3 and a[3] == "weapons"
	bag_only = a.size() > 3 and a[3] == "bag"

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s%s.png" % [out, prefix, name])
	print("saved ", prefix, name)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("Net").start_solo(who)
		change_scene_to_file(root.get_node("GameState").level_path)
		return false
	if frames < 50:
		return false
	if p == null:
		p = get_first_node_in_group("players")
		hud = get_first_node_in_group("hud")
		for z in get_nodes_in_group("zombies"):
			z.set_physics_process(false)
		var inv = p.inventory
		inv.add_weapon("m12")
		inv.add_weapon("hornet")
		inv.add_weapon("bastion")
		inv.add("frag", 2)
		inv.add("flash", 1)
		inv.add_ammo("shells", 12)
		inv.add_ammo("50cal", 6)
		inv.add("herb_red")
		inv.add("herb_green", 2)
		inv.add("gunpowder", 2)
		inv.add("medkit")
		inv.add_key("brass_quill_key")
		inv.add_file("shelter_log")
		p.inventory.mag["p9"] = 9
		p.hp = 52.0
		p.health_changed.emit(p.hp, p.max_hp)
		# Stand in the Great Hall facing the chandelier.
		p.global_position = Vector3(1.5, 0.05, 3.0)
		p.yaw = PI * 0.9
		p.equip("p9")
		t = frames
		return false
	var dt := frames - t
	match step:
		0:
			if skip_bag:
				step = 2; t = frames
				return false
			if dt == 20:
				hud.toggle_inventory()
				menu = hud._inventory
			if dt == 40:
				_shot("bag")
				step = 1; t = frames
		1:
			if dt == 2:
				# Pick the green fern stack and start combining.
				for i in 16:
					var s = p.inventory.slots[i]
					if s != null and s["id"] == "herb_green":
						menu._on_slot(i)
						break
				menu._toggle_combine()
			if dt == 14:
				_shot("bag_combine")
				menu._combine_from = -1
				for i in 16:
					var s = p.inventory.slots[i]
					if s != null and s["id"] == "m12":
						menu._on_slot(i)
						break
			if dt == 30:
				_shot("bag_weapon")
				menu._open_examine("m12")
			if dt == 50:
				_shot("examine")
				menu._close_examine()
				menu._switch_tab("files")
			if dt == 64:
				_shot("files")
				if bag_only:
					print("RENDER OK")
					quit(0)
				menu.close()
				step = 2; t = frames
		2:
			if dt == 2:
				# Back to the lamps, so the knife hand is lit.
				p.yaw = PI * 1.9
				p.equip("knife")
				p.aiming = true
			if dt == 40:
				_shot("knife_guard")
				p.aiming = false
				p.fire_held = true
				step = 3; t = frames
		3:
			# Mid-swing: wait for the slash to reach the blade's arc.
			var ap = p.model._anim
			if (ap.current_animation == "combat/slash" and ap.current_animation_position > 0.5) or dt > 120:
				_shot("knife_slash")
				p.fire_held = false
				step = 4; t = frames
		4:
			if dt == 30:
				p.yaw = PI * 0.9
				p.equip("m12")
				p.aiming = true
			if dt == 70:
				_shot("shotgun_aim")
				p.equip("p9")
			if dt == 110:
				_shot("pistol_aim")
				p.aiming = false
			if dt == 150:
				_shot("pistol_idle")
				print("RENDER OK")
				quit(0)
	return false
