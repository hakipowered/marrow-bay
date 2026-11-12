class_name CustomizeScreen
extends Control
## Outfit and body screen: a lit, turning 3D preview of the survivor on the
## left (drag to spin it), outfits grouped as Classic and Hot on the right,
## then the body sliders. Every change shows on the model straight away.

signal finished(custom: Dictionary)

const SLIDERS := ["height", "shoulders", "chest", "waist", "hips", "legs", "muscle"]
const TAGS := {"classic": "CLASSIC", "hot": "HOT"}

var character := "zegan"
var custom: Dictionary = {}
## Turn slowly when nobody is dragging the preview.
var spin := true

var _model: CharacterModel
var _turntable: Node3D
var _yaw := 0.0
var _idle_spin := 0.0   # seconds before the preview turns by itself again
var _controls: VBoxContainer
var _name: Label
var _desc: Label
var _outfit_buttons := {}
var _sliders := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	margin.add_child(row)
	row.add_child(_build_preview())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_controls = VBoxContainer.new()
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls.add_theme_constant_override("separation", 16)
	scroll.add_child(_controls)
	_build_controls()
	_refresh()

# ---------- Preview ----------

func _build_preview() -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(860, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.gui_input.connect(_on_preview_input)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.012, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.52)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)
	# Key light from the front left, a red rim from behind, a cold fill.
	var key := SpotLight3D.new()
	key.transform = Transform3D(Basis(), Vector3(-1.6, 3.2, 2.6)).looking_at(Vector3(0, 0.9, 0))
	key.light_energy = 6.0
	key.spot_range = 8.0
	key.spot_angle = 32.0
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_color = Color(1.0, 0.35, 0.25)
	rim.light_energy = 1.1
	vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 50, 0)
	fill.light_color = Color(0.6, 0.7, 1.0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	# A dark floor pool so the survivor stands on something.
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.02
	ground.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.035, 0.03, 0.03)
	fm.roughness = 0.55
	ground.material_override = fm
	ground.position.y = -0.01
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.transform = Transform3D(Basis(), Vector3(0, 1.1, 4.9)).looking_at(Vector3(0, 0.9, 0))
	vp.add_child(cam)
	_turntable = Node3D.new()
	vp.add_child(_turntable)
	_model = CharacterModel.new()
	_model.character = character
	_model.customization = custom.duplicate()
	_turntable.add_child(_model)
	# Face the camera: the model looks down -Z.
	_yaw = PI
	return box

func _on_preview_input(e: InputEvent) -> void:
	var dx := 0.0
	if e is InputEventScreenDrag:
		dx = e.relative.x
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		dx = e.relative.x
	if dx != 0.0:
		_yaw += dx * 0.012
		_idle_spin = 3.0

func _process(delta: float) -> void:
	if _idle_spin > 0.0:
		_idle_spin -= delta
	elif spin:
		_yaw += delta * 0.35
	if _turntable:
		_turntable.rotation.y = _yaw
	if _model:
		_model.play("idle", false)

# ---------- Controls ----------

func _label(text: String, size := 32, color := Color(0.92, 0.88, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	_controls.add_child(l)
	return l

func _build_controls() -> void:
	var t := _label("%s · LOOK" % character.to_upper(), 56, Color(0.75, 0.12, 0.08))
	t.add_theme_constant_override("outline_size", 18)
	_name = _label("", 44)
	_desc = _label("", 28, Color(0.75, 0.7, 0.65))
	var ids := CharacterModel.outfits(character)
	for tag in TAGS:
		var in_tag := ids.filter(func(o): return Outfits.info(character, o).get("tag", "classic") == tag)
		if in_tag.is_empty():
			continue
		_label(TAGS[tag], 30, Color(0.85, 0.3, 0.2) if tag == "hot" else Color(0.7, 0.65, 0.6))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		_controls.add_child(grid)
		for o in in_tag:
			var b := Button.new()
			b.text = Outfits.display_name(character, o)
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(300, 96)
			b.add_theme_font_size_override("font_size", 30)
			b.pressed.connect(func(): _pick_outfit(o))
			grid.add_child(b)
			_outfit_buttons[o] = b
	_label("BODY", 30, Color(0.7, 0.65, 0.6))
	for s in SLIDERS:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = s.capitalize()
		l.custom_minimum_size = Vector2(220, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.01
		sl.value = float(custom.get(s, 0.5))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(420, 60)
		sl.value_changed.connect(func(v): custom[s] = v; _model.apply_customization(custom.duplicate()))
		h.add_child(sl)
		_controls.add_child(h)
		_sliders[s] = sl
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	_controls.add_child(buttons)
	for pair in [["Reset body", _reset_body], ["Done", func(): finished.emit(custom.duplicate())]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(300, 110)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		buttons.add_child(b)

func _pick_outfit(o: String) -> void:
	custom["outfit"] = o
	_model.apply_customization(custom.duplicate())
	_refresh()

func _reset_body() -> void:
	var d := GameState.default_customization(character)
	for s in SLIDERS:
		custom[s] = d[s]
		_sliders[s].set_value_no_signal(d[s])
	_model.apply_customization(custom.duplicate())

func _refresh() -> void:
	var o: String = Outfits.resolve(character, custom.get("outfit", Outfits.DEFAULT))
	custom["outfit"] = o
	_name.text = Outfits.display_name(character, o)
	_desc.text = Outfits.info(character, o).get("desc", "")
	for id in _outfit_buttons:
		_outfit_buttons[id].set_pressed_no_signal(id == o)
