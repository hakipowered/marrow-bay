extends CanvasLayer
## In-game HUD and touch controls, laid out with anchors so it works on the
## Fold's near-square inner screen and the tall cover screen.
## Left: move stick. Right: look pad + Aim / Fire / Reload / Interact.
## Top: health, ammo, call-out buttons (tap = normal voice, hold = scream), menu.

var player: Player
var _hp_bar: ProgressBar
var _ammo: Label
var _weapon: Label
var _weapon_icon: TextureRect
var _inventory: Control
var _weapon_pressed_at := 0.0
var _weapon_long := false
var _prompt: Button
var _toast: Label
var _subtitle: Label
var _coop_hint: Label
var _pause: Control
var _fire_btn: Button
var _call_btn: Button
var _call_pressed_at := 0.0
var _theme := Theme.new()
var _crosshair: Crosshair

func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_build_theme()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)

	var stick := TouchStick.new()
	stick.anchor_right = 0.45
	stick.anchor_bottom = 1.0
	stick.anchor_top = 0.3
	stick.moved.connect(func(v): if player: player.move_input = v; player.running = v.length() > 0.92)
	root.add_child(stick)
	var look := LookPad.new()
	look.anchor_left = 0.45
	look.anchor_right = 1.0
	look.anchor_top = 0.12
	look.anchor_bottom = 1.0
	look.look.connect(func(d): if player: player.look_delta += d)
	root.add_child(look)

	# Health + ammo
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.position = Vector2(48, 40)
	_hp_bar.custom_minimum_size = Vector2(380, 26)
	root.add_child(_hp_bar)
	# Equipped weapon: its icon in a small frame, name and rounds beside it.
	var frame := Panel.new()
	frame.position = Vector2(48, 80)
	frame.size = Vector2(150, 96)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.04, 0.04, 0.05, 0.6)
	fsb.border_color = Color(0.85, 0.75, 0.55, 0.45)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	root.add_child(frame)
	_weapon_icon = TextureRect.new()
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_weapon_icon.position = Vector2(4, 4)
	_weapon_icon.size = Vector2(142, 88)
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_weapon_icon)
	_weapon = _label(root, Vector2(214, 78), 30)
	_ammo = _label(root, Vector2(214, 114), 44)

	# Action buttons, bottom-right cluster.
	_fire_btn = _button(root, "FIRE", Vector2(-260, -300), Vector2(220, 220))
	_fire_btn.button_down.connect(func(): if player: player.fire_held = true)
	_fire_btn.button_up.connect(func(): if player: player.fire_held = false)
	var aim := _button(root, "AIM", Vector2(-500, -230), Vector2(200, 160))
	aim.toggle_mode = true
	aim.toggled.connect(func(on): if player: player.aiming = on)
	var reload := _button(root, "RELOAD", Vector2(-230, -520), Vector2(180, 120))
	reload.pressed.connect(func(): if player: player.reload())
	# Tap: next weapon. Hold: open the bag.
	var swap := _button(root, "WEAPON", Vector2(-450, -440), Vector2(180, 110))
	swap.button_down.connect(func(): _weapon_pressed_at = Time.get_ticks_msec(); _weapon_long = false)
	swap.button_up.connect(func():
		if not _weapon_long:
			_cycle_weapon())
	var heal := _button(root, "HEAL", Vector2(-660, -420), Vector2(160, 110))
	heal.pressed.connect(_quick_heal)
	# Dodge roll, next to AIM where the thumb already is.
	var roll := _button(root, "ROLL", Vector2(-700, -230), Vector2(180, 160))
	roll.button_down.connect(func(): if player: player.roll())

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	_prompt = _button(root, "", Vector2(-180, -180), Vector2(360, 110), true)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.62
	_prompt.anchor_bottom = 0.62
	_prompt.visible = false
	_prompt.pressed.connect(func(): if player: player.interact())

	# Call-outs: tap for a quick normal call, hold to pick any line
	# (help, go, come, the partner's name, and all the screams).
	_call_btn = _button(root, "CALL", Vector2(-420, 36), Vector2(170, 100), false, true)
	_call_btn.button_down.connect(func(): _call_pressed_at = Time.get_ticks_msec())
	_call_btn.button_up.connect(func():
		var held := (Time.get_ticks_msec() - _call_pressed_at) / 1000.0
		if held > 0.35:
			open_callout_picker()
		else:
			CallOuts.call_partner(false))
	# Always shown: in solo the line is still voiced (and the AI partner
	# will answer it once that lands).
	var menu := _button(root, "II", Vector2(-220, 36), Vector2(140, 100), false, true)
	menu.pressed.connect(toggle_pause)
	var bag := _button(root, "BAG", Vector2(-620, 36), Vector2(170, 100), false, true)
	bag.pressed.connect(toggle_inventory)

	_toast = _label(root, Vector2(0, 0), 34)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.18
	_toast.anchor_bottom = 0.18
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle = _label(root, Vector2(0, -170), 40)
	_subtitle.anchor_left = 0.1
	_subtitle.anchor_right = 0.9
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	_coop_hint = _label(root, Vector2(0, 0), 32)
	_coop_hint.anchor_left = 0.5
	_coop_hint.anchor_right = 0.5
	_coop_hint.anchor_top = 0.5
	_coop_hint.anchor_bottom = 0.5
	_coop_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_coop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_inventory = preload("res://scripts/ui/inventory_menu.gd").new()
	_inventory.visible = false
	add_child(_inventory)

	_pause = preload("res://scripts/ui/pause_menu.gd").new()
	_pause.theme = _theme
	_pause.visible = false
	add_child(_pause)

	CallOuts.callout_played.connect(_on_callout)
	SaveSystem.saved.connect(func(slot): toast("Autosaved" if slot == SaveSystem.AUTOSAVE_SLOT else "Game saved"))

