extends SceneTree
## The item box in co-op, two copies of the game through the relay. The host
## starts the run with a shotgun and 40 rounds of 9mm already in the box: both
## phones have them on arrival. Both open the office box at once (the lid is up
## on both phones while either has it open). The joiner puts her fern in; the
## host sees it. Both go for the shotgun at the same moment: exactly one of
## them gets it. The joiner takes all the 9mm; the host sees the box without it
## and her bag with it. The host saves: the save on both phones carries the
## box. The joiner closes up; the host closes too, and the lid comes down.
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_item_box.gd -- host
## join: same with -- join
## Prints COOP ITEM BOX OK on each side.

const START_BOX := [["m12", 1, 4], ["ammo:9mm", 40, 0]]
var role := ""
var fails: Array[String] = []
var GS: Node
var SAVE: Node
var NET: Node
var DIR := ""
var store: Node
var box: Node
var hud: Node
var me: Node
var t0 := 0.0

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	SAVE = root.get_node("SaveSystem")
	NET = root.get_node("Net")
	DIR = "user://saves_coop_box_" + role
	_run.call_deferred()
	create_timer(170.0, true).timeout.connect(func():
		print(role, " TIMEOUT")
		quit(1))

func _fail(msg: String) -> void:
	fails.append(msg)
	print(role, " FAIL: ", msg)

func _wait(sec: float) -> void:
	await create_timer(sec, true).timeout

## Waits until sec seconds after both survivors were in the level.
func _at(sec: float) -> void:
	var left := t0 + sec - Time.get_ticks_msec() / 1000.0
	if left > 0.0:
		await _wait(left)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)

func _ints(a: Array) -> Array:
	return a.map(func(e): return [str(e[0]), int(e[1]), int(e[2])])

func _slot_of(p: Node, id: String) -> int:
	for i in p.inventory.slots.size():
		var s = p.inventory.slots[i]
		if s != null and s["id"] == id:
			return i
	return -1

func _box_index(id: String) -> int:
	var list: Array = store.sorted()
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1

func _run() -> void:
	SAVE.save_dir = DIR
	SAVE.autosave_enabled = false
	_clean()
	store = GS.item_box
	await _frames(2)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(8)
	if role == "join":
		await _wait(1.5)
		NET.join_online("BXK742", "obcera")
	else:
		GS.reset_run()
		store.from_save(START_BOX)
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			var flags := {}
			for beat in ["intro", "gates", "warden", "glass"]:
				flags["story_" + beat] = true
			current_scene._start_coop.rpc(GS.FIRST_LEVEL, "safe_office", flags, {}, "", store.to_save()))
		NET.host_online("zegan", "BXK742")
	var t := 0.0
	while t < 60.0 and (get_first_node_in_group("level") == null or get_nodes_in_group("players").size() < 2):
		await _wait(0.25)
		t += 0.25
	if get_nodes_in_group("players").size() < 2:
		_fail("never got both survivors into the level")
		await _finish()
		return
	await _wait(2.0)
	t0 = Time.get_ticks_msec() / 1000.0
	hud = get_first_node_in_group("hud")
	for p in get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			me = p
	for b in get_nodes_in_group("item_boxes"):
		if "office" in str(b.name):
			box = b
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	if box == null:
		_fail("no item box in the office")
		await _finish()
		return
	if JSON.stringify(_ints(store.to_save())) != JSON.stringify(START_BOX):
		_fail("the box on arrival is %s, not the host's %s" % [store.to_save(), START_BOX])
	else:
		print(role, ": box on arrival: ", store.to_save())
	# Both stand at the box and open it.
	var n: Vector3 = box.global_transform.basis.z
	me.global_position = Vector3(box.global_position.x, 0.05, box.global_position.z) + n * 1.2 + box.global_transform.basis.x * (0.5 if role == "host" else -0.5)
	hud.open_item_box(box)
	await _frames(3)
	var menu: Node = hud._box_menu
	if menu == null or not menu.visible:
		_fail("the box screen didn't open")
		await _finish()
		return
	if paused:
		_fail("co-op: the box screen paused the world")
	if role == "join":
		await _joiner(menu)
	else:
		await _host(menu)
	await _finish()

