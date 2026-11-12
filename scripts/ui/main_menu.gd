extends Control
## Title flow: Solo / Host online / Join online / LAN / Continue,
## character select (Zegan or Obcera) and the customization screen.

var _panel: VBoxContainer
var _status: Label
var _code_edit: LineEdit
var _char := "zegan"
var _custom: Dictionary = {}
var _preview_label: Label
var _sliders := {}
var _theme := Theme.new()
var _logo: Label
var _bg: ColorRect
var _art: TextureRect
var _pulse := 0.0
var _beat_avg := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	theme = _theme
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_bg = bg
	# Key art behind the menu: the city under the red moon, dimmed so the
	# buttons stay readable. It brightens on the beats of the theme.
	if ResourceLoader.exists("res://assets/ui/title_bg.jpg"):
		_art = TextureRect.new()
		_art.texture = load("res://assets/ui/title_bg.jpg")
		_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_art.modulate = Color(0.5, 0.5, 0.5)
		add_child(_art)
	Music.play_menu()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.add_theme_constant_override("separation", 20)
	center.add_child(_panel)
	_custom = GameState.default_customization(_char)
	Net.session_ready.connect(_on_session_ready)
	Net.partner_joined.connect(_on_partner_joined)
	Net.session_failed.connect(func(r): _set_status("Connection problem: " + r))
	_home()
	_check_invite_link()

func _build_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.06, 0.9)
	sb.border_color = Color(0.6, 0.15, 0.1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.35, 0.08, 0.06, 0.95)
	_theme.set_stylebox("normal", "Button", sb)
	_theme.set_stylebox("hover", "Button", sbh)
	_theme.set_stylebox("pressed", "Button", sbh)
	_theme.set_font_size("font_size", "Button", 38)
	_theme.set_font_size("font_size", "Label", 32)
	_theme.set_font_size("font_size", "LineEdit", 48)
	_theme.set_color("font_color", "Label", Color(0.92, 0.88, 0.8))
	# Dark outline so text reads over the key art.
	_theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	_theme.set_constant("outline_size", "Label", 10)

func _clear() -> void:
	for c in _panel.get_children():
		c.queue_free()

func _title(text: String, size := 84) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.75, 0.12, 0.08))
	l.add_theme_constant_override("outline_size", 22)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 6)
	_panel.add_child(l)
	return l

## The title and the backdrop throb with the bass of the menu theme.
func _process(delta: float) -> void:
	# Pulse on the hits (energy above its own running average), plus a glow
	# that follows how loud the theme is overall.
	var e := Music.beat()
	_beat_avg = lerp(_beat_avg, e, clamp(delta * 1.5, 0.0, 1.0))
	var hit: float = clamp((e - _beat_avg) * 4.0, 0.0, 1.0) * 0.75 + e * 0.25
	_pulse = max(hit, move_toward(_pulse, 0.0, delta * 2.2))
	if is_instance_valid(_logo):
		_logo.add_theme_color_override("font_color", Color(0.78, 0.09, 0.06).lerp(Color(1.0, 0.3, 0.18), _pulse))
		_logo.pivot_offset = _logo.size * 0.5
		_logo.scale = Vector2.ONE * (1.0 + _pulse * 0.035)
	_bg.color = Color(0.03, 0.02, 0.02).lerp(Color(0.09, 0.015, 0.012), _pulse * 0.8)
	if is_instance_valid(_art):
		var v := 0.45 + _pulse * 0.2
		_art.modulate = Color(v + _pulse * 0.08, v, v)

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 110)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b

func _set_status(t: String) -> void:
	if is_instance_valid(_status):
		_status.text = t

func _home() -> void:
	_clear()
	_logo = _title("RAGOON CITY", 96)
	var sub := Label.new()
	sub.text = "The city has gone silent."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(sub)
	if not SaveSystem.read_slot("slot1").is_empty() or not SaveSystem.read_slot(SaveSystem.AUTOSAVE_SLOT).is_empty():
		_btn("Continue", _continue_menu)
	_btn("Play Solo", func(): _character_select("solo"))
	_btn("Co-op: Invite a Friend", func(): _character_select("host"))
	_btn("Co-op: Join with Code", func(): _character_select("join"))
	_btn("Co-op: Same Wi-Fi", _lan_menu)

func _continue_menu() -> void:
	_clear()
	_title("CONTINUE", 64)
	for slot in ["slot1", SaveSystem.AUTOSAVE_SLOT]:
		var d := SaveSystem.read_slot(slot)
		if d.is_empty():
			continue
		var label := "%s  ·  %s  ·  %s" % ["Saved game" if slot == "slot1" else "Autosave", str(d.get("checkpoint", "")).capitalize().replace("_", " "), str(d.get("timestamp", "")).replace("T", " ")]
		_btn(label, func(): SaveSystem.apply_snapshot(d); _character_select("solo_or_host_resume"))
	_btn("Back", _home)

