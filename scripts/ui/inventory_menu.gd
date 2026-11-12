extends Control
## The bag: an RE-style inventory over the blurred game.
##
## Left: who you are and how you're doing (a heart monitor that reads Fine,
## Caution or Danger) and what's in your hands. Middle: the bag's slots, or
## your key items, files, or (with the cheat on) the full arsenal. Right: the
## selected thing up close (guns turn in 3D, drag to spin them) with what it
## does and what you can do with it: equip, use, combine, examine, give it to
## your partner, or drop it.
##
## Tap a slot to select it, tap it again for its main action (equip a gun,
## use a remedy). Combine: pick COMBINE, then the slot to combine with.
##
## Solo pauses the world while the bag is open; co-op never does, and the
## header says so.

const SLOT := 186.0
const GAP := 14.0
const COLS := 4
const GOLD := Color(0.86, 0.74, 0.5)
const INK := Color(0.93, 0.9, 0.84)
const DIM := Color(0.58, 0.56, 0.53)
const BLOOD := Color(0.64, 0.13, 0.1)
const FINE := Color(0.42, 0.86, 0.5)
const CAUTION := Color(0.95, 0.72, 0.25)
const DANGER := Color(0.92, 0.22, 0.16)
const GIVE_RANGE := 8.0

var player: Player
var _tab := "items"
var _sel := -1
var _combine_from := -1

var _fonts := {}
var _backdrop: ColorRect
var _panel: Control
var _coop_note: Label
var _tabs: Dictionary = {}
var _grid: GridContainer
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _hint: Label
var _slots: Array[Button] = []
var _name_lbl: Label
var _kind_lbl: Label
var _desc: Label
var _stats: VBoxContainer
var _actions: GridContainer
var _preview_icon: TextureRect
var _preview_3d: SubViewportContainer
var _vp: SubViewport
var _turntable: Node3D
var _spin := 0.0        # drag offset
var _sway_t := 0.0
var _drag := false
var _paper: PanelContainer
var _paper_text: Label
var _ecg: Ecg
var _who: Label
var _state_lbl: Label
var _hp_lbl: Label
var _eq_icon: TextureRect
var _eq_name: Label
var _eq_ammo: Label
var _examine: Control
var _examine_vp: SubViewport
var _examine_turn: Node3D
var _examine_icon: TextureRect
var _examine_name: Label
var _examine_desc: Label
var _detail_box: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_fonts()
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/menu_backdrop.gdshader")
	_backdrop.material = bm
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	center.add_child(v)
	_panel = v
	v.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 44)
	v.add_child(body)
	body.add_child(_build_status())
	body.add_child(_build_middle())
	body.add_child(_build_details())
	_build_examine()

# ---------- Open / close ----------

func open(p: Player) -> void:
	player = p
	if player == null:
		return
	if not player.inventory_changed.is_connected(_refresh):
		player.inventory_changed.connect(_refresh)
		player.health_changed.connect(func(_h, _m): _refresh_status())
	_tabs["arsenal"].visible = Cheats.on("all_weapons")
	_tab = "items"
	_combine_from = -1
	_sel = _first_filled()
	visible = true
	_coop_note.visible = Net.is_coop()
	if not Net.is_coop():
		get_tree().paused = true
	player.fire_held = false
	Sfx.ui("ui_open", -4.0)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	_refresh()

func close() -> void:
	if not visible:
		return
	_close_examine()
	visible = false
	_clear_turntable(_turntable)
	_clear_turntable(_examine_turn)
	if not Net.is_coop():
		get_tree().paused = false
	Sfx.ui("ui_close", -6.0)

func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e.pressed and not e.echo and e.physical_keycode in [KEY_ESCAPE, KEY_TAB, KEY_I]:
		if _examine.visible:
			_close_examine()
		else:
			close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_fit()
	# A slow sway around the side-on view keeps the silhouette readable;
	# dragging turns it all the way round.
	if not _drag:
		_sway_t += minf(delta, 0.05)
	for t in [_turntable, _examine_turn]:
		if t and t.get_child_count() > 0:
			t.rotation.y = _spin + sin(_sway_t * 0.7) * 0.45

