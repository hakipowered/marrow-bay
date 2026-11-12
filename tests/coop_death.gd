extends SceneTree
## Two-process co-op test of going down, being revived, bleeding out and
## continuing together, through the relay.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --script tests/coop_death.gd -- host
## join: same with -- join
## The joiner's survivor goes down; the host revives them; they go down again
## and bleed out; both phones get the game over; both press Continue and the
## level reloads with everyone up. Prints COOP DEATH OK on each side.
var role := ""
var frames := 0
var stage := 0
var t0 := 0
var t := 0.0
var fails := []
var first_level: Node = null

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

func _other() -> Node:
	for p in get_nodes_in_group("players"):
		if not p.is_multiplayer_authority():
			return p
	return null

func _game_over_screen() -> Node:
	var lvl = get_first_node_in_group("level")
	if lvl == null:
		return null
	for c in lvl.get_children():
		if c.has_method("show_votes"):
			return c
	return null

func _done() -> void:
	if fails.is_empty():
		print(role, " COOP DEATH OK")
		quit(0)
	else:
		print(role, " COOP DEATH FAIL: ", fails)
		quit(1)

func _process(d: float) -> bool:
	frames += 1
	t += d
	var net = root.get_node("Net")
	if Time.get_ticks_msec() - t0 > 90000:
		fails.append("timeout at stage %d" % stage)
		_done()
	var cs = root.get_node_or_null("Cutscenes")
	if stage >= 2 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames == 2:
				change_scene_to_file("res://scenes/main_menu.tscn")
			if frames == 10:
				if role == "host":
					net.partner_joined.connect(func(_id): _start_later())
					net.host_online("zegan", "DEATH7")
				stage = 1
		1:
			if role == "join" and frames == 90:
				net.join_online("DEATH7", "obcera")
			if get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2:
				stage = 2
				t = 0.0
		2:
			# Settle, then the joiner goes down.
			if t > 3.0:
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				if role == "join":
					_mine().apply_damage(500.0, null)
					if not _mine().downed or _mine().dead:
						fails.append("joiner should be down, not dead")
				stage = 3
				t = 0.0
		3:
			if role == "host" and t > 1.0:
				var o := _other()
				if not o.downed:
					fails.append("host doesn't see the partner down")
				o.proxy_interact(_mine())   # the host revives them
				stage = 4
				t = 0.0
			elif role == "join" and t > 2.5:
				if _mine().downed:
					fails.append("joiner not revived")
				else:
					print("join: revived with hp ", _mine().hp)
				stage = 4
				t = 0.0
		4:
			# Down again, and this time nobody comes: bleed out.
			if role == "join" and t > 1.5:
				var me := _mine()
				me.apply_damage(500.0, null)
				me._downed_t = me.REVIVE_WINDOW - 0.5
				stage = 5
				t = 0.0
			elif role == "host":
				stage = 5
				t = 0.0
		5:
			var lvl = get_first_node_in_group("level")
			if lvl and lvl.game_over:
				print(role, ": game over, screen ", _game_over_screen() != null)
				first_level = lvl
				stage = 6
				t = 0.0
		6:
			# Joiner presses Continue first; the host a little later.
			var go := _game_over_screen()
			if go and go._buttons.visible:
				if role == "join" and t > 0.5:
					go._on_continue()
					stage = 7
					t = 0.0
				elif role == "host" and t > 3.0:
					go._on_continue()
					stage = 7
					t = 0.0
			elif t > 15.0:
				fails.append("no Continue button")
				_done()
		7:
			var lvl = get_first_node_in_group("level")
			if lvl != null and lvl != first_level and get_nodes_in_group("players").size() == 2 and t > 1.0:
				var me := _mine()
				if me == null:
					return false
				if me.dead or me.downed or lvl.game_over:
					fails.append("still dead after Continue")
				print(role, ": continued together, hp ", me.hp)
				_done()
			elif t > 20.0:
				fails.append("Continue never reloaded")
				_done()
	return false
