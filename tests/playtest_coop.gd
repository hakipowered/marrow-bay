extends SceneTree
## Co-op playtest: two copies of the game talking through the relay, Zegan
## hosting and Obcera joining, checking what only shows up with two phones.
##  1. A resumed co-op game gives the partner their saved bag (not a fresh
##     starting kit).
##  2. After the intro (both tap Skip), each survivor moves on their own:
##     the one walking plays a walk or run clip, the one standing idles, on
##     both phones (they used to share one animation after a cutscene).
##  3. The co-op door: one survivor at a handle doesn't open it; both do.
##  4. Both go down, both press Continue: the level reloads at the checkpoint
##     with the bags as they were there, on both phones.
## Prints "COOP ok/FAIL <what>" lines and "PLAYTEST COOP DONE n fails".
##
## node relay/local_relay.js   (npm i ws first), then both of:
## RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/playtest_coop.gd -- host
## RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/playtest_coop.gd -- join
## tools/playtest.sh runs it with the rest.

const CODE := "QAPT42"
var role := ""
var fails: Array = []
var GS: Node
var NET: Node
var CUTS: Node
var CHEATS: Node
var SAVE: Node

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	NET = root.get_node("Net")
	CUTS = root.get_node("Cutscenes")
	CHEATS = root.get_node("Cheats")
	SAVE = root.get_node("SaveSystem")
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

func _mine() -> Node:
	for p in get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null

func _player(who: String) -> Node:
	for p in get_nodes_in_group("players"):
		if p.character == who:
			return p
	return null

func _door(id: String) -> Node:
	for d in get_nodes_in_group("doors"):
		if d.door_id == id:
			return d
	return null

## The bags the host "saved": Obcera found the shotgun, the quill key and a
## second herb; Zegan carries a red herb.
func _saved_bags() -> Dictionary:
	var Inv: GDScript = load("res://scripts/player/inventory.gd")   # (a class name reference wouldn't compile under --script)
	var o = Inv.new()
	o.add_weapon("m12")
	o.add_ammo("shells", 10)
	o.add_item("herb_green", 1)
	o.add_key("brass_quill_key")
	var z = Inv.new()
	z.add_item("herb_red", 1)
	return {"obcera": o.to_dict(), "zegan": z.to_dict()}

func _main() -> void:
	GS.reset_run()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.0)
	if role == "host":
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			GS.inventories = _saved_bags()
			current_scene._start_coop.rpc(GS.level_path, "start", {}, GS.inventories))
		NET.host_online("zegan", CODE)
	else:
		await _wait(2.5)
		NET.join_online(CODE, "obcera")
	if not await _until(func(): return get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2, 40.0):
		_check(false, "both survivors in the level")
		return _finish()
	var level: Node = get_first_node_in_group("level")
	await _wait(2.0)

	# 1. The partner's saved bag.
	var ob: Node = _player("obcera")
	_check(ob.inventory.has_weapon("m12") and ob.inventory.key_items.has("brass_quill_key"),
		"Obcera has her saved bag (shotgun, quill key) on the %s's phone" % role)
	_check(_player("zegan").inventory.count("herb_red") == 1, "Zegan has his saved red herb on the %s's phone" % role)
	var herbs0: int = ob.inventory.count("herb_green")

	# 2. The intro, skipped by both, then each moves on their own.
	await _until(func(): return CUTS.active, 8.0)
	if CUTS.active:
		await _wait(1.5 if role == "host" else 2.5)
		CUTS._on_skip_pressed()
		await _until(func(): return not CUTS.active, 12.0)
	_check(not CUTS.active, "intro over on the %s's phone once both tapped Skip" % role)
	await _wait(1.0)
	CHEATS.set_cheat("god_mode", true)
	var me: Node = _mine()
	_check(not me.input_locked and not me.cutscene_pose, "the %s can move after the intro" % role)
	await _anim_check("zegan", "obcera")
	await _anim_check("obcera", "zegan")

	# 3. The co-op door into the records vault.
	var door: Node = _door("vault_door")
	if door == null:
		_check(false, "vault door exists")
	else:
		var hx := -7.35 if role == "host" else -4.65
		me.global_position = Vector3(hx, 0.05, 15.1)
		me.yaw = PI
		me.pitch = 0.0
		await _wait(0.6)
		var prompt: String = me._prompt_text
		_check(prompt.contains("partner"), "the %s sees 'Hold with partner' at a vault door handle (sees '%s')" % [role, prompt])
		if role == "host":
			me.interact()
			await _wait(1.0)
			_check(not door.is_open, "the vault door stays shut with only Zegan at a handle")
			for i in 10:
				me.interact()
				await _wait(0.5)
		else:
			await _wait(2.5)
			me.interact()
			await _wait(3.0)
		_check(door.is_open, "the vault door opened for both once both held it (%s's phone)" % role)
	await _wait(1.0)

	# 4. Both go down; Continue goes back to the checkpoint with the bags as
	# they were there (the herb Obcera uses now comes back).
	CHEATS.set_cheat("god_mode", false)
	await _wait(1.0)
	if role == "join":
		me.apply_damage(30.0)
		me.use_item("herb_green")
		_check(me.inventory.count("herb_green") == herbs0 - 1, "Obcera used a green herb (%d left)" % me.inventory.count("herb_green"))
	await _wait(1.5)
	me.apply_damage(9999.0)
	if not await _until(func(): return level.get("game_over"), 15.0):
		# The first one down waits for a rescue; the second one down ends it.
		me.apply_damage(9999.0)
		await _until(func(): return level.get("game_over"), 10.0)
	_check(level.get("game_over"), "game over on the %s's phone once both were down" % role)
	await _wait(4.0)
	level.vote_continue()
	if not await _until(func():
			var l: Node = get_first_node_in_group("level")
			return l != null and l != level and is_instance_valid(l) and get_nodes_in_group("players").size() == 2, 25.0):
		_check(false, "the level reloaded after both pressed Continue (%s)" % role)
		return _finish()
	await _wait(2.0)
	ob = _player("obcera")
	_check(ob.inventory.count("herb_green") == herbs0 and ob.inventory.has_weapon("m12"),
		"after Continue Obcera has her checkpoint bag back on the %s's phone (green herbs %d, %d at the checkpoint)" % [role, ob.inventory.count("herb_green"), herbs0])
	_check(GS.shared_checkpoint == "start", "back at the start checkpoint on the %s's phone" % role)
	_finish()

## `walker` walks for two seconds while `stander` stands; on this phone the
## walker's model plays a moving clip and the stander's plays idle.
func _anim_check(walker: String, stander: String) -> void:
	var me: Node = _mine()
	if me.character == walker:
		me.move_input = Vector2(0, -1)
	await _wait(2.0)
	var w: Node = _player(walker)
	var s: Node = _player(stander)
	var wc: String = w.model._current
	var sc: String = s.model._current
	_check(wc.contains("walk") or wc.contains("run") or wc.contains("jog"), "on the %s's phone %s walking plays '%s'" % [role, walker, wc])
	_check(not (sc.contains("walk") or sc.contains("run") or sc.contains("jog")), "on the %s's phone %s standing plays '%s'" % [role, stander, sc])
	me.move_input = Vector2.ZERO
	await _wait(1.0)

var _quitting := false

func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	print("%s PLAYTEST COOP DONE %d fails" % [role, fails.size()])
	for f in fails:
		print("  - ", f)
	# Stay connected a little so the other copy finishes its own checks.
	await _wait(5.0)
	quit(0 if fails.is_empty() else 1)