## Scales the layout to the screen: the Fold's cover screen is 21:9, where
## the bag would otherwise sit small in the middle, and narrow screens shrink it.
func _fit() -> void:
	var want := _panel.get_combined_minimum_size()
	var room := get_viewport_rect().size
	if want.x <= 0.0 or want.y <= 0.0:
		return
	var s := clampf(minf(room.x * 0.96 / want.x, room.y * 0.94 / want.y), 0.6, 1.35)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(s, s)

# ---------- Building the layout ----------

func _load_fonts() -> void:
	var ts := TextServerManager.get_primary_interface()
	for k in [["head", "res://assets/fonts/Oswald.ttf", 500, 4], ["ui", "res://assets/fonts/Oswald.ttf", 400, 1], ["bold", "res://assets/fonts/Oswald.ttf", 600, 2], ["serif", "res://assets/fonts/CormorantGaramond.ttf", 500, 0]]:
		var fv := FontVariation.new()
		fv.base_font = load(k[1])
		fv.variation_opentype = {ts.name_to_tag("wght"): k[2]}
		fv.spacing_glyph = k[3]
		_fonts[k[0]] = fv

func _lbl(text: String, font: String, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _fonts[font])
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(bg: Color, border: Color, radius := 10, bw := 2, margin := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb

func _card(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = width
	var sb := _box(Color(0.035, 0.033, 0.035, 0.82), Color(GOLD, 0.22), 14, 2, 26)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	var title := _lbl("INVENTORY", "head", 66, INK)
	h.add_child(title)
	var bar := ColorRect.new()
	bar.color = Color(BLOOD, 0.9)
	bar.custom_minimum_size = Vector2(6, 66)
	h.add_child(bar)
	for t in [["items", "BAG"], ["keys", "KEY ITEMS"], ["files", "FILES"], ["arsenal", "ARSENAL"]]:
		var b := _flat_button(t[1], 32, Vector2(0, 86))
		b.custom_minimum_size.x = 210 if t[0] != "keys" else 250
		var id: String = t[0]
		b.pressed.connect(func(): _switch_tab(id))
		h.add_child(b)
		_tabs[id] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_coop_note = _lbl("THE WORLD KEEPS MOVING", "ui", 26, Color(DANGER, 0.9))
	_coop_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_coop_note)
	var x := _flat_button("CLOSE", 32, Vector2(200, 86))
	x.pressed.connect(close)
	h.add_child(x)
	return h

func _flat_button(text: String, size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", _fonts["bold"])
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", _box(Color(0.04, 0.04, 0.045, 0.7), Color(GOLD, 0.18), 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.06, 0.06, 0.065, 0.8), Color(GOLD, 0.35), 8))
	b.add_theme_stylebox_override("pressed", _box(Color(BLOOD, 0.75), Color(GOLD, 0.6), 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.03, 0.03, 0.03, 0.5), Color(GOLD, 0.08), 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _build_status() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	var card := _card(400)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	_who = _lbl("", "head", 44)
	v.add_child(_who)
	_ecg = Ecg.new()
	_ecg.custom_minimum_size = Vector2(348, 170)
	v.add_child(_ecg)
	var row := HBoxContainer.new()
	v.add_child(row)
	_state_lbl = _lbl("FINE", "head", 52, FINE)
	_state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_state_lbl)
	_hp_lbl = _lbl("", "ui", 28, DIM)
	_hp_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_hp_lbl)

	var eq := _card(400)
	col.add_child(eq)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 10)
	eq.add_child(ev)
	ev.add_child(_lbl("IN HAND", "ui", 24, DIM))
	_eq_icon = TextureRect.new()
	_eq_icon.custom_minimum_size = Vector2(348, 200)
	_eq_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_eq_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_eq_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ev.add_child(_eq_icon)
	_eq_name = _lbl("", "bold", 34)
	_eq_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_eq_name.custom_minimum_size.x = 348
	ev.add_child(_eq_name)
	_eq_ammo = _lbl("", "head", 46, GOLD)
	ev.add_child(_eq_ammo)
	return col

