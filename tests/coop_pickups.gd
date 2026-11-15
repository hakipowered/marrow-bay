extends SceneTree
## Co-op items, enemies and difficulty, two copies of the game through the
## relay: Zegan hosts a new game on Hard, Obcera joins.
##  1. The joiner plays the host's difficulty, and both phones build the same
##     extra infected (Hard co-op brings every tier).
##  2. Supplies are each survivor's own: Zegan takes the street ammo, it's
##     gone on his phone and still there on hers; she takes hers too. Both
##     reach for the courtyard shotgun at once and both get one. Each box
##     holds Hard's amount. The host keeps both finds for its saves.
##  3. Keys and files are found once, for both: she picks up a key, it's in
##     both bags and he can open the door it fits; he picks up the Great Hall
##     file and she has it too. The office key on the desk is one of those.
##  4. What an infected or a crate leaves: one for her lies only on her
##     phone; a survivor's dropped item is one copy on both phones, under the
##     same name; the host's loot rolls give each survivor their own finds.
##  5. Hard: a blow and a grab's squeeze hurt more, her own burning doesn't;
##     a downed survivor has 20 seconds.
##  6. The host's save holds both survivors' finds and the difficulty.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_pickups.gd -- host
## join: same with -- join.   tools/playtest.sh runs it with the rest.
## Prints "COOP ok/FAIL ..." lines and "COOP PICKUPS DONE n fails".

