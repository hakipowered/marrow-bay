extends Control
## The save-slot screen: the autosave and the manual slots as cards, each with
## the picture from when it was saved, the chapter, the place they come back
## at, play time, date and who played (SaveSystem.slot_info).
##
## mode "save" (pause menu): tapping a slot saves there, asking first when it
## holds a save already; the autosave isn't offered. mode "load" (title): tapping
## a save hands it back to load. picked(slot) fires once the choice is made
## (save: the save was sent; load: the slot to load); closed when backing out.
## On the joining phone in co-op the cards are the host's slots, since the
## host writes the save (and copies it onto this phone).

signal picked(slot: String)
signal closed

var mode := "load"

const RED := Color(0.78, 0.12, 0.08)
const CREAM := Color(0.93, 0.89, 0.81)
const MUTED := Color(0.68, 0.62, 0.56)
const AMBER := Color(0.95, 0.66, 0.25)
const KEY_ART := "res://assets/ui/title_key.jpg"

var _theme := Theme.new()
var _grid: GridContainer
var _hint: Label
var _confirm: Control
var _newest_key := -1.0
var _infos: Array = []
var _waiting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_theme()
	theme = _theme
	# Solid over the game (the HUD and pause menu would show through); over
	# the title the city film still glows faintly behind it.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.012, 0.012, 1.0 if mode == "save" else 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var title := Label.new()
	title.text = "SAVE GAME" if mode == "save" else "LOAD GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", RED)
	title.add_theme_constant_override("outline_size", 18)
	col.add_child(title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.add_theme_color_override("font_color", MUTED)
	_hint.text = _hint_text()
	col.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	col.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 20)
	center.add_child(_grid)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(420, 100)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): closed.emit())
	col.add_child(back)
	SaveSystem.slot_infos_received.connect(_on_infos)
	_waiting = true
	SaveSystem.request_slot_infos()
	if Net.is_coop() and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_hint.text = "Getting your partner's save slots..."
		# No answer (partner gone): show this phone's own slots.
		get_tree().create_timer(4.0, true).timeout.connect(func():
			if _waiting and is_inside_tree():
				_on_infos(SaveSystem.all_slot_infos())
				_hint.text = "Your partner's phone didn't answer. These are this phone's slots.")

func _hint_text() -> String:
	if mode == "load":
		return "Pick a save. You come back at the place it shows."
	var place: String = SaveSystem.PLACES.get(GameState.shared_checkpoint, GameState.shared_checkpoint.capitalize().replace("_", " "))
	var s := "Pick a slot. Loading this save puts you back at: %s." % place
	if Net.is_coop():
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			s += "\nYour partner is hosting: it goes into their slot and a copy onto this phone."
		else:
			s += "\nIt goes onto both phones."
	return s

func _on_infos(infos: Array) -> void:
	if not _waiting:
		return
	_waiting = false
	if SaveSystem.slot_infos_received.is_connected(_on_infos):
		SaveSystem.slot_infos_received.disconnect(_on_infos)
	_hint.text = _hint_text()
	_infos = infos
	_newest_key = -1.0
	for i in infos:
		if not i.get("empty", true):
			_newest_key = max(_newest_key, float(i.get("key", -1.0)))
	for c in _grid.get_children():
		c.queue_free()
	for i in infos:
		if mode == "save" and i.get("slot", "") == SaveSystem.AUTOSAVE_SLOT:
			continue
		_grid.add_child(_card(i))

## One slot: picture on the left, the details on the right.
func _card(info: Dictionary) -> Button:
	var slot: String = info.get("slot", "")
	var empty: bool = info.get("empty", true)
	var damaged: bool = info.get("damaged", false)
	var b := Button.new()
	b.name = "Card_" + slot
	b.custom_minimum_size = Vector2(1010, 262)
	# Lets a drag on a card scroll the list instead of being eaten by it.
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.disabled = mode == "load" and empty
	b.pressed.connect(_pick.bind(info))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	b.add_child(m)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 26)
	m.add_child(row)
	row.add_child(_picture(info))
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	var head := str(info.get("title", SaveSystem.slot_title(slot))).to_upper()
	if not empty and info.get("safe_room", false):
		head += "   ·   SAFE ROOM"
	if not empty and float(info.get("key", -2.0)) == _newest_key:
		head += "   ·   LATEST"
	_line(text, head, 26, AMBER if slot == SaveSystem.AUTOSAVE_SLOT else RED)
	if empty:
		if damaged:
			_line(text, "Damaged save", 38, MUTED)
			_line(text, "Can't be loaded. Saving here replaces it." if mode == "save" else "This file can't be read.", 26, MUTED)
		else:
			_line(text, "No data", 38, MUTED)
			if mode == "save":
				_line(text, "Tap to save here", 26, MUTED)
		if b.disabled:
			b.modulate = Color(1, 1, 1, 0.55)
		return b
	_line(text, str(info.get("chapter", "")), 38, CREAM)
	_line(text, str(info.get("place", "")), 32, CREAM)
	_line(text, "Play time %s     %s" % [info.get("play_time_text", ""), info.get("when", "")], 26, MUTED)
	if str(info.get("party", "")) != "":
		# Who played it, and on what difficulty (older saves: Normal).
		_line(text, "%s  ·  %s" % [info.get("party", ""), GameState.difficulty_name(str(info.get("difficulty", "normal")))], 26, MUTED)
	return b