func _build_middle() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	var w := COLS * SLOT + (COLS - 1) * GAP
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	col.add_child(_grid)
	for i in Inventory.SIZE:
		var b := _make_slot(i)
		_grid.add_child(b)
		_slots.append(b)
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(w, 4 * SLOT + 3 * GAP)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.visible = false
	col.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	_hint = _lbl("", "ui", 28, DIM)
	_hint.custom_minimum_size = Vector2(w, 84)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)
	return col

func _make_slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 5
	icon.offset_right = -5
	icon.offset_bottom = -5
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	b.add_child(shade)
	var count := _lbl("", "head", 38, INK)
	count.name = "Count"
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -150
	count.offset_top = -58
	count.offset_right = -12
	count.offset_bottom = -6
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	count.add_theme_constant_override("outline_size", 10)
	b.add_child(count)
	var tag := _lbl("E", "bold", 26, INK)
	tag.name = "Tag"
	tag.position = Vector2(10, 8)
	tag.size = Vector2(38, 38)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tsb := _box(BLOOD, Color(GOLD, 0.7), 6, 1)
	tag.add_theme_stylebox_override("normal", tsb)
	b.add_child(tag)
	b.pressed.connect(func(): _on_slot(i))
	return b

func _build_details() -> Control:
	var card := _card(780)
	# Fixed height, so the layout doesn't jump between items.
	card.custom_minimum_size.y = 1160
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	_detail_box = v
	_kind_lbl = _lbl("", "ui", 24, Color(GOLD, 0.85))
	v.add_child(_kind_lbl)
	_name_lbl = _lbl("", "head", 50)
	_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_name_lbl.custom_minimum_size.x = 728
	v.add_child(_name_lbl)
	var stage := Panel.new()
	stage.custom_minimum_size = Vector2(728, 380)
	stage.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.025, 0.9), Color(GOLD, 0.12), 10))
	v.add_child(stage)
	_preview_icon = TextureRect.new()
	_preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_preview_icon)
	var pv := _make_stage(stage)
	_preview_3d = pv[0]
	_vp = pv[1]
	_turntable = pv[2]
	_paper = PanelContainer.new()
	_paper.custom_minimum_size = Vector2(728, 820)
	var psb := _box(Color(0.84, 0.8, 0.7), Color(0.4, 0.3, 0.2, 0.6), 4, 2, 44)
	psb.shadow_color = Color(0, 0, 0, 0.6)
	psb.shadow_size = 14
	_paper.add_theme_stylebox_override("panel", psb)
	_paper.visible = false
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_paper.add_child(ps)
	_paper_text = _lbl("", "serif", 36, Color(0.16, 0.11, 0.08))
	_paper_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_paper_text.custom_minimum_size.x = 620
	_paper_text.mouse_filter = Control.MOUSE_FILTER_PASS
	ps.add_child(_paper_text)
	v.add_child(_paper)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 8)
	v.add_child(_stats)
	_desc = _lbl("", "serif", 34, Color(0.88, 0.85, 0.78))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_desc.custom_minimum_size = Vector2(728, 150)
	v.add_child(_desc)
	_actions = GridContainer.new()
	_actions.columns = 3
	_actions.add_theme_constant_override("h_separation", 14)
	_actions.add_theme_constant_override("v_separation", 14)
	v.add_child(_actions)
	return card

## A small 3D stage (camera, key and rim light) in a SubViewport filling
## parent. Returns [container, viewport, turntable].
func _make_stage(parent: Control) -> Array:
	var c := SubViewportContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.stretch = true
	c.visible = false
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(c)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	c.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.53, 0.5)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 32, 0)
	key.light_energy = 2.3
	key.light_color = Color(1.0, 0.93, 0.84)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 200, 0)
	rim.light_energy = 1.4
	rim.light_color = Color(0.75, 0.85, 1.0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 30.0
	cam.transform = Transform3D(Basis.looking_at(-Vector3(0, 0.12, 1.6)), Vector3(0, 0.12, 1.6))
	vp.add_child(cam)
	var turn := Node3D.new()
	vp.add_child(turn)
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch or e is InputEventMouseButton:
			_drag = e.pressed
		elif e is InputEventScreenDrag or (e is InputEventMouseMotion and _drag):
			_spin += e.relative.x * 0.012)
	return [c, vp, turn]

