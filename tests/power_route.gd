extends SceneTree
## The vault power and the elevator, end to end (solo), the way a player does
## it: after Hardass, the dead elevator in the vault, the breaker in the
## boiler room (the prompt has to show from where a person would stand),
## lights and objective, the key card, walking into the car, the ride, and a
## reload with the power on. Prints POWER ROUTE OK or POWER ROUTE FAIL.
##   godot --headless --path . --fixed-fps 60 --script tests/power_route.gd
var frames := 0
var p: Node
var gs: Node
var cs: Node
var lift: Node
var breaker: Node
var circuit: Node
var fails := []
var step := 0
var wait_to := 0
var _walk_from := Vector3.ZERO

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)

## Stands her `dist` m out from a point on a wall, facing it (normal n points
## out of the wall), lets the reach ray update, and returns the prompt.
func _prompt_at(target: Vector3, n: Vector3, dist: float, side := 0.0) -> String:
	var right := n.cross(Vector3.UP).normalized()
	p.global_position = Vector3(target.x, 0.0, target.z) + n * dist + right * side
	p.velocity = Vector3.ZERO
	var face := atan2(n.x, n.z)
	p.body.global_rotation.y = face
	p.yaw = face
	p.sync_yaw = face
	p.move_input = Vector2.ZERO
	for i in 3:
		p.interact_ray.force_raycast_update()
	p._update_focus()
	return p._prompt_text

func _walk(dir: Vector3) -> void:
	p.yaw = atan2(-dir.x, -dir.z)
	p.move_input = Vector2(0, -1)

