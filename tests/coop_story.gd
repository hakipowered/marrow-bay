extends SceneTree
## Two-process co-op cutscene test through the relay: the intro starts on both
## phones, one player's Skip only shows "Waiting for partner...", and the scene
## ends for both once the second player taps Skip too.
## node relay/local_relay.js, then:
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_story.gd -- host
## join: same with -- join
var role := ""
var frames := 0
var stage := 0
var t0 := 0
var t_level := 0.0
var cs: Node
var ok := true

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	t0 = Time.get_ticks_msec()

func _secs() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0

func _check(cond: bool, what: String) -> void:
	print(role, (": ok   " if cond else ": FAIL ") + what)
	ok = ok and cond

func _start_later() -> void:
	await create_timer(1.0).timeout
	var gs = root.get_node("GameState")
	current_scene._start_coop.rpc(gs.level_path, "start", {})

func _process(_d: float) -> bool:
	frames += 1
	var net = root.get_node("Net")
	cs = root.get_node("Cutscenes")
	if _secs() > 60.0:
		print(role, " TIMEOUT stage ", stage)
		quit(1)
	match stage:
		0:
			if frames == 2:
				root.get_node("GameState").reset_run()
				change_scene_to_file("res://scenes/main_menu.tscn")
			if frames == 10:
				if role == "host":
					net.partner_joined.connect(func(_id): _start_later())
					net.host_online("zegan", "STRY42")
					stage = 1
			if role == "join" and frames > 10 and _secs() > 3.0:
				net.join_online("STRY42", "obcera")
				stage = 1
		1:
			if get_first_node_in_group("level") != null:
				stage = 2
				t_level = _secs()
		2:
			if _secs() - t_level > 4.0:
				_check(cs.active and cs.current == "intro", "intro playing on this phone")
				stage = 3
		3:
			# The host taps Skip first.
			if role == "host" and _secs() - t_level > 6.0:
				cs._on_skip_pressed()
				stage = 4
			elif role == "join" and _secs() - t_level > 8.0:
				_check(cs.active, "still playing after only the host tapped Skip")
				_check(cs._skip_hint.modulate.a > 0.5 and cs._skip_hint.text == "Your partner wants to skip", "sees 'Your partner wants to skip'")
				cs._on_skip_pressed()
				stage = 5
		4:
			if _secs() - t_level > 7.5 and stage == 4:
				_check(cs.active, "still playing after only my Skip")
				_check(cs._skip_btn.text == "Waiting for partner...", "button says 'Waiting for partner...'")
				stage = 5
		5:
			if _secs() - t_level > 12.0:
				_check(not cs.active, "intro ended once both tapped Skip")
				_check(root.get_node("GameState").has_flag("story_intro"), "intro flag set on this phone")
				var p = null
				for pl in get_nodes_in_group("players"):
					if pl.is_multiplayer_authority():
						p = pl
				_check(p != null and not p.input_locked, "my player can move again")
				print(role, " COOP STORY ", "OK" if ok else "FAILED")
				quit(0 if ok else 1)
	return false
