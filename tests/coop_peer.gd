extends SceneTree
## Two-process co-op test through the relay.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --script tests/coop_peer.gd -- host
## join: same with -- join
var role := ""
var frames := 0
var outfits_ok := false
var stage := 0
var t0 := 0
var t_play := -1.0
var saw_scene := false
var _done := {}

func _secs() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0

## True the first time `cond` holds for this name, then never again.
func _once(name: String, cond: bool) -> bool:
	if not cond or _done.has(name):
		return false
	_done[name] = true
	return true

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
	if Time.get_ticks_msec() - t0 > 60000:
		print(role, " TIMEOUT stage ", stage)
		quit(1)
	match stage:
		0:
			if frames == 2:
				change_scene_to_file("res://scenes/main_menu.tscn")
			if frames == 10:
				# Outfits: the host wears Riot Unit as Zegan. The joiner also asks for
				# Zegan, so it is handed Obcera and must arrive in its saved Obcera
				# look (Red Dress), not its Zegan one.
				if role == "host":
					gs.looks = {"zegan": {"outfit": "riot", "chest": 0.7}}
				else:
					gs.looks = {"zegan": {"outfit": "biker"}, "obcera": {"outfit": "red_dress", "hips": 0.8}}
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
			# Both players skip the intro (co-op skip needs both); the checks
			# below wait for it, since nobody can move or aim during a scene.
			var cs = root.get_node_or_null("Cutscenes")
			if cs and cs.active:
				saw_scene = true
				if frames % 10 == 0:
					cs._on_skip_pressed()
				frames = mini(frames, 100)
				return false
			if frames == 120:
				var ps = get_nodes_in_group("players")
				var desc := []
				for p in ps:
					desc.append("%s(%d)@%s" % [p.character, p.peer_id, p.global_position.snapped(Vector3.ONE * 0.1)])
					if p.is_multiplayer_authority():
						p.move_input = Vector2(0, -1)
						p.pitch = -0.6   # looking down: the partner's lamp must tip down too
				print(role, ": players ", desc)
				# Checked here, while both players are still in the level.
				var worn := {}
				for p in ps:
					worn[p.character] = p.model.outfit
				print(role, ": outfits ", worn)
				outfits_ok = worn.get("zegan") == "riot" and worn.get("obcera") == "red_dress"
				if role == "join":
					root.get_node("CallOuts").call_partner(true)
			# The rest runs on each phone's clock from the moment the intro ended
			# there (frame counts drift apart between the two processes).
			if t_play < 0.0 and (saw_scene or frames >= 120):
				t_play = _secs()
			var t := _secs() - t_play if t_play >= 0.0 else 0.0
			if _once("lamp", t > 2.5):
				# Each phone draws the partner's flashlight tipped by the
				# partner's synced aim, not stuck level.
				var seen := 0
				for p in get_nodes_in_group("players"):
					if not p.is_multiplayer_authority():
						seen += 1
						var lamp: float = p.flashlight.rotation.x
						print(role, ": partner's lamp pitch %.2f (synced %.2f)" % [lamp, p.sync_lamp.x])
						if lamp > -0.35 or absf(lamp - p.sync_lamp.x) > 0.05:
							print(role, " LAMP SYNC FAILED")
							quit(1)
							return false
				if seen == 0:
					print(role, " LAMP SYNC FAILED: no partner in the level")
					quit(1)
					return false
			# Both press the middle of the co-op vault door, the host first and
			# the partner 0.9 s later (inside the door's 1.5 s window): each
			# takes a free wheel, it stays shut for one alone, and opens for both.
			if _once("host_press", t > 3.0 and role == "host") or _once("join_press", t > 3.9 and role == "join"):
				print(role, ": pressing the vault door at %.2f s" % t)
				for p in get_nodes_in_group("players"):
					if p.is_multiplayer_authority():
						get_first_node_in_group("level").get_node("Door_vault_door").interact(p, -2)
			var after_one := _once("check_one", t > 3.5)
			if after_one or _once("check_both", t > 5.5):
				var vault = get_first_node_in_group("level").get_node("Door_vault_door")
				print(role, ": vault door open after %s: %s" % ["one press" if after_one else "both", vault.is_open])
				if vault.is_open == after_one:
					print(role, " COOP DOOR FAILED")
					quit(1)
					return false
			if not _once("finish", t > 7.5 and frames >= 240):
				return false
			var after := []
			for p in get_nodes_in_group("players"):
				after.append("%s(%d)@%s" % [p.character, p.peer_id, p.global_position.snapped(Vector3.ONE * 0.1)])
			print(role, ": after move ", after)
			if not outfits_ok:
				print(role, " OUTFIT SYNC FAILED")
				quit(1)
				return false
			print(role, " COOP OK")
			quit(0)
	return false
