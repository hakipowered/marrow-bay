extends SceneTree
## Co-op call-outs (CALL button, the picker, a scream) with two copies of the
## game through the relay: Zegan hosts, Obcera joins, and Zegan stands out on
## Ashgrove Street and Obcera in the Great Hall, about 41 m apart.
##  1. Every call-out line has its recording.
##  2. Each one's call reaches the other phone: the partner's phone voices it
##     from the caller's body (their line, on the Voice bus, playing), shows
##     the subtitle, and it's loud enough there: no quieter than -10 dB for
##     a normal call (-7 for a scream) from 41 m away.
##  3. A quick tap of CALL (a random normal line), a picked line and a
##     scream all go through; the caller hears their own too.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_callouts.gd -- host
## join: same with -- join.   tools/playtest.sh runs it with the rest.
## Prints "COOP ok/FAIL ..." lines and "COOP CALLOUTS DONE n fails".

const CODE := "QACA77"
var role := ""
var fails: Array = []
var GS: Node
var NET: Node
var CHEATS: Node
var CALLS: Node
var heard: Array = []   # [speaker peer, character, line id, text, scream, voice node or null]

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	NET = root.get_node("Net")
	CHEATS = root.get_node("Cheats")
	CALLS = root.get_node("CallOuts")
	create_timer(150.0).timeout.connect(func():
		print(role, " COOP FAIL timed out")
		quit(1))
	_main.call_deferred()

