extends SceneTree
## Checks the 0.5 playtest fixes on a solo game, headless:
##   1. an item lying on the floor can be picked up (focus + interact)
##   2. a second finger on FIRE works while the first is on the move stick
##   3. FIRE without AIM shoots from the hip and hits an infected ahead
##   4. the knife's hit lands on the swing's contact frame, not later
##   5. the crosshair dot shows with a gun and hides with the knife
##   godot --headless --path . --script tests/player_feel.gd
var frames := 0
var stage := 0
var t := 0
var p
var hud
var z
var fails: Array[String] = []
var hp0 := 0.0
var mag0 := 0
var hit_at := -1.0
var swing_at := 0
var swung_at := -1.0
var fire_downs := 0

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _process(_d: float) -> bool:
	frames += 1
	var gs = root.get_node("GameState")
	if frames == 3:
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
		return false
	if frames < 40:
		return false
	var cs = root.get_node_or_null("Cutscenes")
	if cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	if p == null:
		p = get_first_node_in_group("players")
		hud = get_first_node_in_group("hud")
		for zz in get_nodes_in_group("zombies"):
			zz.set_physics_process(false)
			zz.global_position += Vector3(0, -50, 0)   # out of the way
		p.global_position = Vector3(1.5, 0.05, 3.0)
		p.yaw = PI
		p.body.rotation.y = PI
		t = frames
		return false
	var dt := frames - t
	match stage:
		0:
			# 1. An item on the floor, half a metre ahead.
			if dt == 1:
				var lvl = current_scene
				lvl.spawn_pickup("herb_red", p.global_position + Vector3(0, 0.05, 0.8), 1)
			if dt == 10:
				var focus = p._focus
				_check(focus != null and focus.is_in_group("pickups") and focus.get("item") == "herb_red", "floor item is in reach (focus %s)" % [focus])
				_check(hud._prompt.visible and hud._prompt.text.begins_with("Pick up"), "pickup prompt shows: '%s'" % hud._prompt.text)
				hp0 = p.inventory.count("herb_red")
				p.interact()
			if dt == 20:
				_check(p.inventory.count("herb_red") == hp0 + 1, "floor item went into the bag")
				stage = 1; t = frames
		1:
			# 2. Thumb on the stick (finger 0), then FIRE with finger 1.
			if dt == 1:
				var stick_at := Vector2(root.get_visible_rect().size.x * 0.2, root.get_visible_rect().size.y * 0.8)
				_touch(0, stick_at, true)
			if dt == 3:
				var fire: Control = hud._fire_btn
				fire.button_down.connect(func(): fire_downs += 1)
				_touch(1, fire.get_global_rect().get_center(), true)
			if dt == 5:
				_check(fire_downs == 1 and hud._fire_btn._finger == 1, "second finger presses FIRE while the stick is held")
				var stick = root.find_children("*", "TouchStick", true, false)
				_check(not stick.is_empty() and stick[0]._touch == 0, "first finger still holds the move stick")
				var fire: Control = hud._fire_btn
				_touch(1, fire.get_global_rect().get_center(), false)
			if dt == 7:
				_check(hud._fire_btn._finger == -1 and not p.fire_held, "lifting the second finger releases FIRE")
				var stick_at := Vector2(root.get_visible_rect().size.x * 0.2, root.get_visible_rect().size.y * 0.8)
				_touch(0, stick_at, false)
				stage = 2; t = frames
		2:
			# 3. Hip-fire at an infected 6 m ahead, without AIM.
			if dt == 1:
				z = get_nodes_in_group("zombies")[0]
				z.global_position = p.global_position + Vector3(0, 0, 6.0)
				z.state = z.S.CHASE
				p.move_input = Vector2.ZERO
				p.equip("p9")
				p.yaw = 0.0   # camera looks along -Z; the body still faces +Z...
				p.pitch = -0.05
			if dt == 3:
				# ...so turn the camera onto the infected (+Z is behind -Z).
				p.yaw = PI
				hp0 = z.hp
				mag0 = p.inventory.mag["p9"]
				p.aiming = false
				p.fire_held = true
			if dt == 40:
				p.fire_held = false
				_check(p.inventory.mag["p9"] < mag0, "hip-fire shot without AIM (mag %d -> %d)" % [mag0, p.inventory.mag["p9"]])
				_check(z.hp < hp0, "hip-fire hit the infected ahead (hp %.0f -> %.0f)" % [hp0, z.hp])
				_check(hud._crosshair._want > 0.0, "crosshair dot shows with a gun")
				stage = 3; t = frames
		3:
			# 4. Knife: when does the hit land relative to the swing?
			if dt == 1:
				z.hp = 500.0
				z.global_position = p.global_position + Vector3(0, 0, 1.1)
				p.equip("knife")
			if dt == 20:
				hp0 = z.hp
				p.fire_held = true
				swing_at = Time.get_ticks_msec()
			if dt > 20 and swung_at < 0.0 and p._swing_t > 0.0:
				swung_at = (Time.get_ticks_msec() - swing_at) / 1000.0
			if dt > 20 and hit_at < 0.0 and z.hp < hp0:
				hit_at = (Time.get_ticks_msec() - swing_at) / 1000.0
			if dt > 20 and (hit_at > 0.0 or Time.get_ticks_msec() - swing_at > 1500):
				p.fire_held = false
				_check(hit_at > 0.0, "knife hit the infected in front")
				print("     knife hit landed %.2f s after the press, swing began at %.2f s (contact frame %.2f s into the swing)" % [hit_at, swung_at, 0.46 / 1.6])
				_check(swung_at >= 0.0 and hit_at - swung_at < 0.29 + 0.06, "knife hit lands on the contact frame")
				_check(hud._crosshair._want == 0.0, "crosshair hidden with the knife")
				stage = 4; t = frames
		4:
			if fails.is_empty():
				print("PLAYER FEEL OK")
			else:
				print("PLAYER FEEL FAILED: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _touch(index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	root.push_input(e, true)
