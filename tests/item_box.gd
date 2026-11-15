extends SceneTree
## The item box (solo): a box in every safe room, its prompt, the screen it
## opens (world paused, lid up), storing a gun with its loaded rounds, stacks
## merging in the box, the box refusing the last weapon, taking one bag slot's
## worth or all of it, a full bag and a gun already carried, closing (lid down,
## world running), the box in saves (old saves: empty), a new game emptying
## it, and the same contents at the keeper's lodge in chapter 2.
## Uses its own save folder. Prints ITEM BOX OK, or PLAYTEST BUG lines and
## ITEM BOX FAILED.
##   godot --headless --path . --script tests/item_box.gd

const DIR := "user://saves_item_box_test"
## Chapter 1's story up to the office scene ("story_elevator" would send a
## chapter 1 load on to chapter 2), and chapter 2's opening scenes.
const CH1_BEATS := ["intro", "gates", "warden", "glass"]
const CH2_BEATS := ["elevator", "c2_arrival", "c2_intercom", "c2_warden"]
var fails: Array[String] = []
var GS: Node
var SAVE: Node
var p: Node
var hud: Node
var menu: Node
var store: Node

func _initialize() -> void:
	GS = root.get_node("GameState")
	SAVE = root.get_node("SaveSystem")
	_run.call_deferred()
	create_timer(240.0, true).timeout.connect(func():
		print("ITEM BOX TIMEOUT")
		quit(1))

func _bug(msg: String) -> void:
	fails.append(msg)
	print("PLAYTEST BUG [item box] ", msg)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)

func _box_named(part: String) -> Node:
	for b in get_nodes_in_group("item_boxes"):
		if part in str(b.name):
			return b
	return null

func _slot_of(id: String) -> int:
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

func _load_level(path: String, checkpoint: String) -> void:
	GS.level_path = path
	GS.shared_checkpoint = checkpoint
	change_scene_to_file(path)
	await _frames(30)
	p = get_first_node_in_group("players")
	hud = get_first_node_in_group("hud")
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	for s in get_nodes_in_group("stalker"):
		s.queue_free()
	await _frames(2)

## Stands her in front of the box, facing it, and reads the prompt.
func _face(box: Node, dist := 1.15) -> String:
	var n: Vector3 = box.global_transform.basis.z
	p.global_position = Vector3(box.global_position.x, 0.05, box.global_position.z) + n * dist
	p.velocity = Vector3.ZERO
	var face := atan2(n.x, n.z)
	p.body.global_rotation.y = face
	p.yaw = face
	await physics_frame
	await physics_frame
	p.interact_ray.force_raycast_update()
	p._update_focus()
	return p._prompt_text

func _run() -> void:
	store = GS.item_box
	SAVE.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	_clean()
	SAVE.autosave_enabled = false
	GS.reset_run()
	for beat in CH1_BEATS:
		GS.set_flag("story_" + beat)
	root.get_node("Net").start_solo("zegan")
	await _load_level("res://scenes/levels/archive_hub.tscn", "safe_office")
	await _every_safe_room_has_one()
	await _office()
	await _saves()
	await _lodge()
	_clean()
	DirAccess.remove_absolute(DIR)
	if fails.is_empty():
		print("ITEM BOX OK")
		quit(0)
	else:
		print("ITEM BOX FAILED: ", fails.size())
		quit(1)

## Each safe room checkpoint in this level has a box standing inside it.
func _every_safe_room_has_one() -> void:
	var found := 0
	for c in get_nodes_in_group("checkpoints"):
		if not c.is_safe_room:
			continue
		var shape: BoxShape3D = c.get_child(0).shape
		var area := AABB(c.global_position - Vector3(shape.size.x / 2, 0, shape.size.z / 2), shape.size)
		var inside := false
		for b in get_nodes_in_group("item_boxes"):
			# In the room, a step or so from where they stand together.
			if area.grow(1.0).has_point(b.global_position + Vector3.UP * 0.2):
				inside = true
		if not inside:
			_bug("safe room %s has no item box" % c.checkpoint_id)
		found += 1
	if found == 0:
		_bug("no safe room in %s" % GS.level_path)

