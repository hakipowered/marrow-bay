extends SceneTree
## Two-process co-op test through the relay.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --script tests/coop_peer.gd -- host
## join: same with -- join
var role := ""
var frames := 0
var stage := 0
var t0 := 0

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	t0 = Time.get_ticks_msec()

func _start_later() -> void:
	await create_timer(1.0).timeout
	var gs = root.get_node("GameState")
	print("host roster ", gs.character_by_peer)
	current_scene._start_coop.rpc(gs.level_path, "start", {})

func _process(_d: float) -> bool:
	frames += 1
	var net = root.get_node("Net")
	var gs = root.get_node("GameState")
	if Time.get_ticks_msec() - t0 > 40000:
		print(role, " TIMEOUT stage ", stage)
		quit(1)
	match stage:
		0:
			if frames == 2:
				change_scene_to_file("res://scenes/main_menu.tscn")
			if frames == 10:
				if role == "host":
					net.partner_joined.connect(func(_id): print("host: partner joined"); _start_later())
					net.host_online("zegan", "TEST42")
				stage = 5
		5:
			if role == "join" and frames == 90:
				net.join_online("TEST42", "zegan")
				stage = 1
			elif role == "host":
				stage = 1
		1:
			if get_first_node_in_group("level") != null:
				stage = 2
				frames = 0
				print(role, ": level loaded, my id ", root.multiplayer.get_unique_id())
		2:
			if frames == 120:
				var ps = get_nodes_in_group("players")
				var desc := []
				for p in ps:
					desc.append("%s(%d)@%s" % [p.character, p.peer_id, p.global_position.snapped(Vector3.ONE * 0.1)])
					if p.is_multiplayer_authority():
						p.move_input = Vector2(0, -1)
				print(role, ": players ", desc)
				if role == "join":
					root.get_node("CallOuts").call_partner(true)
			if frames == 240:
				var desc := []
				for p in get_nodes_in_group("players"):
					desc.append("%s(%d)@%s" % [p.character, p.peer_id, p.global_position.snapped(Vector3.ONE * 0.1)])
				print(role, ": after move ", desc)
				print(role, " COOP OK")
				quit(0)
	return false
