extends SceneTree
## Co-op save slots, two copies of the game through the relay. The joiner
## opens Save from its pause menu: the slot screen shows the HOST's slots (the
## host writes the save), the joiner picks Slot 3, the host saves there and
## sends the save over. The joiner's own Slot 3 holds a different game, so its
## copy goes into its first free slot instead. Then the host saves into Slot 2
## and the joiner's copy lands in Slot 2 too (free on both phones), the same
## save on both. Each copy of the game uses its own save folder (two copies
## on one machine share user://).
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_saves.gd -- host
## join: same with -- join
## Prints COOP SAVES OK on each side.

var role := ""
var fails: Array[String] = []
var GS: Node
var SAVE: Node
var NET: Node
var DIR := ""

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	SAVE = root.get_node("SaveSystem")
	NET = root.get_node("Net")
	DIR = "user://saves_coop_" + role
	_run.call_deferred()
	# A hard stop, whatever happens.
	create_timer(150.0, true).timeout.connect(func():
		print(role, " TIMEOUT")
		quit(1))

func _fail(msg: String) -> void:
	fails.append(msg)
	print(role, " FAIL: ", msg)

func _wait(sec: float) -> void:
	await create_timer(sec, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)

func _find(n: Node, cond: Callable) -> Node:
	if cond.call(n):
		return n
	for c in n.get_children():
		var f := _find(c, cond)
		if f:
			return f
	return null

func _run() -> void:
	SAVE.save_dir = DIR
	_clean()
	await _frames(2)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(8)
	if role == "join":
		# The joiner's own game in its Slot 3: a co-op copy must not land on it.
		FileAccess.open(DIR + "/slot3.json", FileAccess.WRITE).store_string(JSON.stringify({"version": 2,
			"timestamp": "2026-11-10T09:00:00", "run_id": "JOINERS-OWN-RUN", "level": GS.FIRST_LEVEL,
			"checkpoint": "hall", "flags": {"story_intro": true}, "party": ["obcera"]}))
		await _wait(1.5)
		NET.join_online("SAVE42", "obcera")
	else:
		GS.reset_run()
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			current_scene._start_coop.rpc(GS.level_path, "start", {"story_intro": true}))
		NET.host_online("zegan", "SAVE42")
	# Both in the level.
	var t := 0.0
	while t < 60.0 and (get_first_node_in_group("level") == null or get_nodes_in_group("players").size() < 2):
		await _wait(0.25)
		t += 0.25
	if get_nodes_in_group("players").size() < 2:
		_fail("never got both survivors into the level")
		await _finish()
		return
	await _wait(2.0)
	if role == "join":
		await _joiner()
	else:
		await _host()
	await _finish()

func _joiner() -> void:
	var hud := get_first_node_in_group("hud")
	hud.toggle_pause()
	await _frames(2)
	var save_btn: Button = _find(hud, func(x): return x is Button and x.text == "Save game")
	save_btn.pressed.emit()
	# The host's slot list arrives over the relay.
	var screen: Node = null
	var t := 0.0
	while t < 6.0:
		screen = _find(hud, func(x): return x.has_signal("picked"))
		if screen and not screen._waiting:
			break
		await _wait(0.2)
		t += 0.2
	if screen == null or screen._waiting:
		_fail("the save screen never got the host's slots")
		return
	var c3: Button = screen._grid.get_node_or_null("Card_slot3")
	if c3 == null:
		_fail("no Slot 3 card on the joiner's save screen")
		return
	# The host's Slot 3 is empty: no question, it saves straight away. (Had the
	# screen shown this phone's own Slot 3, it would ask to save over it.)
	c3.pressed.emit()
	await _frames(3)
	if is_instance_valid(screen) and _find(screen, func(x): return x is Button and x.text == "Save over it") != null:
		_fail("the joiner's save screen showed its own Slot 3, not the host's")
		return
	await _wait(3.0)
	var mine: Dictionary = SAVE.read_slot("slot3")
	if mine.get("run_id") != "JOINERS-OWN-RUN":
		_fail("the host's save landed on the joiner's other game in Slot 3 (now run %s)" % mine.get("run_id"))
	var copy: Dictionary = SAVE.read_slot("slot1")
	if copy.is_empty() or copy.get("run_id", "") == "JOINERS-OWN-RUN" or copy.get("checkpoint") != GS.shared_checkpoint:
		_fail("the copy of the host's save isn't in the joiner's first free slot: %s" % copy)
	else:
		print("join: copy of the host's Slot 3 save is in Slot 1 here, run ", copy.get("run_id"))
	if not "Slot 1" in hud._toast.text:
		_fail("the joiner wasn't told where the copy went: '%s'" % hud._toast.text)
	# Then the host saves into Slot 2 by itself: free here too, same slot.
	await _wait(5.0)
	var s2: Dictionary = SAVE.read_slot("slot2")
	if s2.is_empty() or s2.get("run_id") != copy.get("run_id"):
		_fail("the host's Slot 2 save didn't arrive in the joiner's Slot 2: %s" % s2)
	else:
		print("join: host's Slot 2 save is in Slot 2 here")
	var host_s2 := _read_other("slot2")
	if host_s2.is_empty() or JSON.stringify(host_s2) != JSON.stringify(s2):
		_fail("the joiner's Slot 2 differs from the host's")
	if SAVE.has_slot("autosave"):
		_fail("an autosave appeared on the joiner's phone at the start spot")

func _host() -> void:
	await _wait(5.0)
	var s3: Dictionary = SAVE.read_slot("slot3")
	if s3.is_empty() or s3.get("run_id") != GS.run_id:
		_fail("the joiner's Save didn't write the host's Slot 3: %s" % s3)
	else:
		print("host: the joiner's save is in the host's Slot 3, party ", s3.get("party"))
	if s3.get("party", []).size() != 2:
		_fail("the co-op save doesn't list both survivors: %s" % s3.get("party"))
	SAVE.request_save("slot2")
	await _wait(1.0)
	if not SAVE.has_slot("slot2"):
		_fail("the host's own save into Slot 2 wrote nothing")
	await _wait(6.0)

## The other copy's save folder (same machine).
func _read_other(slot: String) -> Dictionary:
	var other := "user://saves_coop_" + ("host" if role == "join" else "join")
	var path := "%s/%s.json" % [other, slot]
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

func _finish() -> void:
	print(role, " COOP SAVES OK" if fails.is_empty() else " COOP SAVES FAILED")
	# Stay connected a little so the other copy can finish its checks.
	await _wait(5.0)
	_clean()
	quit(0 if fails.is_empty() else 1)