func _line(parent: Control, s: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

## The save's own picture; an old save (from before pictures) shows the city
## art dimmed instead, an empty slot a dark frame.
func _picture(info: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(400, 225)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.01, 0.01)
	sb.border_color = Color(0.32, 0.1, 0.07)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", sb)
	if info.get("empty", true):
		# Nothing saved: just the outline where the picture will go.
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(0.45, 0.14, 0.1, 0.35)
		sb.set_corner_radius_all(6)
		return frame
	var tex: Texture2D = null
	var path := SaveSystem.local_thumb_for(info) if _remote_list() else str(info.get("thumb", ""))
	if path != "" and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	var dim := false
	if tex == null and ResourceLoader.exists(KEY_ART):
		tex = load(KEY_ART)
		dim = true
	if tex:
		var r := TextureRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.clip_contents = true
		if dim:
			r.modulate = Color(0.42, 0.36, 0.36)
		frame.add_child(r)
	return frame

## The cards came from the host's phone (this phone joined a co-op game).
func _remote_list() -> bool:
	return Net.is_coop() and multiplayer.has_multiplayer_peer() and not multiplayer.is_server()

func _pick(info: Dictionary) -> void:
	var slot: String = info.get("slot", "")
	if mode == "load":
		if not info.get("empty", true):
			picked.emit(slot)
		return
	if info.get("empty", true):
		_save(slot)
	else:
		_ask_overwrite(info)

func _save(slot: String) -> void:
	SaveSystem.request_save(slot)
	picked.emit(slot)

func _ask_overwrite(info: Dictionary) -> void:
	if is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.045, 0.98)
	sb.border_color = Color(0.7, 0.16, 0.1)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)
	var q := _line(col, "Save over %s?" % info.get("title", ""), 48, CREAM)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pic := _picture(info)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(pic)
	var what := _line(col, "%s, %s\nPlay time %s, saved %s" % [info.get("chapter", ""), info.get("place", ""), info.get("play_time_text", ""), info.get("when", "")], 30, MUTED)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	what.autowrap_mode = TextServer.AUTOWRAP_WORD
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)
	var yes := Button.new()
	yes.name = "Overwrite"
	yes.text = "Save over it"
	yes.custom_minimum_size = Vector2(420, 104)
	yes.pressed.connect(func(): _confirm.queue_free(); _save(str(info.get("slot", ""))))
	row.add_child(yes)
	var no := Button.new()
	no.text = "Cancel"
	no.custom_minimum_size = Vector2(320, 104)
	no.pressed.connect(func(): _confirm.queue_free())
	row.add_child(no)

func _build_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.05, 0.94)
	sb.border_color = Color(0.45, 0.12, 0.09)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.3, 0.07, 0.05, 0.96)
	sbh.border_color = Color(0.85, 0.2, 0.12)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.05, 0.04, 0.04, 0.85)
	sbd.border_color = Color(0.2, 0.09, 0.07)
	_theme.set_stylebox("normal", "Button", sb)
	_theme.set_stylebox("hover", "Button", sbh)
	_theme.set_stylebox("pressed", "Button", sbh)
	_theme.set_stylebox("disabled", "Button", sbd)
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_font_size("font_size", "Button", 38)
	_theme.set_color("font_color", "Button", CREAM)
	_theme.set_font_size("font_size", "Label", 30)
	_theme.set_color("font_color", "Label", CREAM)
	_theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	_theme.set_constant("outline_size", "Label", 8)