func _build_examine() -> void:
	_examine = Control.new()
	_examine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_examine.visible = false
	add_child(_examine)
	var dark := ColorRect.new()
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0.0, 0.0, 0.0, 0.55)
	_examine.add_child(dark)
	var stage := Control.new()
	stage.anchor_left = 0.08
	stage.anchor_right = 0.92
	stage.anchor_top = 0.1
	stage.anchor_bottom = 0.7
	_examine.add_child(stage)
	_examine_icon = TextureRect.new()
	_examine_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_examine_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_examine_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(_examine_icon)
	var st := _make_stage(stage)
	_examine_vp = st[1]
	_examine_turn = st[2]
	var text := VBoxContainer.new()
	text.anchor_left = 0.2
	text.anchor_right = 0.8
	text.anchor_top = 0.72
	text.anchor_bottom = 0.98
	text.add_theme_constant_override("separation", 14)
	_examine.add_child(text)
	_examine_name = _lbl("", "head", 60)
	_examine_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_examine_name)
	_examine_desc = _lbl("", "serif", 38, Color(0.88, 0.85, 0.78))
	_examine_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_examine_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_examine_desc)
	var hint := _lbl("Drag to turn it over.  Tap BACK to return.", "ui", 26, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(hint)
	var back := _flat_button("BACK", 32, Vector2(220, 90))
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -270
	back.offset_right = -50
	back.offset_top = 44
	back.offset_bottom = 134
	back.pressed.connect(_close_examine)
	_examine.add_child(back)

# ---------- Contents ----------

func _switch_tab(id: String) -> void:
	_tab = id
	_combine_from = -1
	_sel = _first_filled() if id == "items" else 0
	Sfx.ui("ui_select", -10.0)
	_refresh()

func _first_filled() -> int:
	if player == null:
		return -1
	for i in Inventory.SIZE:
		if player.inventory.slots[i] != null and player.inventory.slots[i]["id"] == player.inventory.equipped:
			return i
	for i in Inventory.SIZE:
		if player.inventory.slots[i] != null:
			return i
	return -1

## Ids shown in the current tab, in order (items tab: slot contents).
func _entries() -> Array:
	var inv := player.inventory
	match _tab:
		"keys":
			return inv.key_items.map(func(k): return "key:" + k)
		"files":
			return inv.files.map(func(f): return "file:" + f)
		"arsenal":
			return WeaponDB.WEAPONS.keys().filter(func(w): return not WeaponDB.WEAPONS[w].get("enemy_only", false))
	return inv.slots.map(func(s): return "" if s == null else s["id"])

func _selected_id() -> String:
	var e := _entries()
	return e[_sel] if _sel >= 0 and _sel < e.size() else ""

func _refresh() -> void:
	if player == null or not visible:
		return
	for id in _tabs:
		var on: bool = id == _tab
		_tabs[id].add_theme_color_override("font_color", INK if on else DIM)
		_tabs[id].add_theme_stylebox_override("normal", _box(Color(BLOOD, 0.55) if on else Color(0.04, 0.04, 0.045, 0.7), Color(GOLD, 0.55 if on else 0.18), 8))
	var grid_tab := _tab in ["items", "keys", "arsenal"]
	_grid.visible = grid_tab
	_list_scroll.visible = not grid_tab
	if grid_tab:
		_refresh_grid()
	else:
		_refresh_list()
	_refresh_status()
	_refresh_details()

func _refresh_grid() -> void:
	var inv := player.inventory
	var e := _entries()
	var from_id := ""
	if _combine_from >= 0 and inv.slots[_combine_from] != null:
		from_id = inv.slots[_combine_from]["id"]
	for i in _slots.size():
		var b := _slots[i]
		var id: String = e[i] if i < e.size() else ""
		b.visible = _tab == "items" or i < e.size()
		var icon: TextureRect = b.get_node("Icon")
		var count: Label = b.get_node("Count")
		var tag: Label = b.get_node("Tag")
		var shade: ColorRect = b.get_node("Shade")
		icon.texture = ItemInfo.icon(id) if id != "" else null
		count.text = ""
		tag.visible = false
		count.remove_theme_color_override("font_color")
		if id != "":
			var k := ItemInfo.kind(id)
			var n: int = int(inv.slots[i]["n"]) if _tab == "items" else 1
			if k == "weapon" and WeaponDB.WEAPONS[id].has("mag"):
				var m: int = int(inv.mag.get(id, 0))
				count.text = str(m)
				count.add_theme_color_override("font_color", GOLD if m > 0 else DANGER)
			elif n > 1 or k == "ammo" or k == "throwable":
				count.text = str(n)
			tag.visible = id == inv.equipped and k in ["weapon", "throwable"]
		var selected := i == _sel
		var target := _combine_from >= 0 and id != "" and from_id != "" and (i != _combine_from or int(inv.slots[i]["n"]) >= 2) and ItemInfo.combinable(from_id, id)
		shade.visible = _combine_from >= 0 and not target and i != _combine_from
		var border := Color(GOLD, 0.95) if selected else (Color(FINE, 0.9) if target else Color(GOLD, 0.16))
		var bg := Color(0.06, 0.055, 0.05, 0.95) if id != "" else Color(0.03, 0.03, 0.033, 0.72)
		var sb := _box(bg, border, 8, 4 if (selected or target) else 2)
		if selected:
			sb.shadow_color = Color(GOLD, 0.35)
			sb.shadow_size = 12
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if _combine_from >= 0:
		_hint.text = "Combine %s with...   (tap COMBINE again to cancel)" % ItemInfo.display_name(from_id)
		_hint.add_theme_color_override("font_color", FINE)
	else:
		_hint.remove_theme_color_override("font_color")
		_hint.add_theme_color_override("font_color", DIM)
		match _tab:
			"items":
				_hint.text = "%d of %d slots free.  Tap twice to equip or use." % [inv.free_slots(), Inventory.SIZE]
			"keys":
				_hint.text = "Key items don't take bag space." if not e.is_empty() else "No key items yet."
			"arsenal":
				_hint.text = "Cheat arsenal: every weapon, outside the bag."

func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var e := _entries()
	if e.is_empty():
		var none := _lbl("No files yet. Documents you find are kept here.", "serif", 34, DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		none.custom_minimum_size.x = COLS * SLOT
		_list.add_child(none)
	for i in e.size():
		var b := _flat_button("  " + ItemInfo.display_name(e[i]), 34, Vector2(0, 104))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = ItemInfo.icon(e[i])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 84)
		if i == _sel:
			b.add_theme_stylebox_override("normal", _box(Color(BLOOD, 0.5), Color(GOLD, 0.7), 8))
			b.add_theme_color_override("font_color", INK)
		var idx := i
		b.pressed.connect(func(): _sel = idx; Sfx.ui("ui_select", -10.0); _refresh())
		_list.add_child(b)
	_hint.text = ""

func _refresh_status() -> void:
	if player == null:
		return
	var f := player.hp / player.max_hp
	_who.text = player.character.to_upper()
	var col := FINE if f > 0.66 else (CAUTION if f > 0.33 else DANGER)
	_state_lbl.text = "FINE" if f > 0.66 else ("CAUTION" if f > 0.33 else "DANGER")
	_state_lbl.add_theme_color_override("font_color", col)
	_hp_lbl.text = "%d / %d" % [int(ceil(player.hp)), int(player.max_hp)]
	_ecg.color = col
	_ecg.rate = 1.0 if f > 0.66 else (1.45 if f > 0.33 else 2.1)
	var id := player.inventory.equipped
	_eq_icon.texture = ItemInfo.icon(id) if id != "" else null
	_eq_name.text = ItemInfo.display_name(id) if id != "" else "Nothing"
	var w: Dictionary = WeaponDB.WEAPONS.get(id, {})
	if w.has("mag"):
		_eq_ammo.text = "%d / %d" % [int(player.inventory.mag.get(id, 0)), player.inventory.ammo_count(w["ammo"])]
	elif w.get("kind") == "throwable":
		_eq_ammo.text = "x%d" % player.inventory.ammo_count(id)
	else:
		_eq_ammo.text = ""

func _refresh_details() -> void:
	for c in _actions.get_children():
		c.queue_free()
	for c in _stats.get_children():
		c.queue_free()
	var id := _selected_id()
	var reading := _tab == "files" and id != ""
	_paper.visible = reading
	_preview_icon.get_parent().visible = not reading
	_desc.visible = not reading
	if id == "":
		_kind_lbl.text = ""
		_name_lbl.text = "Empty slot" if _tab == "items" else ""
		_desc.text = "Room for a weapon or a stack of supplies." if _tab == "items" else ""
		_preview_icon.texture = null
		_show_3d(_turntable, _preview_3d, "")
		return
	var k := ItemInfo.kind(id)
	_kind_lbl.text = {"weapon": "WEAPON", "throwable": "GRENADE", "ammo": "AMMUNITION", "item": "SUPPLY", "key": "KEY ITEM", "file": "FILE"}.get(k, "")
	_name_lbl.text = ItemInfo.display_name(id)
	_desc.text = ItemInfo.description(id)
	if reading:
		_name_lbl.text = ItemInfo.display_name(id)
		_paper_text.text = ItemInfo.description(id)
		return
	var has3d := _show_3d(_turntable, _preview_3d, id)
	_preview_icon.texture = null if has3d else ItemInfo.icon(id)
	# Weapon stats as short bars.
	var st := ItemInfo.stats(id)
	for label in st:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var l := _lbl(label.to_upper(), "ui", 24, DIM)
		l.custom_minimum_size.x = 150
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = st[label]
		bar.custom_minimum_size = Vector2(540, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 3, 0))
		bar.add_theme_stylebox_override("fill", _box(Color(GOLD, 0.85), Color(0, 0, 0, 0), 3, 0))
		row.add_child(bar)
		_stats.add_child(row)
	if _tab == "items" and k == "weapon" and WeaponDB.WEAPONS[id].has("mag"):
		var w: Dictionary = WeaponDB.WEAPONS[id]
		_stats.add_child(_lbl("LOADED  %d / %d      CARRIED  %d" % [int(player.inventory.mag.get(id, 0)), w["mag"], player.inventory.ammo_count(w["ammo"])], "ui", 26, GOLD))
	_add_actions(id, k)

