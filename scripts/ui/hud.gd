extends CanvasLayer
## In-game HUD and touch controls, laid out with anchors so it works on the
## Fold's near-square inner screen and the tall cover screen.
## Left: move stick. Right: look pad + Aim / Fire / Reload / Interact.
## Top: health, ammo, call-out buttons (tap = normal voice, hold = scream), menu.

var player: Player
var _hp_bar: ProgressBar
var _ammo: Label
var _weapon: Label
var _prompt: Button
var _toast: Label
var _subtitle: Label
var _coop_hint: Label
var _pause: Control
var _fire_btn: Button
var _call_btn: Button
var _call_pressed_at := 0.0
var _theme := Theme.new()

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
	_weapon = _label(root, Vector2(48, 76), 30)
	_ammo = _label(root, Vector2(48, 116), 44)

	# Action buttons, bottom-right cluster.
	_fire_btn = _button(root, "FIRE", Vector2(-260, -300), Vector2(220, 220))
	_fire_btn.button_down.connect(func(): if player: player.fire_held = true)
	_fire_btn.button_up.connect(func(): if player: player.fire_held = false)
	var aim := _button(root, "AIM", Vector2(-500, -230), Vector2(200, 160))
	aim.toggle_mode = true
	aim.toggled.connect(func(on): if player: player.aiming = on)
	var reload := _button(root, "RELOAD", Vector2(-230, -520), Vector2(180, 120))
	reload.pressed.connect(func(): if player: player.reload())
	var swap := _button(root, "WEAPON", Vector2(-450, -440), Vector2(180, 110))
	swap.pressed.connect(_cycle_weapon)
	var heal := _button(root, "HEAL", Vector2(-660, -420), Vector2(160, 110))
	heal.pressed.connect(_quick_heal)

	_prompt = _button(root, "", Vector2(-180, -180), Vector2(360, 110), true)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.62
	_prompt.anchor_bottom = 0.62
	_prompt.visible = false
	_prompt.pressed.connect(func(): if player: player.interact())

	# Call-outs: tap for normal voice, hold 0.4s for a scream.
	_call_btn = _button(root, "CALL", Vector2(-420, 36), Vector2(170, 100), false, true)
	_call_btn.button_down.connect(func(): _call_pressed_at = Time.get_ticks_msec())
	_call_btn.button_up.connect(func():
		var held := (Time.get_ticks_msec() - _call_pressed_at) / 1000.0
		CallOuts.call_partner(held > 0.4))
	_call_btn.visible = Net.is_coop()
	var menu := _button(root, "II", Vector2(-220, 36), Vector2(140, 100), false, true)
	menu.pressed.connect(toggle_pause)

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
	var b := Button.new()
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
	p.ammo_changed.connect(func(m, r): _ammo.text = "%d / %d" % [m, r])
	p.weapon_changed.connect(func(id): _weapon.text = WeaponDB.WEAPONS[id]["name"])
	p.interact_prompt.connect(func(t): _prompt.text = t; _prompt.visible = t != "")
	_hp_bar.max_value = p.max_hp
	_hp_bar.value = p.hp
	p.equip(p.inventory.equipped)

func _tint_hp(f: float) -> void:
	var fill := _theme.get_stylebox("fill", "ProgressBar") as StyleBoxFlat
	fill.bg_color = Color(0.3, 0.75, 0.35) if f > 0.6 else (Color(0.9, 0.7, 0.2) if f > 0.25 else Color(0.85, 0.15, 0.1))

func _cycle_weapon() -> void:
	if not player:
		return
	var owned: Array = WeaponDB.WEAPONS.keys().filter(func(w): return player.inventory.has_weapon(w))
	var i := owned.find(player.inventory.equipped)
	player.equip(owned[(i + 1) % owned.size()])

func _quick_heal() -> void:
	if not player:
		return
	for id in ["herb_mix", "medkit", "herb_green", "bandage"]:
		if player.inventory.items.get(id, 0) > 0 or Cheats.on("infinite_heals"):
			player.use_item(id)
			toast("Used " + WeaponDB.ITEMS[id]["name"])
			return
	toast("No healing items")

func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)

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
	_coop_hint.text = "This needs %s too.\nTap CALL to shout for them (hold to scream)." % partner
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

func show_subtitle(speaker: String, text: String, duration: float) -> void:
	_subtitle.text = ("%s: %s" % [speaker, text]) if speaker != "" else text
	_subtitle.remove_theme_color_override("font_color")
	_subtitle.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_subtitle, "modulate:a", 0.0, 0.4)

func toggle_pause() -> void:
	_pause.visible = not _pause.visible
	if _pause.visible:
		_pause.refresh()
	# Co-op never pauses the world; solo does.
	if not Net.is_coop():
		get_tree().paused = _pause.visible