func _office() -> void:
	var box := _box_named("office")
	if box == null:
		_bug("no item box in the Archivist's Office (boxes: %s)" % [get_nodes_in_group("item_boxes").map(func(b): return str(b.name))])
		return
	# The crate itself is solid and on the floor, lid shut.
	if absf(box.global_position.y) > 0.05:
		_bug("office box isn't on the floor (y %.2f)" % box.global_position.y)
	var prompt := await _face(box)
	if prompt != "Open the item box":
		_bug("standing at the office box the prompt reads '%s'" % prompt)
		return
	# A loaded shotgun in hand, so storing it has to re-arm her.
	p.inventory.add_weapon("m12")
	p.inventory.mag["m12"] = 3
	p.equip("m12")
	p.inventory.add_ammo("9mm", 20)
	p.interact()
	await _frames(3)
	menu = hud._box_menu
	if menu == null or not menu.visible:
		_bug("interacting with the box didn't open the box screen")
		return
	if not paused:
		_bug("solo: the world keeps running behind the box screen")
	await _wait(0.3)
	if not box.is_open():
		_bug("the lid didn't come up when the box was opened")
	# Store the shotgun: tap its slot twice.
	var i := _slot_of("m12")
	menu._on_slot(i)
	menu._on_slot(i)
	await _frames(2)
	var bi := _box_index("m12")
	if bi < 0:
		_bug("double-tapping the shotgun didn't put it in the box")
	else:
		var e: Dictionary = store.sorted()[bi]
		if int(e["mag"]) != 3:
			_bug("the shotgun went in with %d rounds loaded, not 3" % int(e["mag"]))
	if _slot_of("m12") >= 0:
		_bug("the stored shotgun is still in the bag")
	if p.inventory.equipped == "m12":
		_bug("she still holds the shotgun she put in the box")
	# 9mm: the starting 30 and the 20 merge into one stack on the way in, and
	# a second load into the box tops up the same entry.
	menu._side = "bag"
	menu._sel = _slot_of("ammo:9mm")
	menu._store()
	p.inventory.add_ammo("9mm", 15)
	menu._sel = _slot_of("ammo:9mm")
	menu._store()
	await _frames(2)
	var nine := 0
	var entries := 0
	for e in store.entries:
		if e["id"] == "ammo:9mm":
			entries += 1
			nine += int(e["n"])
	if entries != 1 or nine != 65:
		_bug("9mm in the box: %d entries, %d rounds (want 1 entry, 65)" % [entries, nine])
	if menu._box_hint.text.find("in the box") < 0:
		_bug("no line saying what went in the box: '%s'" % menu._box_hint.text)
	# The last weapon stays: knife and P9 out of the bag except one.
	var p9 := _slot_of("p9")
	menu._on_slot(p9)
	menu._on_slot(p9)
	var knife := _slot_of("knife")
	menu._on_slot(knife)
	menu._on_slot(knife)
	await _frames(2)
	var kept: Array = p.inventory.weapon_list()
	if kept.is_empty():
		_bug("the box took her last weapon: nothing left to hold")
	elif not "Keep one weapon" in menu._box_hint.text:
		_bug("storing the last weapon wasn't refused with a reason: '%s'" % menu._box_hint.text)
	if not p.inventory.has_weapon(p.inventory.equipped):
		_bug("she holds '%s', which isn't in her bag" % p.inventory.equipped)
	# Take the shotgun back: tap it in the box twice. Loaded rounds kept.
	bi = _box_index("m12")
	menu._on_box_slot(bi)
	menu._on_box_slot(bi)
	await _frames(2)
	if _slot_of("m12") < 0:
		_bug("double-tapping the shotgun in the box didn't take it out")
	elif int(p.inventory.mag.get("m12", 0)) != 3:
		_bug("the shotgun came out with %d loaded, not 3" % int(p.inventory.mag.get("m12", 0)))
	if _box_index("m12") >= 0:
		_bug("the shotgun is still in the box after taking it")
	# A second shotgun in the box can't come out while she carries one.
	store._put("m12", 1, 5)
	store.changed.emit()
	bi = _box_index("m12")
	menu._on_box_slot(bi)
	menu._take(false)
	await _frames(2)
	if p.inventory.count("m12") != 1:
		_bug("took a second shotgun into the bag (%d now)" % p.inventory.count("m12"))
	if not "already carrying" in menu._box_hint.text:
		_bug("taking a gun she already carries wasn't refused with a reason: '%s'" % menu._box_hint.text)
	# 9mm: TAKE is one bag slot's worth (a stack), TAKE ALL the rest. Two
	# stacks and a bit in the box, so more than a stack is left after TAKE.
	var st: int = load("res://scripts/weapons/item_info.gd").stack("ammo:9mm")
	store._put("ammo:9mm", st * 2 + 5 - store.count("ammo:9mm"))
	store.changed.emit()
	var before: int = p.inventory.ammo_count("9mm")
	bi = _box_index("ammo:9mm")
	menu._on_box_slot(bi)
	menu._take(false)
	await _frames(2)
	if p.inventory.ammo_count("9mm") - before != st or store.count("ammo:9mm") != st + 5:
		_bug("TAKE moved %d rounds (box now %d); want %d and %d" % [p.inventory.ammo_count("9mm") - before, store.count("ammo:9mm"), st, st + 5])
	var acts: Array = menu._actions.get_children().filter(func(b): return not b.is_queued_for_deletion()).map(func(b): return b.text)
	if not "TAKE ALL" in acts:
		_bug("no TAKE ALL for %d rounds in the box: %s" % [st + 5, acts])
	menu._take(true)
	await _frames(2)
	if store.count("ammo:9mm") != 0 or _box_index("ammo:9mm") >= 0:
		_bug("TAKE ALL left %d rounds in the box with room in the bag" % store.count("ammo:9mm"))
	# A full bag: nothing comes out, and she's told why.
	for k in p.inventory.slots.size():
		if p.inventory.slots[k] == null:
			p.inventory.slots[k] = {"id": "bandage", "n": 3}
	p.inventory.changed.emit()
	store._put("ammo:shells", 12)
	store.changed.emit()
	bi = _box_index("ammo:shells")
	menu._on_box_slot(bi)
	menu._on_box_slot(bi)
	await _frames(2)
	if store.count("ammo:shells") != 12:
		_bug("shells came out of the box into a full bag")
	if not "bag is full" in menu._box_hint.text:
		_bug("a full bag wasn't given as the reason: '%s'" % menu._box_hint.text)
	# A drag that scrolled the box isn't a tap.
	menu._press_scroll = menu._box_scroll.scroll_vertical + 100
	var sel_before: int = menu._box_key
	menu._on_box_slot(0)
	if menu._box_key != sel_before:
		_bug("a scroll drag over the box selected a slot")
	menu._press_scroll = menu._box_scroll.scroll_vertical
	# Close: lid down, world running, prompt back.
	menu.close()
	await _frames(2)
	if paused:
		_bug("the world stayed paused after closing the box")
	await _wait(1.0)
	if box.is_open():
		_bug("the lid stayed up after the box was closed")
	for k in p.inventory.slots.size():
		var s = p.inventory.slots[k]
		if s != null and s["id"] == "bandage":
			p.inventory.slots[k] = null
	p.inventory.changed.emit()
	# Walking off with it open (keys on a computer) shuts it.
	p.interact()
	await _frames(2)
	p.global_position += box.global_transform.basis.z * 5.0
	await _frames(3)
	if menu.visible:
		_bug("the box screen stayed open with her 5 m away")
	paused = false

