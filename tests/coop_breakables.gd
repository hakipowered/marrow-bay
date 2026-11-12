extends SceneTree
## Two-process co-op test of shootable things, through the relay:
##  - The joiner shoots the courtyard drum: it blows on both phones, an
##    infected next to it dies, and both phones show the wreck.
##  - The host shoots a great hall window: both phones see it shattered.
##  - The joiner stands by the boiler drums when the host sets them off:
##    the joiner's own phone takes the blast damage.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_breakables.gd -- host
## join: same with -- join
## Prints COOP BREAKABLES OK on each side.
var role := ""
var frames := 0
var stage := 0
var t0 := 0
var t := 0.0
var fails := []
var hp0 := 0.0
var _did := {}   # steps done (a story scene can cut in mid-stage)

func _once(key: String) -> bool:
	if _did.has(key):
		return false
	_did[key] = true
	return true

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	t0 = Time.get_ticks_msec()

func _start_later() -> void:
	await create_timer(1.0).timeout
	current_scene._start_coop.rpc(root.get_node("GameState").level_path, "start", {})

func _mine() -> Node:
	for p in get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null

func _b(id: String) -> Node:
	return current_scene.find_child("Breakable_" + id, true, false)

func _shoot_at(p: Node, target: Vector3) -> void:
	var cam: Camera3D = p.camera
	var from := cam.global_position
	root.get_node("Combat").fire(p, "p9", from, [(target - from).normalized()], p._muzzle_pos())

func _stand(p: Node, at: Vector3, target: Vector3) -> void:
	p.global_position = at
	var d := target - at
	p.yaw = atan2(-d.x, -d.z)
	p.body.rotation.y = p.yaw
	p.pitch = 0.0

func _glass() -> Node:
	for b in get_nodes_in_group("breakables"):
		if b.kind == "glass" and b.breakable_id.begins_with("glass_GreatHall_n") and b.global_position.y < 4.0:
			return b
	return null

var _quitting := false

func _done() -> void:
	if _quitting:
		return
	_quitting = true
	print(role, " COOP BREAKABLES OK" if fails.is_empty() else " COOP BREAKABLES FAIL: " + str(fails))
	await create_timer(4.0).timeout
	quit(0 if fails.is_empty() else 1)

func _process(d: float) -> bool:
	if _quitting:
		return false
	frames += 1
	var net = root.get_node("Net")
	if Time.get_ticks_msec() - t0 > 90000:
		fails.append("timeout at stage %d" % stage)
		_done()
	var cs = root.get_node_or_null("Cutscenes")
	if stage >= 2 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	t += d   # not while a story scene plays: both phones sit through it
	match stage:
		0:
			if frames == 2:
				change_scene_to_file("res://scenes/main_menu.tscn")
			if frames == 10:
				root.get_node("GameState").reset_run()
				if role == "host":
					net.partner_joined.connect(func(_id): _start_later())
					net.host_online("zegan", "BXRT42")
				stage = 1
		1:
			if role == "join" and frames == 90:
				net.join_online("BXRT42", "obcera")
			if get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2:
				stage = 2
				t = 0.0
		2:
			if t > 3.0:
				# Keep one infected (host owns them) beside the courtyard drum.
				var kept := false
				var drum := _b("court_drum_gate")
				var c: Vector3 = drum.global_transform * drum.center
				for zz in get_nodes_in_group("zombies"):
					if not kept and zz.name == "Z_court_2":
						kept = true
						if role == "host":
							zz.global_position = c + Vector3(1.2, -c.y, 0.5)
						continue
					if role == "host":
						zz.queue_free()
				if role == "join":
					_stand(_mine(), c + Vector3(0.5, -c.y + 0.05, 9.0), c)
				else:
					var g := _glass()
					_stand(_mine(), Vector3(g.global_position.x, 0.05, g.global_position.z + 5.0), g.global_position)
				stage = 3
				t = 0.0
		3:
			if role == "join" and t > 1.0 and _once("shoot_drum"):
				var drum := _b("court_drum_gate")
				_shoot_at(_mine(), drum.global_transform * drum.center)
			if role == "host" and t > 1.2 and _once("shoot_glass"):
				_shoot_at(_mine(), _glass().global_position)
			if t > 3.2:
				var drum := _b("court_drum_gate")
				if not drum.broken:
					fails.append("drum the joiner shot didn't blow on the %s" % role)
				if drum.model != null:
					fails.append("no wreck on the %s" % role)
				var z := current_scene.find_child("Z_court_2", true, false)
				if z and z.state != z.get_script().get_script_constant_map()["S"]["DEAD"]:
					fails.append("infected by the drum lived on the %s" % role)
				if not _glass().broken:
					fails.append("window the host shot isn't broken on the %s" % role)
				# Next: the joiner by the boiler drums.
				if role == "join":
					var b1 := _b("boiler_drum_1")
					_stand(_mine(), b1.global_position + Vector3(-2.0, 0.05, -1.0), b1.global_position)
					hp0 = _mine().hp
				stage = 4
				t = 0.0
		4:
			if role == "host" and t > 1.5 and _once("boiler"):
				var b1 := _b("boiler_drum_1")
				b1.host_damage(30.0, "bullet", b1.global_position + Vector3.UP * 0.4, Vector3.FORWARD)
			if t > 3.5 and (role == "join" or _did.has("boiler")):
				if not (_b("boiler_drum_1").broken and _b("boiler_drum_2").broken):
					fails.append("boiler drums didn't both go on the %s" % role)
				if role == "join":
					if _mine().hp >= hp0:
						fails.append("joiner beside the drums took no damage (%.0f -> %.0f)" % [hp0, _mine().hp])
					else:
						print("join: blast took her from %.0f to %.0f" % [hp0, _mine().hp])
				_done()
	return false
