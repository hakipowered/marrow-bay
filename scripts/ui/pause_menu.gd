extends Control
## Pause: Resume, Save (shared checkpoint), Load, Cheats, Quit.

var _list: VBoxContainer
var _cheats: VBoxContainer
var _info: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Anchors AND offsets: set_anchors_preset() alone keeps the current
	# (zero) size once the node is in the tree, which pushed the menu off
	# the top-left corner on the phone.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	center.add_child(row)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(520, 0)
	_list.add_theme_constant_override("separation", 18)
	row.add_child(_list)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 56)
	_list.add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_list.add_child(_info)
	_add("Resume", func(): get_parent().toggle_pause())
	_add("Save at shared checkpoint", func(): SaveSystem.request_save("slot1"); get_parent().toggle_pause())
	_add("Cheats", func(): _cheats.visible = not _cheats.visible)
	_add("Quit to title", _quit)
	_cheats = VBoxContainer.new()
	_cheats.visible = false
	row.add_child(_cheats)
	for k in Cheats.LIST:
		var c := CheckButton.new()
		c.text = Cheats.LIST[k]
		c.add_theme_font_size_override("font_size", 28)
		c.button_pressed = Cheats.on(k)
		c.toggled.connect(func(on): Cheats.set_cheat(k, on))
		Cheats.changed.connect(func(n, v): if n == k: c.set_pressed_no_signal(v))
		_cheats.add_child(c)

func refresh() -> void:
	var goal: String = GameState.world_flags.get("objective", "")
	_info.text = ("Objective: %s\n\n" % goal if goal != "" else "") + "Save point: %s\nPlay time: %d min" % [GameState.shared_checkpoint.capitalize().replace("_", " "), int(GameState.play_time_sec / 60.0)]

func _add(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.pressed.connect(cb)
	_list.add_child(b)

func _quit() -> void:
	get_tree().paused = false
	Net.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