## The box goes into saves and comes back with them; old saves and new
## games have an empty box.
func _saves() -> void:
	var want: Array = store.to_save()
	if want.is_empty():
		_bug("nothing in the box to save")
		return
	SAVE.save_game("slot4", true)
	var d: Dictionary = SAVE.read_slot("slot4")
	if JSON.stringify(_ints(d.get("item_box", []))) != JSON.stringify(want):
		_bug("the save's item_box %s isn't the box %s" % [d.get("item_box"), want])
	# Through JSON the counts come back as floats: still the same box.
	store.clear()
	SAVE.apply_snapshot(d)
	if JSON.stringify(store.to_save()) != JSON.stringify(want):
		_bug("loading the save gave the box %s, want %s" % [store.to_save(), want])
	# An old save (before the box): empty box, no error.
	SAVE.apply_snapshot({"version": 2, "level": GS.FIRST_LEVEL, "checkpoint": "safe_office", "flags": {}, "inventories": {}})
	if not store.is_empty():
		_bug("a save without an item box left %s in the box" % [store.to_save()])
	SAVE.apply_snapshot(d)
	# The checkpoint Continue goes back to carries it too.
	SAVE.mark_checkpoint()
	if JSON.stringify(SAVE.checkpoint_snapshot.get("item_box", [])) != JSON.stringify(want):
		_bug("the checkpoint snapshot (Continue) doesn't carry the box")
	var keep: Array = store.to_save()
	GS.reset_run()
	if not store.is_empty():
		_bug("a new game kept the last run's box")
	store.from_save(keep)

## A box list read back from JSON (numbers come back as floats).
func _ints(a: Array) -> Array:
	return a.map(func(e): return [str(e[0]), int(e[1]), int(e[2])])

## Chapter 2's safe room opens onto the same store.
func _lodge() -> void:
	var want: Array = store.to_save()
	for beat in CH1_BEATS + CH2_BEATS:
		GS.set_flag("story_" + beat)
	# Down the elevator: the bag and the box come along.
	current_scene.change_level("res://scenes/levels/undercroft.tscn", "ch2_lodge")
	await _frames(40)
	p = get_first_node_in_group("players")
	hud = get_first_node_in_group("hud")
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	await _every_safe_room_has_one()
	var box := _box_named("lodge")
	if box == null:
		_bug("no item box in the keeper's lodge")
		return
	var prompt := await _face(box)
	if prompt != "Open the item box":
		_bug("standing at the lodge box the prompt reads '%s'" % prompt)
		return
	p.interact()
	await _frames(3)
	var m: Node = hud._box_menu
	if m == null or not m.visible:
		_bug("the lodge box didn't open the box screen")
		return
	if JSON.stringify(store.to_save()) != JSON.stringify(want) or m._box_count.text != ("%d items" % want.size() if want.size() != 1 else "1 item"):
		_bug("the lodge box shows %s ('%s'), not the office's %s" % [store.to_save(), m._box_count.text, want])
	m.close()
	await _frames(2)