func _add_actions(id: String, k: String) -> void:
	var inv := player.inventory
	var acts: Array = []
	if _tab == "arsenal":
		acts.append(["EQUIP" if inv.equipped != id else "IN HAND", _equip.bind(id), inv.equipped != id])
		acts.append(["EXAMINE", _open_examine.bind(id), true])
	elif _tab == "keys":
		acts.append(["EXAMINE", _open_examine.bind(id), true])
	else:
		if k in ["weapon", "throwable"]:
			acts.append(["EQUIP" if inv.equipped != id else "IN HAND", _equip.bind(id), inv.equipped != id])
		if WeaponDB.ITEMS.get(id, {}).has("heal"):
			acts.append(["USE", _use.bind(id), player.hp < player.max_hp or Cheats.on("infinite_heals")])
		if _can_combine_anything(id):
			acts.append(["CANCEL" if _combine_from >= 0 else "COMBINE", _toggle_combine, true])
		acts.append(["EXAMINE", _open_examine.bind(id), true])
		var partner := _partner()
		if partner:
			acts.append(["GIVE TO " + partner.character.to_upper(), _give, partner.global_position.distance_to(player.global_position) <= GIVE_RANGE])
		acts.append(["DROP", _drop, true])
	for a in acts:
		var b := _flat_button(a[0], 30, Vector2(234, 96))
		b.add_theme_color_override("font_color", INK)
		b.disabled = not a[2]
		b.pressed.connect(a[1])
		_actions.add_child(b)