func _joiner(menu: Node) -> void:
	await _at(1.0)
	var herb := _slot_of(me, "herb_green")
	if herb < 0:
		_fail("the joiner has no fern to put in")
	else:
		menu._on_slot(herb)
		menu._on_slot(herb)
	await _at(5.0)
	if store.count("herb_green") != 1:
		_fail("the joiner's own box view doesn't show her fern: %s" % [store.to_save()])
	# Both go for the shotgun now.
	var bi := _box_index("m12")
	if bi >= 0:
		menu._on_box_slot(bi)
		menu._take(false)
	await _at(9.0)
	print("join: shotgun in my bag: ", me.inventory.count("m12"), ", box: ", store.to_save())
	if store.count("m12") != 0:
		_fail("the shotgun is still in the joiner's view of the box")
	# All the 9mm.
	var before: int = me.inventory.ammo_count("9mm")
	bi = _box_index("ammo:9mm")
	if bi < 0:
		_fail("no 9mm in the joiner's view of the box")
	else:
		menu._on_box_slot(bi)
		menu._take(true)
	await _at(12.0)
	if me.inventory.ammo_count("9mm") - before != 40:
		_fail("the joiner took %d rounds of 9mm, not 40" % (me.inventory.ammo_count("9mm") - before))
	# The host saves at 14: the copy here carries the box.
	await _at(18.0)
	var copy: Dictionary = SAVE.read_slot("slot2")
	if copy.is_empty():
		_fail("the host's save never reached the joiner's Slot 2")
	elif JSON.stringify(_ints(copy.get("item_box", []))) != JSON.stringify(_ints(store.to_save())):
		_fail("the joiner's copy of the save has box %s, the box is %s" % [copy.get("item_box"), store.to_save()])
	else:
		print("join: save copy carries the box ", copy.get("item_box"))
	menu.close()
	await _at(24.0)

func _host(menu: Node) -> void:
	await _at(4.0)
	if store.count("herb_green") != 1:
		_fail("the joiner's fern didn't reach the host's box: %s" % [store.to_save()])
	if not box.is_open():
		_fail("the lid isn't up on the host's phone with both using the box")
	# Both go for the shotgun now.
	await _at(5.0)
	var bi := _box_index("m12")
	if bi >= 0:
		menu._on_box_slot(bi)
		menu._take(false)
	await _at(8.0)
	var holders := 0
	var who := []
	for p in get_nodes_in_group("players"):
		if p.inventory.count("m12") > 0:
			holders += 1
			who.append(p.character)
	if holders != 1:
		_fail("%d survivors have the box's one shotgun (%s)" % [holders, who])
	else:
		print("host: the shotgun went to ", who[0], " only")
	if store.count("m12") != 0:
		_fail("the shotgun is still in the box after it was taken")
	await _at(12.0)
	if store.count("ammo:9mm") != 0:
		_fail("the joiner's TAKE ALL left %d rounds in the host's box" % store.count("ammo:9mm"))
	var her: Node = null
	for p in get_nodes_in_group("players"):
		if not p.is_multiplayer_authority():
			her = p
	if her and her.inventory.ammo_count("9mm") < 70:
		_fail("the host's copy of her bag has %d rounds of 9mm, not 70" % her.inventory.ammo_count("9mm"))
	await _at(14.0)
	SAVE.request_save("slot2")
	await _wait(1.0)
	var s2: Dictionary = SAVE.read_slot("slot2")
	if JSON.stringify(_ints(s2.get("item_box", []))) != JSON.stringify(_ints(store.to_save())):
		_fail("the host's save has box %s, the box is %s" % [s2.get("item_box"), store.to_save()])
	# She closed at 18; the lid stays up while the host still has it open.
	await _at(20.0)
	if not box.is_open():
		_fail("the lid came down while the host still had the box open")
	menu.close()
	await _at(22.0)
	if box.is_open():
		_fail("the lid stayed up after both closed the box")

func _finish() -> void:
	print(role, " COOP ITEM BOX OK" if fails.is_empty() else " COOP ITEM BOX FAILED")
	await _wait(4.0)
	_clean()
	quit(0 if fails.is_empty() else 1)
