class_name CustomizeScreen
extends Control
## Outfit and body screen: a lit, turning 3D preview of the survivor on the
## left (drag to spin it, pinch or the view buttons to zoom from the whole
## body to the face, pose buttons to see them stand, walk or run), outfits
## grouped as Classic and Hot on the right, then the body sliders. Every
## change shows on the model straight away.

signal finished(custom: Dictionary)

const SLIDERS := ["height", "shoulders", "chest", "waist", "hips", "legs", "muscle"]
const TAGS := {"classic": "CLASSIC", "hot": "HOT"}
## Preview camera views: label and zoom (0 whole body .. 1 face).
const VIEWS := {"full": ["Full body", 0.0], "upper": ["Waist up", 0.5], "face": ["Face", 1.0]}
## Preview poses: model state -> label.
const POSES := {"idle": "Stand", "walk": "Walk", "run": "Run"}
## Top of the head at height slider 0.5, in metres.
const HEIGHTS := {"zegan": 1.83, "obcera": 1.76}

var character := "zegan"
var custom: Dictionary = {}
## Turn slowly when nobody is dragging the preview.
var spin := true

var _model: CharacterModel
var _turntable: Node3D
var _yaw := 0.0
var _cam: Camera3D
var _zoom := 0.0
var _zoom_target := 0.0
var _pose := "idle"
var _pose_buttons := {}
var _view_buttons := {}
var _touches := {}
var _pinch := 0.0
var _body_turn := 0.0
var _body_turn_ready := false
var _hips := Vector2.ZERO
var _head := Vector3.INF
var _head_follow := Vector3.INF
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
	scroll.size_flags_stretch_ratio = 1.0
	row.add_child(scroll)
	_controls = VBoxContainer.new()
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls.add_theme_constant_override("separation", 16)
	scroll.add_child(_controls)
	_build_controls()
	_refresh()

# ---------- Preview ----------

func _build_preview() -> Control:
	# A framed stage: the 3D view fills it, with view and pose buttons on top.
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.15
	frame.custom_minimum_size = Vector2(820, 0)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.018, 0.012, 0.012)
	fs.border_color = Color(0.45, 0.08, 0.05, 0.8)
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fs)
	var stage := Control.new()
	stage.clip_contents = true
	frame.add_child(stage)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.gui_input.connect(_on_preview_input)
	stage.add_child(box)
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
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.03, 0.03)
	env.fog_density = 0.04
	we.environment = env
	vp.add_child(we)
	# Key light from the front left, a red rim from behind, a cold fill.
	var key := SpotLight3D.new()
	key.transform = Transform3D(Basis(), Vector3(-1.6, 3.2, 2.6)).looking_at(Vector3(0, 0.9, 0))
	key.light_energy = 4.2
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
	_cam = Camera3D.new()
	_cam.fov = 30.0
	vp.add_child(_cam)
	_turntable = Node3D.new()
	vp.add_child(_turntable)
	_model = CharacterModel.new()
	_model.character = character
	_model.customization = custom.duplicate()
	_turntable.add_child(_model)
	# Face the camera: the model looks down -Z.
	_yaw = PI
	# View buttons along the bottom, pose buttons along the top.
	var top := _overlay_row(stage, true)
	for p in POSES:
		_pose_buttons[p] = _overlay_button(top, POSES[p], func(): _set_pose(p))
	var bottom := _overlay_row(stage, false)
	for v in VIEWS:
		_view_buttons[v] = _overlay_button(bottom, VIEWS[v][0], func(): _set_view(v))
	var hint := Label.new()
	hint.text = "Drag to turn · pinch to zoom"
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6, 0.7))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	bottom.move_child(hint, 0)
	_set_pose("idle")
	_set_view("full")
	_zoom = _zoom_target
	return frame