func _can_combine_anything(id: String) -> bool:
	var inv := player.inventory
	for i in Inventory.SIZE:
		var s = inv.slots[i]
		if s == null:
			continue
		if i == _sel and int(s["n"]) < 2:
			continue
		if ItemInfo.combinable(id, s["id"]):
			return true
	return false

## Puts the item's 3D model on a stage. Returns false if it has none.
func _show_3d(turn: Node3D, container: Control, id: String) -> bool:
	_clear_turntable(turn)
	var m: Node3D = HeldWeapon.build_model(id) if ItemInfo.kind(id) in ["weapon", "throwable"] else null
	container.visible = m != null
	if m == null:
		return false
	var box: AABB = m.get_meta("aabb")
	var pivot := Node3D.new()
	pivot.add_child(m)
	m.position = -box.get_center()
	# Long guns lie across the stage, side on.
	pivot.rotation.y = PI / 2.0
	turn.add_child(pivot)
	# Frame the long side to fill most of the stage's width.
	var length := maxf(box.size.z, box.size.y)
	var aspect := maxf(container.size.x / maxf(container.size.y, 1.0), 1.0) if container.size.y > 0 else 1.9
	var cam: Camera3D = turn.get_parent().get_node("Cam")
	var half_w := aspect * tan(deg_to_rad(cam.fov * 0.5))
	var d := maxf(length * 1.3 / (2.0 * half_w), maxf(box.size.y, box.size.x) * 2.2)
	var at := Vector3(0, d * 0.12, d)
	cam.transform = Transform3D(Basis.looking_at(-at), at)
	_spin = 0.0
	_sway_t = 0.0
	return true