func _check(cond: bool, what: String) -> void:
	print("%s COOP %s %s" % [role, "ok  " if cond else "FAIL", what])
	if not cond:
		fails.append(what)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _until(cond: Callable, max_t: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_t * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return false

func _sync(step: String) -> void:
	GS.share_flag("qa_sync:%s:%s" % [step, role])
	var other := "join" if role == "host" else "host"
	if not await _until(func(): return GS.has_flag("qa_sync:%s:%s" % [step, other]), 30.0):
		_check(false, "%s: the other phone reached '%s'" % [role, step])

func _player(who: String) -> Node:
	for p in get_nodes_in_group("players"):
		if p.character == who:
			return p
	return null

## Every call heard on this phone, with the voice it played (if any).
func _on_call(speaker: int, character: String, line_id: String, text: String, scream: bool) -> void:
	var voice: Node = null
	var body := _player(character)
	if body:
		for c in body.get_children():
			if c is AudioStreamPlayer3D and c.stream and c.stream.resource_path.ends_with("/%s.ogg" % line_id):
				voice = c
	heard.append([speaker, character, line_id, text, scream, voice])

## How loud a 3D voice is at this phone's ears (dB, before the bus).
func _loudness(a: AudioStreamPlayer3D) -> float:
	var ear: Camera3D = root.get_viewport().get_camera_3d()
	var d := ear.global_position.distance_to(a.global_position)
	return minf(linear_to_db(a.unit_size / maxf(d, 0.001)) + a.volume_db, a.max_db)

## The partner's call `line` (or any of theirs) reached this phone properly.
func _expect_from(who: String, line: String, scream: bool, what: String, since: int) -> void:
	var fits := func(x: Array) -> bool: return x[1] == who and (line == "" or x[2] == line)
	var ok := await _until(func(): return heard.slice(since).any(fits), 6.0)
	_check(ok, "%s's phone heard %s (%s)" % [role, what, who.capitalize()])
	if not ok:
		return
	var h: Array = heard.slice(since).filter(fits)[0]
	var body: Node = _player(who)
	_check(int(h[0]) == body.peer_id, "it came from %s's phone (peer %d)" % [who.capitalize(), h[0]])
	_check(bool(h[4]) == scream, "as a %s" % ("scream" if scream else "normal call"))
	var a: AudioStreamPlayer3D = h[5]
	_check(a != null, "%s's voice played from %s on the %s's phone (%s)" % [who.capitalize(), who.capitalize(), role, h[2]])
	if a != null:
		_check(a.bus == &"Voice" and a.playing, "on the Voice bus, playing")
		var db := _loudness(a)
		var floor_db := -7.0 if scream else -10.0
		var ear: Vector3 = root.get_viewport().get_camera_3d().global_position
		_check(db >= floor_db, "loud enough %.0f m away: %.1f dB (at least %.0f; ears at %s, voice at %s)" % [ear.distance_to(a.global_position), db, floor_db, ear, a.global_position])
	var hud: Node = get_first_node_in_group("hud")
	var sub: Label = hud.get("_subtitle") if hud else null
	_check(sub != null and sub.text == "%s: %s" % [who.capitalize(), h[3]], "the subtitle reads '%s'" % (sub.text if sub else "?"))

func _main() -> void:
	GS.reset_run()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.0)
	if role == "host":
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			current_scene._start_coop.rpc(GS.level_path, "start", {"story_intro": true}, {}, "normal"))
		NET.host_online("zegan", CODE)
	else:
		await _wait(2.5)
		NET.join_online(CODE, "obcera")
	if not await _until(func(): return get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2, 40.0):
		_check(false, "both survivors in the level (scene %s, level %s, players %s)" % [current_scene.name if current_scene else "?", get_first_node_in_group("level") != null, get_nodes_in_group("players").map(func(p): return p.character)])
		_finish()
		return
	await _wait(2.5)
	if role == "host":
		CHEATS.set_cheat("god_mode", true)
	CALLS.callout_played.connect(_on_call)
	var me: Node = _player("zegan" if role == "host" else "obcera")
	var them: String = "obcera" if role == "host" else "zegan"

	# 1. Every line has its recording.
	var missing: Array = []
	for who in ["zegan", "obcera"]:
		for scream in [false, true]:
			for l in CALLS.lines_for(who, scream):
				if not ResourceLoader.exists("res://assets/audio/voice/%s/%s.ogg" % [who, l["id"]]):
					missing.append(l["id"])
	_check(missing.is_empty(), "every call-out line has its recording (missing %s)" % [missing])

	# Far apart: Zegan out on Ashgrove Street, Obcera in the Great Hall.
	me.global_position = Vector3(-13.0, 0.05, -21.5) if role == "host" else Vector3(9.0, 0.05, 13.0)
	me.velocity = Vector3.ZERO
	await _sync("apart")
	await _wait(1.5)
	var far: float = me.global_position.distance_to(_player(them).global_position)
	_check(far > 40.0, "the two stand %.0f m apart on the %s's phone" % [far, role])

	# 2. A picked line from Zegan, then a scream from Obcera, then a quick tap
	# of CALL from each.
	# (Each phone notes how many calls it had heard before each step: the
	# partner's call can arrive before this phone gets there.)
	var n := heard.size()
	if role == "host":
		CALLS.call_partner(false, "z_over_here")
	await _expect_from("zegan", "z_over_here", false, "Zegan's 'Obcera, over here.'", n)
	n = heard.size()
	await _sync("picked")
	await _wait(1.6)   # past the call cooldown
	if role == "join":
		CALLS.call_partner(true, "o_zegaan")
	await _expect_from("obcera", "o_zegaan", true, "Obcera's scream 'ZEGAAAN!'", n)
	n = heard.size()
	await _sync("scream")
	await _wait(1.6)
	var hud: Node = get_first_node_in_group("hud")
	if role == "host":
		# The CALL button as a quick tap (down and up at once).
		hud._call_btn.button_down.emit()
		hud._call_btn.button_up.emit()
	await _expect_from("zegan", "", false, "a quick tap of Zegan's CALL", n)
	n = heard.size()
	await _sync("tap_z")
	await _wait(1.6)
	if role == "join":
		hud._call_btn.button_down.emit()
		hud._call_btn.button_up.emit()
	await _expect_from("obcera", "", false, "a quick tap of Obcera's CALL", n)
	await _sync("done")
	_finish()

var _quitting := false

func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	print("%s COOP CALLOUTS DONE %d fails" % [role, fails.size()])
	for f in fails:
		print("  - ", f)
	await _wait(5.0)
	quit(0 if fails.is_empty() else 1)