func _overlay_row(stage: Control, at_top: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if not at_top else BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_TOP_WIDE if at_top else Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 20
	row.offset_right = -20
	if at_top:
		row.offset_top = 20
		row.offset_bottom = 100
	else:
		row.offset_top = -100
		row.offset_bottom = -20
	stage.add_child(row)
	return row

func _overlay_button(row: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(150, 76)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	row.add_child(b)
	return b

func _set_pose(p: String) -> void:
	_pose = p
	for k in _pose_buttons:
		_pose_buttons[k].set_pressed_no_signal(k == p)

func _set_view(v: String) -> void:
	_zoom_target = VIEWS[v][1]
	for k in _view_buttons:
		_view_buttons[k].set_pressed_no_signal(k == v)

## Height of the top of the head for the current outfit and height slider.
func _top() -> float:
	return HEIGHTS.get(character, 1.8) * (_model.scale.y if _model else 1.0)

func _frame_camera(delta: float) -> void:
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-delta * 7.0))
	var h := _top()
	# 0 = whole body, 0.5 = waist up, 1 = face.
	var centre: float
	var shown: float
	if _zoom < 0.5:
		var t := _zoom / 0.5
		centre = lerpf(h * 0.5, h * 0.74, t)
		shown = lerpf(h * 1.16, h * 0.62, t)
	else:
		var t := (_zoom - 0.5) / 0.5
		centre = lerpf(h * 0.74, h * 0.92, t)
		shown = lerpf(h * 0.62, h * 0.3, t)
	# Close views follow the head, which the clips move about.
	var x := 0.0
	if _head != Vector3.INF:
		var t := clampf((_zoom - 0.3) / 0.7, 0.0, 1.0)
		_head_follow = _head_follow.lerp(_head, 1.0 - exp(-delta * 5.0)) if _head_follow != Vector3.INF else _head
		x = _head_follow.x * t
		centre = lerpf(centre, _head_follow.y + h * 0.035, t)
	var dist := shown * 0.5 / tan(deg_to_rad(_cam.fov * 0.5))
	_cam.transform = Transform3D(Basis(), Vector3(x, centre + shown * 0.06, dist)).looking_at(Vector3(x, centre, 0))

func _on_preview_input(e: InputEvent) -> void:
	# Touch only: the desktop mouse is turned into touches by the project
	# settings, and touches into mouse events, so reading both would double up.
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch = 0.0
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch > 0.0:
				_zoom_target = clampf(_zoom_target + (d - _pinch) * 0.0025, 0.0, 1.0)
				_zoom = _zoom_target
				_clear_view_buttons()
			_pinch = d
		else:
			_yaw += e.relative.x * 0.012
		_idle_spin = 3.0
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom_target = clampf(_zoom_target + (0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1), 0.0, 1.0)
		_clear_view_buttons()

func _clear_view_buttons() -> void:
	for k in _view_buttons:
		_view_buttons[k].set_pressed_no_signal(is_equal_approx(VIEWS[k][1], _zoom_target))

func _process(delta: float) -> void:
	if _idle_spin > 0.0:
		_idle_spin -= delta
	elif spin:
		_yaw += delta * 0.35
	if _model:
		_model.play(_pose, false)
		_follow_body(delta)
	if _turntable:
		_turntable.rotation.y = _yaw - _body_turn
	if _cam:
		_frame_camera(delta)

## Keeps the survivor on the turntable's axis with the chest to the camera
## at the "front" angle, whatever the clip does with the hips and shoulders
## (the idle stands half turned, the aim stance side on).
func _follow_body(delta: float) -> void:
	var hips = _model.bone_position("Hips")
	var l = _model.bone_position("LeftArm")
	var r = _model.bone_position("RightArm")
	if hips == null or l == null or r == null:
		return
	var k := 1.0 - exp(-delta * 2.5)
	var across: Vector3 = r - l
	var turn := atan2(-across.z, across.x)
	if _body_turn_ready:
		_body_turn = lerp_angle(_body_turn, turn, k)
		_hips = _hips.lerp(Vector2(hips.x, hips.z), k)
	else:
		_body_turn = turn
		_hips = Vector2(hips.x, hips.z)
		_body_turn_ready = true
	_model.position = -Vector3(_hips.x, 0.0, _hips.y) * _model.scale.x
	var head = _model.bone_position("Head")
	if head != null:
		_head = _model.to_global(head)

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