func _build_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.55)
	sb.border_color = Color(0.85, 0.75, 0.55, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(0.5, 0.15, 0.1, 0.7)
	_theme.set_stylebox("normal", "Button", sb)
	_theme.set_stylebox("hover", "Button", sb)
	_theme.set_stylebox("pressed", "Button", sbp)
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_font_size("font_size", "Button", 30)
	_theme.set_font_size("font_size", "Label", 30)
	_theme.set_color("font_color", "Label", Color(0.93, 0.9, 0.84))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.02, 0.02, 0.6)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.75, 0.35)
	fill.set_corner_radius_all(6)
	_theme.set_stylebox("background", "ProgressBar", bg)
	_theme.set_stylebox("fill", "ProgressBar", fill)

func _label(parent: Control, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, offset: Vector2, size: Vector2, center := false, top := false) -> Button:
	var b := TouchButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if not center:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 0.0 if top else 1.0
		b.anchor_bottom = 0.0 if top else 1.0
	b.offset_left = offset.x
	b.offset_top = offset.y
	b.offset_right = offset.x + size.x
	b.offset_bottom = offset.y + size.y
	parent.add_child(b)
	return b

func bind_player(p: Player) -> void:
	player = p
	p.health_changed.connect(func(hp, mx): _hp_bar.max_value = mx; _hp_bar.value = hp; _tint_hp(hp / mx))
	p.ammo_changed.connect(_show_ammo)
	p.weapon_changed.connect(func(id):
		_weapon.text = WeaponDB.WEAPONS[id]["name"]
		_weapon_icon.texture = ItemInfo.icon(id))
	p.interact_prompt.connect(func(t): _prompt.text = t; _prompt.visible = t != "")
	_hp_bar.max_value = p.max_hp
	_hp_bar.value = p.hp
	p.equip(p.inventory.equipped)

func _show_ammo(in_mag: int, reserve: int) -> void:
	if in_mag < 0 and reserve < 0:
		_ammo.text = ""          # knife, hatchet: nothing to count
	elif in_mag < 0:
		_ammo.text = "x%d" % reserve
	else:
		_ammo.text = "%d / %d" % [in_mag, reserve]
	_ammo.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if in_mag == 0 else Color(0.93, 0.9, 0.84))

func _process(_d: float) -> void:
	_crosshair.update_from(player)
	if _weapon_pressed_at > 0.0 and not _weapon_long and (Time.get_ticks_msec() - _weapon_pressed_at) > 450.0:
		_weapon_long = true
		_weapon_pressed_at = 0.0
		toggle_inventory()

## Opens or closes the bag. Solo pauses the world; co-op never does, so the
## menu reminds you that things can still reach you.
func toggle_inventory() -> void:
	if _pause.visible:
		return
	if _inventory.visible:
		_inventory.close()
	else:
		_inventory.open(player)

func _tint_hp(f: float) -> void:
	var fill := _theme.get_stylebox("fill", "ProgressBar") as StyleBoxFlat
	fill.bg_color = Color(0.3, 0.75, 0.35) if f > 0.6 else (Color(0.9, 0.7, 0.2) if f > 0.25 else Color(0.85, 0.15, 0.1))

func _cycle_weapon() -> void:
	_weapon_pressed_at = 0.0
	if not player:
		return
	var owned := player.inventory.weapon_list()
	if owned.is_empty():
		return
	var i := owned.find(player.inventory.equipped)
	player.equip(owned[(i + 1) % owned.size()])

func _quick_heal() -> void:
	if not player:
		return
	if player.hp >= player.max_hp:
		toast("Already at full health")
		return
	# Smallest remedy that still does the job first, so nothing is wasted.
	var missing := player.max_hp - player.hp
	var order := ["bandage", "herb_green", "herb_gg", "herb_mix", "medkit"]
	var pick := ""
	for id in order:
		if player.inventory.count(id) > 0 or Cheats.on("infinite_heals"):
			pick = id   # the strongest so far, unless a smaller one is enough
			if WeaponDB.ITEMS[id]["heal"] >= missing:
				break
	if pick != "" and player.use_item(pick):
		toast("Used " + WeaponDB.ITEMS[pick]["name"])
		return
	toast("No healing items")