func _process(_d: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 240000:
		print("TIMEOUT")
		quit(1)
	if frames == 3:
		gs = root.get_node("GameState")
		cs = root.get_node("Cutscenes")
		gs.reset_run()
		for beat in ["intro", "gates", "warden", "glass"]:
			gs.set_flag("story_" + beat)
		gs.world_flags["objective"] = "Find a way down to the records vault"   # an old save's goal
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
		return false
	if frames < 40:
		return false
	match step:
		0:
			p = get_first_node_in_group("players")
			lift = current_scene.find_child("VaultElevator", true, false)
			breaker = current_scene.find_child("BreakerPanel", true, false)
			circuit = current_scene.find_child("VaultCircuit", true, false)
			_check(lift != null and breaker != null and circuit != null, "elevator, breaker and vault circuit are in the level")
			for z in get_nodes_in_group("zombies"):
				z.queue_free()
			p.inventory.key_items.append("vault_card")
			print("objective after loading an old save: ", gs.world_flags.get("objective", ""))
			_check(str(gs.world_flags.get("objective", "")).contains("boiler room"), "old save's objective now says where the power is")
			_check(not circuit._lights[0].visible, "vault tubes dark before the power")
			# The dead elevator.
			var n: Vector3 = lift.global_transform.basis.z
			var t := _prompt_at(lift.global_position, n, 1.0)
			_check(t == "Call the elevator", "dead elevator prompt: \"%s\"" % t)
			p.interact()
			_check(p.inventory.files.has("lift_note"), "the note on the doors goes into Files")
			_check(not lift.is_open and lift._blocker.collision_layer == 1, "doors stay shut without power")
			step = 1
			wait_to = frames + 20
		1:
			if frames < wait_to:
				return false
			# The breaker: a prompt from where a person stands, at a few
			# distances and a little to either side.
			var n: Vector3 = breaker.global_transform.basis.z
			var at: Vector3 = breaker.global_position + breaker.global_transform.basis * Vector3(0.25, 0, 0)
			for c in [[0.6, 0.0], [1.0, 0.0], [1.5, 0.0], [1.0, -0.4], [1.0, 0.4]]:
				var t := _prompt_at(at, n, c[0], c[1])
				var hit = p.interact_ray.get_collider() if p.interact_ray.is_colliding() else null
				_check(t == "Turn on the power", "breaker prompt at %.1f m, %+.1f m aside: \"%s\" (ray hit %s)" % [c[0], c[1], t, str(hit.get_parent().name) if hit else "-"])
			_prompt_at(at, n, 1.0)
			p.interact()
			step = 2
			wait_to = frames + 60 * 4
		2:
			if frames < wait_to:
				return false
			_check(gs.has_flag("power:vault"), "power flag set")
			_check(absf(breaker._handle.rotation.x - breaker.HANDLE_ON) < 0.05, "breaker handle thrown up")
			var lit := 0
			for l in circuit._lights:
				lit += 1 if l.visible else 0
			_check(lit == circuit._lights.size(), "vault tubes on (%d of %d)" % [lit, circuit._lights.size()])
			_check(lift._car_light.visible and lift._lamp_light.light_energy > 0.0, "elevator lamp and car light on")
			print("objective: ", gs.world_flags.get("objective", ""))
			_check(gs.world_flags.get("objective", "") == "Take the vault elevator down", "objective moved on to the elevator")
			var n2: Vector3 = breaker.global_transform.basis.z
			var t := _prompt_at(breaker.global_position, n2, 1.0)
			_check(t == "", "breaker has no prompt once it's on")
			# The key card.
			var n: Vector3 = lift.global_transform.basis.z
			t = _prompt_at(lift.global_position, n, 1.0)
			_check(t == "Use the vault key card", "elevator prompt with power: \"%s\"" % t)
			p.interact()
			step = 3
			wait_to = frames + 60 * 3
		3:
			if frames < wait_to:
				return false
			_check(lift.is_open and lift._blocker.collision_layer == 0, "doors open")
			# Walk in from the vault on her own feet.
			var n: Vector3 = lift.global_transform.basis.z
			_prompt_at(lift.global_position, n, 2.0)
			_walk_from = p.global_position
			_walk(-n)
			step = 4
			wait_to = frames + 60 * 2
		4:
			if frames < wait_to:
				return false
			p.move_input = Vector2.ZERO
			_check(lift.in_car(p.global_position), "walked into the car (now %s, %.2f m from the start)" % [str(p.global_position.snapped(Vector3.ONE * 0.01)), p.global_position.distance_to(_walk_from)])
			_check(absf(p.global_position.y) < 0.1, "standing on the car floor (y %.2f)" % p.global_position.y)
			var n: Vector3 = lift.global_transform.basis.z
			p.body.global_rotation.y = atan2(n.x, n.z)
			for i in 3:
				p.interact_ray.force_raycast_update()
			p._update_focus()
			_check(p._prompt_text == "Go down", "inside the car: \"%s\"" % p._prompt_text)
			p.interact()
			step = 5
			wait_to = frames + 30
		5:
			if frames < wait_to:
				return false
			_check(cs.active and cs.current == "elevator", "the ride starts")
			step = 6
			# Scenes run on the wall clock (Cutscenes._sleep), not frames.
			wait_to = Time.get_ticks_msec() + 45000
		6:
			if cs.active and Time.get_ticks_msec() < wait_to:
				return false
			_check(not cs.active, "the ride ends by itself")
			_check(gs.has_flag("story_elevator"), "story_elevator flag")
			print("objective: ", gs.world_flags.get("objective", ""))
			_check(str(gs.world_flags.get("objective", "")).begins_with("End of chapter 1"), "objective says this is the end of chapter 1 for now")
			_check(lift.is_open and not p.input_locked, "doors open again and she can move")
			# Reload: the power and the open doors come back with the flags.
			reload_current_scene()
			step = 7
			wait_to = frames + 40
		7:
			if frames < wait_to:
				return false
			lift = current_scene.find_child("VaultElevator", true, false)
			breaker = current_scene.find_child("BreakerPanel", true, false)
			circuit = current_scene.find_child("VaultCircuit", true, false)
			_check(circuit._lights[0].visible and lift._car_light.visible, "after a reload the vault is lit")
			_check(lift.is_open and absf(breaker._handle.rotation.x - breaker.HANDLE_ON) < 0.05, "after a reload the doors are open and the handle is up")
			print("POWER ROUTE OK" if fails.is_empty() else "POWER ROUTE FAIL: %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	return false