func _clear_turntable(turn: Node3D) -> void:
	if turn == null:
		return
	for c in turn.get_children():
		c.queue_free()

func _partner() -> Player:
	if not Net.is_coop():
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			return p
	return null

# ---------- Actions ----------

func _on_slot(i: int) -> void:
	if _tab == "items" and _combine_from >= 0:
		_finish_combine(i)
		return
	var again := i == _sel
	_sel = i
	if again:
		var id := _selected_id()
		var k := ItemInfo.kind(id)
		if k in ["weapon", "throwable"] and (_tab == "items" or _tab == "arsenal"):
			_equip(id)
			return
		if WeaponDB.ITEMS.get(id, {}).has("heal"):
			_use(id)
			return
		if id != "":
			_open_examine(id)
			return
	Sfx.ui("ui_select", -10.0)
	_refresh()

func _equip(id: String) -> void:
	player.equip(id)
	Sfx.ui("equip", -4.0)
	_refresh()

func _use(id: String) -> void:
	if player.hp >= player.max_hp and not Cheats.on("infinite_heals"):
		_flash_hint("Already at full health.")
		return
	if player.use_item(id):
		_flash_hint("Used %s." % ItemInfo.display_name(id))
	_refresh()

func _toggle_combine() -> void:
	_combine_from = -1 if _combine_from >= 0 else _sel
	Sfx.ui("ui_select", -10.0)
	_refresh()

func _finish_combine(target: int) -> void:
	var from := _combine_from
	_combine_from = -1
	if target == from and (player.inventory.slots[from] == null or int(player.inventory.slots[from]["n"]) < 2):
		_refresh()
		return
	var msg := player.inventory.combine(from, target)
	if msg == "":
		Sfx.ui("ui_select", -10.0)
		_flash_hint("Those don't go together.")
	else:
		Sfx.ui("ui_combine", -3.0)
		_flash_hint(msg)
		player._emit_ammo()
		_sel = target if player.inventory.slots[target] != null else _first_filled()
	_refresh()

func _close_examine() -> void:
	_examine.visible = false
	_panel.visible = true
	_clear_turntable(_examine_turn)

func _open_examine(id: String) -> void:
	_examine.visible = true
	_panel.visible = false
	_examine_name.text = ItemInfo.display_name(id)
	_examine_desc.text = ItemInfo.description(id)
	var stage_box: Control = _examine_icon.get_parent()
	var has3d := _show_3d(_examine_turn, stage_box.get_child(1), id)
	_examine_icon.texture = null if has3d else ItemInfo.icon(id)
	Sfx.ui("ui_select", -8.0)