func _character_select(next: String) -> void:
	_clear()
	_title("CHOOSE YOUR SURVIVOR", 56)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(row)
	for c in GameState.CHARACTERS:
		var b := Button.new()
		b.text = c.capitalize()
		b.custom_minimum_size = Vector2(340, 160)
		b.toggle_mode = true
		b.button_pressed = c == _char
		b.pressed.connect(func(): _char = c; _custom = GameState.default_customization(c); _character_select(next))
		row.add_child(b)
	var bio := Label.new()
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD
	bio.text = {
		"zegan": "Zegan. Night-shift paramedic with a dry sense of humor who keeps moving when everything says stop. Steady hands, bad knees, worse jokes.",
		"obcera": "Obcera. Motorcycle courier who knows every back alley of RaGoon City. Fast, loud, fearless, and the best shot in any room she walks into.",
	}[_char]
	_panel.add_child(bio)
	_btn("Customize %s" % _char.capitalize(), func(): _customize(next))
	var go_text := {"solo": "Start", "host": "Create Room", "join": "Next", "solo_or_host_resume": "Resume Solo"}.get(next, "Start")
	_btn(go_text, func(): _go(next))
	if next == "solo_or_host_resume":
		_btn("Resume as Co-op Host", func(): _go("host"))
	_btn("Back", _home)

func _customize(next: String) -> void:
	_clear()
	_title("%s · LOOK" % _char.to_upper(), 56)
	var outfits := HBoxContainer.new()
	outfits.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(outfits)
	for o in CharacterModel.outfits(_char):
		var b := Button.new()
		b.text = o.capitalize().replace("_", " ")
		b.toggle_mode = true
		b.button_pressed = _custom.get("outfit") == o
		b.pressed.connect(func(): _custom["outfit"] = o; _customize(next))
		outfits.add_child(b)
	for s in ["height", "shoulders", "chest", "waist", "hips", "legs", "muscle"]:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = s.capitalize()
		l.custom_minimum_size = Vector2(220, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.01
		sl.value = float(_custom.get(s, 0.5))
		sl.custom_minimum_size = Vector2(480, 60)
		sl.value_changed.connect(func(v): _custom[s] = v)
		h.add_child(sl)
		_panel.add_child(h)
	_btn("Reset", func(): _custom = GameState.default_customization(_char); _customize(next))
	_btn("Done", func(): _character_select(next))

func _go(next: String) -> void:
	GameState.customization_by_peer[1] = _custom
	match next:
		"solo", "solo_or_host_resume":
			if next == "solo":
				GameState.reset_run()
			Net.start_solo(_char)
			GameState.customization_by_peer[1] = _custom
		"host":
			if SaveSystem.read_slot("slot1").is_empty() or next == "host":
				pass
			var code := Net.host_online(_char)
			_lobby_host(code)
		"join":
			_join_menu()

func _lobby_host(code: String) -> void:
	_clear()
	_title("ROOM %s" % code, 72)
	_status = Label.new()
	_status.text = "Send this code or the invite link to your friend.\nWaiting for them to join..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_panel.add_child(_status)
	_btn("Share Invite Link", func():
		var msg := "Join my RaGoon City game: %s  (or enter code %s)" % [Net.invite_link(), code]
		DisplayServer.clipboard_set(msg)
		if OS.has_feature("android"):
			OS.shell_open("https://wa.me/?text=" + msg.uri_encode())
		_set_status("Invite copied. Waiting for your friend..."))
	_btn("Cancel", func(): Net.close(); _home())

func _join_menu(prefill := "") -> void:
	_clear()
	_title("JOIN A FRIEND", 64)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.text = prefill
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.custom_minimum_size = Vector2(0, 120)
	_panel.add_child(_code_edit)
	_btn("Paste Invite", func(): _code_edit.text = Net.parse_code(DisplayServer.clipboard_get()))
	_btn("Join", func():
		Net.join_online(_code_edit.text, _char)
		_set_status("Connecting..."))
	_status = Label.new()
	_panel.add_child(_status)
	_btn("Back", _home)

func _lan_menu() -> void:
	_clear()
	_title("SAME WI-FI", 64)
	_btn("Host on this phone", func():
		Net.host_lan(_char)
		_lobby_host("LAN"))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Host phone IP (e.g. 192.168.1.20)"
	_panel.add_child(_code_edit)
	_btn("Join", func(): Net.join_lan(_code_edit.text, _char))
	_status = Label.new()
	_panel.add_child(_status)
	_btn("Back", _home)

func _check_invite_link() -> void:
	# Android deep link ragooncity://join/CODE arrives as a command-line arg.
	for a in OS.get_cmdline_args():
		if a.to_lower().begins_with("ragooncity://"):
			_char = "obcera"
			_join_menu(Net.parse_code(a))

func _on_session_ready() -> void:
	if GameState.mode == GameState.Mode.SOLO:
		get_tree().change_scene_to_file(GameState.level_path)
	elif not multiplayer.is_server():
		_set_status("Connected. Waiting for host to start...")

func _on_partner_joined(_id: int) -> void:
	if not multiplayer.is_server():
		return
	_set_status("Your partner is here!")
	if _panel.get_child_count() > 0:
		_btn("START", func(): _start_coop.rpc(GameState.level_path, GameState.shared_checkpoint, GameState.world_flags))

@rpc("authority", "reliable", "call_local")
func _start_coop(level: String, checkpoint: String, flags: Dictionary) -> void:
	GameState.level_path = level
	GameState.shared_checkpoint = checkpoint
	GameState.world_flags = flags
	get_tree().change_scene_to_file(level)