const CODE := "QAPK42"
var role := ""
var fails: Array = []
var GS: Node
var NET: Node
var CHEATS: Node
var SAVE: Node
var level: Node

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	NET = root.get_node("Net")
	CHEATS = root.get_node("Cheats")
	SAVE = root.get_node("SaveSystem")
	create_timer(170.0).timeout.connect(func():
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

## Both phones at the same step before going on (each says so through a
## shared flag and waits for the other's).
func _sync(step: String) -> void:
	GS.share_flag("qa_sync:%s:%s" % [step, role])
	var other := "join" if role == "host" else "host"
	if not await _until(func(): return GS.has_flag("qa_sync:%s:%s" % [step, other]), 30.0):
		_check(false, "%s: the other phone reached '%s'" % [role, step])

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

func _item(pid: String) -> Node:
	var n: Node = level.get_node_or_null("Pickup_" + pid)
	return n if n != null and is_instance_valid(n) and not n.is_queued_for_deletion() else null

## Stands right by an item (so it's the one in reach whichever way she
## faces) and takes it through the prompt, as the button would.
func _take(pid: String, side := 0.3) -> bool:
	var me: Node = _mine()
	var it: Node = _item(pid)
	if it == null:
		_check(false, "%s: %s is there to take" % [role, pid])
		return false
	me.global_position = Vector3(it.global_position.x + side, me.global_position.y if absf(it.global_position.y - me.global_position.y) < 0.6 else it.global_position.y - 0.8, it.global_position.z + 0.25)
	await _wait(0.3)
	me._update_focus()
	var prompt: String = me._prompt_text
	_check(prompt.begins_with("Pick up") and me._focus == it, "%s sees '%s' at %s" % [role, prompt, pid])
	me.interact()
	await _wait(0.2)
	return true

func _main() -> void:
	GS.reset_run()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.0)
	if role == "host":
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			GS.set_difficulty("hard")
			current_scene._start_coop.rpc(GS.level_path, "start", {"story_intro": true}, {}, "hard"))
		NET.host_online("zegan", CODE)
	else:
		await _wait(2.5)
		NET.join_online(CODE, "obcera")
	if not await _until(func(): return get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2, 40.0):
		_check(false, "both survivors in the level")
		return _finish()
	level = get_first_node_in_group("level")
	await _wait(2.5)
	CHEATS.set_cheat("god_mode", true)
	var me: Node = _mine()

	# 1. Difficulty and the extra infected.
	_check(GS.difficulty == "hard", "the %s plays on Hard (%s)" % [role, GS.difficulty])
	_check(GS.pressure() == 3, "Hard co-op is the highest pressure on the %s's phone (%d)" % [role, GS.pressure()])
	var extras: Array = level.ExtraInfected.for_level(level.scene_file_path)
	var missing := extras.filter(func(e): return level.get_node_or_null(NodePath(e["name"])) == null)
	_check(not extras.is_empty() and missing.is_empty(), "every extra infected is in the street level on the %s's phone (%d listed, missing %s)" % [role, extras.size(), missing.map(func(e): return e["name"])])

	# 2. Supplies: his first, then hers, from the same box.
	var box := "street_ammo_1"
	var nine0: int = me.inventory.ammo_count("9mm")
	if role == "host":
		await _take(box)
		_check(me.inventory.ammo_count("9mm") == nine0 + 11, "Zegan got Hard's 11 rounds (%d -> %d)" % [nine0, me.inventory.ammo_count("9mm")])
		_check(_item(box) == null, "the box is gone on Zegan's phone once he took it")
		await _wait(3.5)
		_check(GS.has_flag("taken:%s:obcera" % box), "the host knows Obcera took her box too (for its saves)")
	else:
		await _wait(2.0)
		_check(_item(box) != null, "Obcera still sees her own box after Zegan took his")
		_check(GS.has_flag("taken:%s:zegan" % box), "her phone knows he took his")
		await _take(box)
		_check(me.inventory.ammo_count("9mm") == nine0 + 11, "Obcera got her own 11 rounds (%d -> %d)" % [nine0, me.inventory.ammo_count("9mm")])
		_check(_item(box) == null, "the box is gone on her phone once she took it")
		await _wait(1.5)
	# Both reach for the courtyard shotgun at the same moment.
	await _wait(1.0)
	await _take("court_m12", 0.35 if role == "host" else -0.35)
	await _wait(1.0)
	_check(me.inventory.has_weapon("m12"), "%s has a shotgun of their own" % me.character.capitalize())
	await _wait(1.5)
	var partner: Node = _player("obcera" if role == "host" else "zegan")
	_check(partner.inventory.has_weapon("m12"), "on the %s's phone the partner has one too (bags sync)" % role)

	# 3. A key and a file: found once, for both. A key and its door of our
	# own, so no story scene gets in the way.
	var spot: Vector3 = Vector3(-3.0, 0.1, -20.0)
	level.place_pickup("key:qa_key", spot, "qa_key")
	var door: Node = level.place_door(Vector3(-12.0, 0, -20.0), 90, 2, "wood_panel", 1.1, 2.2, "qa_door", "qa_key")   # Door.Kind.LOCKED
	_check(_item("qa_key") != null and _item("qa_key").share == "party", "a key lies there for both (party) on the %s's phone" % role)
	var office_key: Node = _item("brass_quill_key")
	_check(office_key != null and office_key.share == "party", "the office's Brass Quill key is a party item")
	var shells: Node = _item("court_shells")
	_check(shells != null and shells.share == "personal", "shells are each survivor's own")
	await _sync("keys")
	if role == "join":
		await _take("qa_key")
	await _wait(2.5)
	var z: Node = _player("zegan")
	var o: Node = _player("obcera")
	_check(_item("qa_key") == null, "the key is gone from the floor on the %s's phone" % role)
	_check(me.inventory.key_items.has("qa_key"), "%s carries the key Obcera found (%s's phone)" % [me.character.capitalize(), role])
	if role == "host":
		_check(door.interact_text(z).begins_with("Open"), "Zegan can open the door her key fits ('%s')" % door.interact_text(z))
		await _take("hall_file_1")
	await _wait(2.5)
	_check(me.inventory.files.has("shelter_log"), "%s has the Great Hall file Zegan found" % me.character.capitalize())
	_check(_item("hall_file_1") == null, "the file is gone from the desk on the %s's phone" % role)
	_check(z.inventory.key_items.has("qa_key") and o.inventory.key_items.has("qa_key"), "both bags show the key on the %s's phone" % role)

	# 4. Drops. Both phones count drops the same, so they name them the same.
	# (Counted before the meeting point: the host's drops can reach her phone
	# in the same moment as its "ready".)
	var c0: int = level._pickup_counter
	await _sync("drops")
	var at := Vector3(2.0, 0.05, -21.0)
	if role == "host":
		level.spawn_pickup.rpc("ammo:shells", at, -1, 2)          # for her only
		level.spawn_pickup.rpc("herb_green", at + Vector3(1, 0, 0), 1, 0)   # anyone's
	await _wait(1.5)
	var hers: Node = level.get_node_or_null("Drop_%d" % (c0 + 1))
	var anyone: Node = level.get_node_or_null("Drop_%d" % (c0 + 2))
	_check(level._pickup_counter == c0 + 2, "both drops counted on the %s's phone" % role)
	if role == "host":
		_check(hers == null, "her drop doesn't lie on Zegan's phone")
	else:
		_check(hers != null and hers.share == "personal", "her drop lies on her phone, hers alone")
	_check(anyone != null and anyone.share == "shared", "a dropped herb lies on the %s's phone under the same name" % role)
	await _wait(0.5)
	if role == "join" and hers != null:
		var s0: int = me.inventory.ammo_count("shells")
		hers.interact(me)
		_check(me.inventory.ammo_count("shells") == s0 + 4, "she took her 4 Hard shells (%d -> %d)" % [s0, me.inventory.ammo_count("shells")])
	if role == "host" and anyone != null:
		anyone.interact(me)
	await _wait(2.0)
	_check(level.get_node_or_null("Drop_%d" % (c0 + 2)) == null, "the shared herb is gone on the %s's phone once Zegan took it" % role)
	# The host's loot rolls: each survivor gets their own.
	var c1: int = level._pickup_counter
	await _sync("loot")
	if role == "host":
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 30:
			level.drop_loot("brute", Vector3(-2.0 + i * 0.2, 0.05, -26.5), rng)
	await _wait(2.0)
	var own := 0
	for k in range(c1 + 1, level._pickup_counter + 1):
		var d: Node = level.get_node_or_null("Drop_%d" % k)
		if d != null:
			_check(d.share == "personal", "every loot drop on the %s's phone is personal (%s)" % [role, d.name])
			own += 1
	_check(own >= 3 and own <= 20, "the %s's survivor got a fair share of 30 Hard co-op rolls (%d)" % [role, own])
	_check(level._pickup_counter > c1, "the %s's phone counted the loot (%d)" % [role, level._pickup_counter - c1])

	# 5. Hard hurts more; burning doesn't change. (God mode off on this phone
	# only: the cheat is the party's, and the other phone runs its own checks.)
	CHEATS._apply("god_mode", false)
	var zz: Node = level.get_node_or_null("Z_street_1")
	me.hp = me.max_hp
	me.apply_damage(20.0, zz)
	_check(is_equal_approx(me.hp, me.max_hp - 30.0), "on Hard a 20 blow takes 30 (%s's phone, hp %.1f)" % [role, me.hp])
	me.hp = me.max_hp
	me.apply_damage(8.0, null, true)
	_check(is_equal_approx(me.hp, me.max_hp - 12.0), "a grab's 8 squeeze takes 12 on Hard (hp %.1f)" % me.hp)
	me.hp = me.max_hp
	me.apply_damage(3.0)
	_check(is_equal_approx(me.hp, me.max_hp - 3.0), "her own burning stays 3 (hp %.1f)" % me.hp)
	me.hp = me.max_hp
	me.health_changed.emit(me.hp, me.max_hp)
	_check(is_equal_approx(me.revive_window(), 20.0), "Hard gives 20 seconds to reach a downed partner (%s)" % role)
	CHEATS._apply("god_mode", true)

	# 6. The host's save.
	await _wait(1.5)
	if role == "host":
		var snap: Dictionary = SAVE.build_snapshot()
		var flags: Dictionary = snap.get("flags", {})
		_check(snap.get("difficulty", "") == "hard", "the save says Hard")
		_check(flags.has("taken:street_ammo_1:zegan") and flags.has("taken:street_ammo_1:obcera"), "the save remembers both took their street ammo")
		_check(flags.has("taken:qa_key") and flags.has("taken:hall_file_1"), "the save remembers the key and the file are gone")
		var bag: Dictionary = snap.get("inventories", {}).get("obcera", {})
		_check("m12" in str(bag.get("slots", [])) and "qa_key" in bag.get("keys", []) and "shelter_log" in bag.get("files", []),
			"the save has Obcera's own shotgun, the key and the file in her bag")
	_finish()

var _quitting := false

func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	print("%s COOP PICKUPS DONE %d fails" % [role, fails.size()])
	for f in fails:
		print("  - ", f)
	await _wait(5.0)
	quit(0 if fails.is_empty() else 1)
