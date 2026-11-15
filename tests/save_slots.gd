extends SceneTree
## Save slots: saves from older builds still show and load, several manual
## slots each keep their own save, the newest one is what Continue loads, the
## save screen (pause menu) saves into a picked slot and asks before saving
## over one, Load Game at the title loads a picked slot, the autosave follows
## new checkpoints but not the spot a load puts them back at, play time only
## runs in the levels, and a co-op copy never lands on a different run.
## Uses its own save folder, so the real saves on this machine stay as they are.
## Prints SAVE SLOTS OK, or PLAYTEST BUG lines and SAVE SLOTS FAILED.
##   godot --headless --path . --script tests/save_slots.gd

const DIR := "user://saves_slot_test"
var fails: Array[String] = []
var GS: Node
var SAVE: Node
var NET: Node

func _initialize() -> void:
	GS = root.get_node("GameState")
	SAVE = root.get_node("SaveSystem")
	NET = root.get_node("Net")
	_run.call_deferred()

func _bug(msg: String) -> void:
	fails.append(msg)
	print("PLAYTEST BUG [saves] ", msg)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(sec: float) -> void:
	await create_timer(sec, true).timeout

func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)

func _write_json(slot: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	FileAccess.open("%s/%s.json" % [DIR, slot], FileAccess.WRITE).store_string(JSON.stringify(data))

func _player() -> Node:
	return get_first_node_in_group("players")

func _find(n: Node, cond: Callable) -> Node:
	if cond.call(n):
		return n
	for c in n.get_children():
		var f := _find(c, cond)
		if f:
			return f
	return null

func _button(n: Node, text: String) -> Button:
	return _find(n, func(x): return x is Button and x.text == text and x.is_visible_in_tree())

func _run() -> void:
	SAVE.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	_clean()
	await _frames(2)
	await _old_saves()
	await _slots_in_game()
	await _save_screen()
	await _autosave_rules()
	await _title_load()
	_mirror_rules()
	_clean()
	DirAccess.remove_absolute(DIR)
	if fails.is_empty():
		print("SAVE SLOTS OK")
		quit(0)
	else:
		print("SAVE SLOTS FAILED: ", fails.size())
		quit(1)

## Version 1 saves (slot1 + autosave, before slots) show up with sensible
## details and are what Continue finds.
func _old_saves() -> void:
	_write_json("slot1", {"version": 1, "timestamp": "2026-11-14T21:05:00", "level": "res://scenes/levels/archive_hub.tscn",
		"checkpoint": "safe_office", "flags": {"story_intro": true, "story_gates": true}, "inventories": {}, "play_time": 3725.0,
		"mode": 0, "looks": {"obcera": {"outfit": "default"}}})
	_write_json("autosave", {"version": 1, "timestamp": "2026-11-14T20:10:00", "level": "res://scenes/levels/archive_hub.tscn",
		"checkpoint": "start", "flags": {"story_intro": true}, "inventories": {}, "play_time": 300.0, "mode": 1,
		"looks": {"zegan": {}, "obcera": {}}})
	var i: Dictionary = SAVE.slot_info("slot1")
	if i.get("empty", true):
		_bug("an old slot1 save shows as empty")
		return
	if i.get("chapter") != "Chapter 1: Shelter" or i.get("place") != "Archivist's Office" or i.get("play_time_text") != "1:02:05":
		_bug("old slot1 described as %s / %s / %s" % [i.get("chapter"), i.get("place"), i.get("play_time_text")])
	if i.get("party") != "Solo: Obcera" or not i.get("safe_room", false):
		_bug("old slot1 party '%s', safe room %s" % [i.get("party"), i.get("safe_room")])
	if i.get("when") != "14 Nov 2026, 21:05":
		_bug("old slot1 date reads '%s'" % i.get("when"))
	var a: Dictionary = SAVE.slot_info("autosave")
	if a.get("chapter") != "Prologue: Last Call" or a.get("party") != "Co-op: Zegan & Obcera":
		_bug("old autosave described as %s / %s" % [a.get("chapter"), a.get("party")])
	if SAVE.newest_slot() != "slot1":
		_bug("newest save should be the old slot1, got '%s'" % SAVE.newest_slot())
	var infos: Array = SAVE.all_slot_infos()
	if infos.size() != 1 + SAVE.MANUAL_SLOTS or infos[0].get("slot") != "autosave":
		_bug("slot list has %d entries, first %s" % [infos.size(), infos[0].get("slot") if not infos.is_empty() else "-"])
	# A broken file shows as damaged, not as a crash or a save.
	FileAccess.open("%s/slot8.json" % DIR, FileAccess.WRITE).store_string("{not json")
	var bad: Dictionary = SAVE.slot_info("slot8")
	if not bad.get("empty", false) or not bad.get("damaged", false):
		_bug("a damaged slot8 file reads as %s" % bad)

## Into the game, then three manual slots: each keeps its own save.
func _slots_in_game() -> void:
	GS.reset_run()
	GS.set_flag("story_intro")
	NET.start_solo("obcera")
	change_scene_to_file(GS.level_path)
	await _wait(2.0)
	if _player() == null:
		_bug("the level didn't start")
		return
	var run: String = GS.run_id
	if run == "":
		_bug("a new game has no run id")
	SAVE.request_save("slot3")
	await _wait(1.1)
	GS.set_flag("slot5_marker")
	SAVE.request_save("slot5")
	await _wait(0.2)
	var s3: Dictionary = SAVE.read_slot("slot3")
	var s5: Dictionary = SAVE.read_slot("slot5")
	if s3.is_empty() or s5.is_empty():
		_bug("saving to slot3 / slot5 wrote nothing (%s / %s)" % [not s3.is_empty(), not s5.is_empty()])
		return
	if s3.get("flags", {}).has("slot5_marker") or not s5.get("flags", {}).has("slot5_marker"):
		_bug("slots 3 and 5 don't each keep their own save")
	if int(s5.get("version", 0)) != SAVE.SNAPSHOT_VERSION or s5.get("run_id") != run or s5.get("party") != ["obcera"]:
		_bug("slot5 save: version %s, run %s (want %s), party %s" % [s5.get("version"), s5.get("run_id"), run, s5.get("party")])
	if s5.get("host_character") != "obcera":
		_bug("slot5 doesn't say Obcera played it: %s" % s5.get("host_character"))
	if SAVE.newest_slot() != "slot5":
		_bug("newest save should be slot5, got '%s'" % SAVE.newest_slot())
	if SAVE.has_slot("slot1") == false:
		_bug("saving into other slots touched slot1")

## The pause menu's Save opens the slot screen; a free slot saves at once,
## a used one asks first; Back leaves everything alone.
func _save_screen() -> void:
	var hud := get_first_node_in_group("hud")
	if hud == null:
		_bug("no HUD in the level")
		return
	hud.toggle_pause()
	await _frames(3)
	var save_btn := _button(hud, "Save game")
	if save_btn == null:
		_bug("no Save game button in the pause menu")
		return
	save_btn.pressed.emit()
	await _frames(4)
	var screen := _find(hud, func(x): return x.has_signal("picked") and x.get("mode") == "save")
	if screen == null:
		_bug("Save game didn't open the slot screen")
		return
	var cards: Array = []
	for c in screen._grid.get_children():
		if not c.is_queued_for_deletion():
			cards.append(c)
	if cards.size() != SAVE.MANUAL_SLOTS:
		_bug("save screen shows %d cards, want %d (no autosave)" % [cards.size(), SAVE.MANUAL_SLOTS])
	var c7: Button = screen._grid.get_node_or_null("Card_slot7")
	var c3: Button = screen._grid.get_node_or_null("Card_slot3")
	if c7 == null or c3 == null:
		_bug("save screen has no card for slot7 or slot3")
		return
	GS.set_flag("slot7_marker")
	c7.pressed.emit()
	await _wait(0.3)
	if not SAVE.read_slot("slot7").get("flags", {}).has("slot7_marker"):
		_bug("tapping the empty Slot 7 didn't save there")
	if hud._pause.visible:
		_bug("the pause menu stayed open after saving")
	if is_instance_valid(screen) and not screen.is_queued_for_deletion():
		_bug("the slot screen stayed open after saving")
	if not hud._toast.text.begins_with("Saved to Slot 7"):
		_bug("toast after saving says '%s'" % hud._toast.text)
	# Over a used slot: asked first, Cancel keeps it.
	await _wait(1.1)
	hud.toggle_pause()
	await _frames(2)
	_button(hud, "Save game").pressed.emit()
	await _frames(4)
	screen = _find(hud, func(x): return x.has_signal("picked") and x.get("mode") == "save")
	var before: Dictionary = SAVE.read_slot("slot3")
	GS.set_flag("slot3_over")
	screen._grid.get_node("Card_slot3").pressed.emit()
	await _frames(3)
	if SAVE.read_slot("slot3").get("flags", {}).has("slot3_over"):
		_bug("tapping a used slot saved over it without asking")
	var cancel := _button(screen, "Cancel")
	if cancel == null:
		_bug("no question before saving over Slot 3")
		return
	cancel.pressed.emit()
	await _frames(3)
	if SAVE.read_slot("slot3") != before:
		_bug("Cancel changed Slot 3")
	screen._grid.get_node("Card_slot3").pressed.emit()
	await _frames(3)
	_button(screen, "Save over it").pressed.emit()
	await _wait(0.3)
	if not SAVE.read_slot("slot3").get("flags", {}).has("slot3_over"):
		_bug("Save over it didn't save into Slot 3")
	if SAVE.newest_slot() != "slot3":
		_bug("after saving over Slot 3 the newest is '%s'" % SAVE.newest_slot())
	# Back closes the screen and nothing else.
	hud.toggle_pause()
	await _frames(2)
	_button(hud, "Save game").pressed.emit()
	await _frames(4)
	screen = _find(hud, func(x): return x.has_signal("picked") and x.get("mode") == "save")
	_button(screen, "Back").pressed.emit()
	await _frames(3)
	if is_instance_valid(screen) and not screen.is_queued_for_deletion():
		_bug("Back didn't close the slot screen")
	if not hud._pause.visible:
		_bug("Back from the slot screen closed the pause menu too")
	hud.toggle_pause()
	await _frames(2)
	if paused:
		_bug("game still paused after leaving the pause menu")

## The autosave: a new checkpoint writes it; the spot they start at after a
## load or Continue doesn't (it would replace the newer autosave at once).
func _autosave_rules() -> void:
	DirAccess.remove_absolute("%s/autosave.json" % DIR)
	var hall: Node = null
	for c in get_nodes_in_group("checkpoints"):
		if c.checkpoint_id == "hall":
			hall = c
	if hall == null:
		_bug("no 'hall' checkpoint to test the autosave with")
		return
	hall._rpc_reached()
	await _wait(0.2)
	var a: Dictionary = SAVE.read_slot("autosave")
	if a.get("checkpoint") != "hall":
		_bug("reaching the hall checkpoint didn't autosave (autosave at '%s')" % a.get("checkpoint", "nothing"))
	DirAccess.remove_absolute("%s/autosave.json" % DIR)
	hall._rpc_reached()
	await _wait(0.2)
	if SAVE.has_slot("autosave"):
		_bug("standing in the same checkpoint again wrote another autosave")
	# A loaded game starts at its checkpoint: no autosave over the old one.
	SAVE.apply_snapshot(SAVE.read_slot("slot5"))
	reload_current_scene()
	await _wait(2.0)
	if SAVE.has_slot("autosave"):
		_bug("loading a save wrote the autosave straight away (at '%s')" % SAVE.read_slot("autosave").get("checkpoint"))
	# A new chapter's first checkpoint does autosave.
	var level := get_first_node_in_group("level")
	level.change_level("res://scenes/levels/undercroft.tscn", "ch2_lift")
	await _wait(3.0)
	var a2: Dictionary = SAVE.read_slot("autosave")
	if a2.get("checkpoint") != "ch2_lift" or SAVE.describe(a2).get("chapter") != "Chapter 2: The Count":
		_bug("arriving in chapter 2 didn't autosave there (autosave: %s, %s)" % [a2.get("checkpoint", "nothing"), SAVE.describe(a2).get("chapter", "")])

## At the title: Continue and Load Game; Load Game lists the slots and loads
## the one picked, starting on the survivor it was played as. Play time
## doesn't run on the title.
func _title_load() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(10)
	var menu := current_scene
	var t0: float = GS.play_time_sec
	await _wait(1.0)
	if GS.play_time_sec != t0:
		_bug("play time ran on the title screen (%.2f -> %.2f)" % [t0, GS.play_time_sec])
	if _button(menu, "Continue") == null or _button(menu, "Load Game") == null:
		_bug("no Continue / Load Game on the title with saves on the phone")
		return
	menu._char = "zegan"
	_button(menu, "Load Game").pressed.emit()
	await _frames(4)
	var screen := _find(menu, func(x): return x.has_signal("picked") and x.get("mode") == "load")
	if screen == null:
		_bug("Load Game didn't open the slot screen")
		return
	if screen._grid.get_child_count() != 1 + SAVE.MANUAL_SLOTS:
		_bug("load screen shows %d cards, want %d" % [screen._grid.get_child_count(), 1 + SAVE.MANUAL_SLOTS])
	var empty: Button = screen._grid.get_node_or_null("Card_slot2")
	if empty == null or not empty.disabled:
		_bug("an empty slot can be picked on the load screen")
	var want: Dictionary = SAVE.read_slot("slot5")
	screen._grid.get_node("Card_slot5").pressed.emit()
	await _frames(4)
	if _button(menu, "Resume Solo") == null:
		_bug("picking Slot 5 didn't go on to Resume Solo")
	if not GS.has_flag("slot5_marker") or GS.has_flag("slot7_marker"):
		_bug("Load Game loaded the wrong save (slot5 marker %s, slot7 marker %s)" % [GS.has_flag("slot5_marker"), GS.has_flag("slot7_marker")])
	if GS.run_id != want.get("run_id"):
		_bug("loading kept run id %s, the save has %s" % [GS.run_id, want.get("run_id")])
	if menu._char != "obcera":
		_bug("Slot 5 was played as Obcera but the resume picked %s" % menu._char)
	# Continue = the newest save (the autosave from chapter 2).
	menu._home()
	await _frames(3)
	_button(menu, "Continue").pressed.emit()
	await _frames(3)
	if GS.level_path != "res://scenes/levels/undercroft.tscn":
		_bug("Continue didn't load the newest save (level %s)" % GS.level_path)
	# A new co-op game starts over, even right after loading a save.
	menu._home()
	await _frames(3)
	NET.relay_url = "ws://127.0.0.1:9"   # nowhere: this only checks the run resets
	menu._go("host_new")
	await _frames(2)
	if GS.level_path != GS.FIRST_LEVEL or GS.has_flag("slot5_marker"):
		_bug("Invite a Friend after loading a save kept the loaded run (%s)" % GS.level_path)
	NET.close()

## Where the partner's phone puts its copy of the host's save.
func _mirror_rules() -> void:
	_clean()
	var host_save := {"timestamp": "2026-11-15T10:00:00", "run_id": "RUN-A", "level": GS.FIRST_LEVEL, "checkpoint": "hall"}
	if SAVE.mirror_target("slot2", host_save) != "slot2":
		_bug("copy into an empty slot2 went to '%s'" % SAVE.mirror_target("slot2", host_save))
	_write_json("slot2", {"timestamp": "2026-11-14T10:00:00", "run_id": "RUN-A"})
	if SAVE.mirror_target("slot2", host_save) != "slot2":
		_bug("copy over the same run in slot2 went to '%s'" % SAVE.mirror_target("slot2", host_save))
	_write_json("slot2", {"timestamp": "2026-11-14T10:00:00", "run_id": "RUN-B"})
	_write_json("slot1", {"timestamp": "2026-11-14T10:00:00", "run_id": "RUN-C"})
	if SAVE.mirror_target("slot2", host_save) != "slot3":
		_bug("copy aimed at slot2 (another run) went to '%s', want the first free slot3" % SAVE.mirror_target("slot2", host_save))
	for i in SAVE.MANUAL_SLOTS:
		_write_json("slot%d" % (i + 1), {"timestamp": "2026-11-14T1%d:00:00" % i, "run_id": "RUN-B"})
	if SAVE.mirror_target("slot2", host_save) != "":
		_bug("with every slot holding other runs the copy still went to '%s'" % SAVE.mirror_target("slot2", host_save))
	_write_json("slot6", {"timestamp": "2026-11-14T09:00:00", "run_id": "RUN-A"})
	_write_json("slot4", {"timestamp": "2026-11-14T08:00:00", "run_id": "RUN-A"})
	if SAVE.mirror_target("slot2", host_save) != "slot4":
		_bug("copy should replace the oldest save of the same run (slot4), went to '%s'" % SAVE.mirror_target("slot2", host_save))
	if SAVE.mirror_target("autosave", host_save) != "autosave":
		_bug("the autosave copy didn't go to the autosave")
