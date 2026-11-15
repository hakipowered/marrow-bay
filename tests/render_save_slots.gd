extends SceneTree
## Pictures of the save slots: saves in three places (each slot gets its own
## picture of the view), an old save with no picture, the pause menu's save
## screen, the "save over it?" question, the title with Continue / Load Game,
## and the load screen. Uses its own save folder.
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 1600x1332 --script tests/render_save_slots.gd -- <out_dir>
##   then the same with -- <out_dir> title
## (--rendering-driver opengl3 draws it the way the browser version does.)

const DIR := "user://saves_render_test"
var out := "/tmp/save_slots"
var GS: Node
var SAVE: Node

## "title": only the title and load screen, with the saves an earlier run
## left (lavapipe runs out of memory doing the level and the title in one go).
var title_only := false

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	title_only = a.size() > 1 and a[1] == "title"
	DirAccess.make_dir_recursive_absolute(out)
	GS = root.get_node("GameState")
	SAVE = root.get_node("SaveSystem")
	_run.call_deferred()

func _wait(sec: float) -> void:
	await create_timer(sec, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, tag])
	print("shot ", tag)

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

func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)

## Stands her at a spot looking along yaw, waits for the camera to settle,
## and saves there.
func _save_at(slot: String, pos: Vector3, yaw: float, checkpoint: String, play_min: float) -> void:
	var p := get_first_node_in_group("players")
	p.global_position = pos
	p.yaw = yaw
	p.body.rotation.y = yaw
	GS.shared_checkpoint = checkpoint
	GS.play_time_sec = play_min * 60.0
	await _wait(2.5)
	SAVE.request_save(slot)
	await _wait(1.5)
	var thumb := "%s/%s.jpg" % [DIR, slot]
	if FileAccess.file_exists(thumb):
		var img := Image.load_from_file(thumb)
		print("thumb ", slot, " ", img.get_size(), " ", FileAccess.get_file_as_bytes(thumb).size(), " bytes")
		img.save_png("%s/thumb_%s.png" % [out, slot])
	else:
		print("NO THUMB for ", slot)
	await _wait(1.1)

func _run() -> void:
	SAVE.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	if title_only:
		await _title()
		_clean()
		DirAccess.remove_absolute(DIR)
		quit(0)
		return
	_clean()
	# A save from the build before slots: no picture, no chapter in it.
	FileAccess.open("%s/slot5.json" % DIR, FileAccess.WRITE).store_string(JSON.stringify({"version": 1,
		"timestamp": "2026-11-14T21:05:00", "level": "res://scenes/levels/archive_hub.tscn", "checkpoint": "safe_office",
		"flags": {"story_intro": true, "story_gates": true}, "inventories": {}, "play_time": 3725.0, "mode": 1,
		"looks": {"zegan": {}, "obcera": {}}}))
	GS.reset_run()
	GS.set_flag("story_intro")
	GS.set_flag("story_gates")
	root.get_node("Net").start_solo("obcera")
	change_scene_to_file(GS.level_path)
	await _wait(6.0)
	await _save_at("slot1", Vector3(-2.0, 0.1, -22.0), PI, "start", 7.3)
	await _save_at("slot2", Vector3(0.0, 0.1, 6.0), PI, "hall", 18.6)
	await _save_at("slot3", Vector3(17.5, 0.1, 5.5), PI * 0.75, "safe_office", 31.2)
	var hud := get_first_node_in_group("hud")
	hud.toggle_pause()
	await _frames(3)
	await _shot("pause_menu")
	_button(hud, "Save game").pressed.emit()
	await _wait(0.6)
	await _shot("save_screen")
	var screen := _find(hud, func(x): return x.has_signal("picked"))
	screen._grid.get_node("Card_slot2").pressed.emit()
	await _wait(0.4)
	await _shot("save_over_question")
	_button(screen, "Cancel").pressed.emit()
	await _frames(2)
	_button(screen, "Back").pressed.emit()
	hud.toggle_pause()
	await _frames(2)
	# The saves stay for a "title" run.
	quit(0)

func _title() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(2.0)
	await _shot("title")
	var menu := current_scene
	_button(menu, "Load Game").pressed.emit()
	await _wait(0.6)
	await _shot("load_screen")