## Hands the whole stack (a gun with its loaded rounds) to the partner.
func _give() -> void:
	var partner := _partner()
	var s = player.inventory.slots[_sel] if _sel >= 0 else null
	if partner == null or s == null:
		return
	var id: String = s["id"]
	var n: int = int(s["n"])
	var rounds: int = int(player.inventory.mag.get(id, 0))
	player.inventory.take_from_slot(_sel, n)
	partner.receive_item.rpc_id(partner.peer_id, id, n, rounds, player.character.capitalize())
	_after_removal(id)
	_flash_hint("Gave %s to %s." % [ItemInfo.display_name(id), partner.character.capitalize()])
	Sfx.ui("ui_combine", -6.0)
	_refresh()

## Drops the stack at your feet (a gun's loaded rounds go back in the bag
## when there's room). Either of you can pick it up again.
func _drop() -> void:
	var s = player.inventory.slots[_sel] if _sel >= 0 else null
	if s == null:
		return
	var id: String = s["id"]
	var n: int = int(s["n"])
	var rounds: int = int(player.inventory.mag.get(id, 0))
	player.inventory.take_from_slot(_sel, n)
	if rounds > 0 and WeaponDB.WEAPONS.get(id, {}).has("ammo"):
		player.inventory.add_ammo(WeaponDB.WEAPONS[id]["ammo"], rounds)
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("request_drop"):
		var fwd: Vector3 = -player.body.global_transform.basis.z
		level.request_drop(Pickup.item_string(id), player.global_position + fwd * 0.6, n)
	_after_removal(id)
	_flash_hint("Dropped %s." % ItemInfo.display_name(id))
	Sfx.ui("ui_close", -8.0)
	_refresh()

func _after_removal(id: String) -> void:
	if player.inventory.equipped == id and not player.inventory.has_weapon(id):
		player.equip(player._fallback_weapon())
	player._emit_ammo()
	if _sel >= 0 and player.inventory.slots[_sel] == null:
		_sel = _first_filled()

func _flash_hint(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", INK)
	_hint.modulate = Color(1.4, 1.3, 1.1)
	create_tween().tween_property(_hint, "modulate", Color.WHITE, 0.6)

# ---------- Heart monitor ----------

## A scrolling ECG trace: green and steady when fine, amber and quick at
## caution, red and racing in danger.
class Ecg extends Control:
	var color := Color(0.42, 0.86, 0.5)
	var rate := 1.0
	var _t := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _beat(p: float) -> float:
		# One heartbeat over p in 0..1: P wave, QRS spike, T wave.
		var y := 0.0
		y += 0.12 * exp(-pow((p - 0.16) / 0.035, 2.0))
		y -= 0.14 * exp(-pow((p - 0.27) / 0.012, 2.0))
		y += 1.0 * exp(-pow((p - 0.3) / 0.014, 2.0))
		y -= 0.3 * exp(-pow((p - 0.335) / 0.014, 2.0))
		y += 0.22 * exp(-pow((p - 0.52) / 0.06, 2.0))
		return y

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.03, 0.02, 0.85))
		for gx in range(0, int(w), 29):
			draw_line(Vector2(gx, 0), Vector2(gx, h), Color(color, 0.07), 1.0)
		for gy in range(0, int(h), 29):
			draw_line(Vector2(0, gy), Vector2(w, gy), Color(color, 0.07), 1.0)
		var period := 2.4 / rate
		var head := fmod(_t, period) / period * w
		var beats := 1.6
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var x := 0.0
		while x <= w:
			var p := fmod(x / w * beats, 1.0)
			pts.append(Vector2(x, h * 0.62 - _beat(p) * h * 0.48))
			var behind := fmod(head - x + w, w) / w
			cols.append(Color(color, clampf(1.0 - behind * 1.15, 0.0, 1.0)))
			x += 3.0
		draw_polyline_colors(pts, cols, 3.0, true)
		var hp := Vector2(head, h * 0.62 - _beat(fmod(head / w * beats, 1.0)) * h * 0.48)
		draw_circle(hp, 5.0, Color(1, 1, 1, 0.9))
		draw_circle(hp, 12.0, Color(color, 0.25))