func show_file_hint(_id: String) -> void:
	toast("New file. Read it in the bag under Files.")

func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)

var _picker: Control

## Every call-out line for this character as buttons: normal lines first,
## screams in red. Closes after a pick.
func open_callout_picker() -> void:
	if _picker and is_instance_valid(_picker):
		_picker.queue_free()
		return
	var character := GameState.local_character()
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -330
	panel.offset_bottom = 330
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.88)
	sb.border_color = Color(0.5, 0.15, 0.12)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "Call %s" % GameState.partner_character(character).capitalize()
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(90, 70)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): panel.queue_free())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for scream in [false, true]:
		for line in CallOuts.lines_for(character, scream):
			var b := Button.new()
			var t: String = line["text"]
			b.text = t if t.length() <= 26 else t.substr(0, 24) + "..."
			b.custom_minimum_size = Vector2(340, 84)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 24)
			if scream:
				b.add_theme_color_override("font_color", Color(1.0, 0.5, 0.42))
			var id: String = line["id"]
			b.pressed.connect(func():
				CallOuts.call_partner(scream, id)
				panel.queue_free())
			grid.add_child(b)
	add_child(panel)
	_picker = panel

## Flash grenade went off in view: white screen that fades out.
func white_flash(secs: float) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 1)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var t := create_tween()
	t.tween_interval(secs * 0.3)
	t.tween_property(r, "color:a", 0.0, secs * 0.7)
	t.tween_callback(r.queue_free)

func show_coop_wait() -> void:
	var partner := GameState.partner_character(GameState.local_character()).capitalize()
	_coop_hint.text = "This needs %s too.\nTap CALL to shout for them (hold CALL to pick a line)." % partner
	_coop_hint.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(3.0)
	t.tween_property(_coop_hint, "modulate:a", 0.0, 0.8)
	var pulse := create_tween().set_loops(4)
	pulse.tween_property(_call_btn, "modulate", Color(1.6, 0.8, 0.6), 0.25)
	pulse.tween_property(_call_btn, "modulate", Color.WHITE, 0.25)

func _on_callout(_peer: int, character: String, _id: String, text: String, scream: bool) -> void:
	_subtitle.text = "%s: %s" % [character.capitalize(), text]
	_subtitle.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if scream else Color(0.95, 0.92, 0.85))
	_subtitle.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.5)
	t.tween_property(_subtitle, "modulate:a", 0.0, 0.6)

# ---------- Meters (a boss's health, the generator's crank) ----------

var _meters := {}
var _meter_box: VBoxContainer

## A labelled bar at the top of the screen, made on first use and updated
## after: `frac` 0..1. Bosses show their health this way; the generator its
## progress while it is cranked.
func show_meter(id: String, label: String, frac: float, color := Color(0.75, 0.12, 0.08)) -> void:
	if _meter_box == null:
		_meter_box = VBoxContainer.new()
		_meter_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_meter_box.anchor_left = 0.3
		_meter_box.anchor_right = 0.7
		_meter_box.offset_top = 96
		_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_meter_box.theme = _theme
		_meter_box.add_theme_constant_override("separation", 6)
		add_child(_meter_box)
	var m: Dictionary = _meters.get(id, {})
	if m.is_empty():
		var name := Label.new()
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_font_size_override("font_size", 26)
		name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		name.add_theme_constant_override("outline_size", 6)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 18)
		bar.max_value = 1.0
		bar.step = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		fill.set_corner_radius_all(3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.04, 0.04, 0.75)
		bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		_meter_box.add_child(name)
		_meter_box.add_child(bar)
		m = {"label": name, "bar": bar}
		_meters[id] = m
	m["label"].text = label
	var t := create_tween()
	t.tween_property(m["bar"], "value", clampf(frac, 0.0, 1.0), 0.2)

func hide_meter(id: String) -> void:
	var m: Dictionary = _meters.get(id, {})
	if m.is_empty():
		return
	_meters.erase(id)
	m["label"].queue_free()
	m["bar"].queue_free()

func show_subtitle(speaker: String, text: String, duration: float) -> void:
	_subtitle.text = ("%s: %s" % [speaker, text]) if speaker != "" else text
	_subtitle.remove_theme_color_override("font_color")
	_subtitle.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_subtitle, "modulate:a", 0.0, 0.4)

func toggle_pause() -> void:
	if _inventory.visible:
		_inventory.close()
	_pause.visible = not _pause.visible
	if _pause.visible:
		_pause.refresh()
	# Co-op never pauses the world; solo does.
	if not Net.is_coop():
		get_tree().paused = _pause.visible
