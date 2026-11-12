extends CanvasLayer
## Game over. Comes up a moment after a survivor dies (while the camera is
## still pulling away from the body): the screen sinks to black and red, the
## words fade in with a low sting, then Continue (from the last checkpoint)
## and Quit to title. In co-op both players press Continue to go again.

var who := ""            # the character who died
const DELAY := 2.4       # seconds of the death itself before the screen
const LINES := [
	"RaGoon City keeps what it kills.",
	"No one is coming for the dead.",
	"The rain will wash it away by morning.",
	"The Tallyman adds one more to the count.",
]

var _bg: ColorRect
var _veil: ColorRect
var _title: Label
var _line: Label
var _buttons: VBoxContainer
var _continue: Button
var _status: Label

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if hud and hud.get("_theme"):
		root.theme = hud._theme
	add_child(root)
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0, 0, 0, 0)
	root.add_child(_bg)
	# Blood-dark edges closing in.
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 c = UV - 0.5;
	c.x *= 1.6;
	float d = length(c);
	float edge = smoothstep(0.25, 0.95, d);
	COLOR = vec4(0.22, 0.0, 0.0, amount * (0.35 + edge * 0.65));
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_veil.material = mat
	root.add_child(_veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	center.add_child(col)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var me := GameState.local_character()
	_title.text = "YOU DIED" if who == "" or who == me else "%s DIED" % who.to_upper()
	var serif := FontVariation.new()
	serif.base_font = load("res://assets/fonts/CormorantGaramond.ttf")
	serif.variation_embolden = 0.6
	serif.spacing_glyph = 14
	_title.add_theme_font_override("font", serif)
	_title.add_theme_font_size_override("font_size", 150)
	_title.add_theme_color_override("font_color", Color(0.62, 0.05, 0.04))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 10)
	_title.modulate.a = 0.0
	col.add_child(_title)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.text = LINES[randi() % LINES.size()]
	var italic := FontVariation.new()
	italic.base_font = serif.base_font
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	_line.add_theme_font_override("font", italic)
	_line.add_theme_font_size_override("font_size", 40)
	_line.add_theme_color_override("font_color", Color(0.75, 0.72, 0.7))
	_line.modulate.a = 0.0
	col.add_child(_line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	col.add_child(gap)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 18)
	_buttons.modulate.a = 0.0
	_buttons.visible = false
	col.add_child(_buttons)
	var where := GameState.shared_checkpoint.capitalize().replace("_", " ")
	_continue = _button("Continue" + (" from %s" % where if where != "" else ""), _on_continue)
	_button("Quit to title", _on_quit)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 28)
	_status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.65))
	_buttons.add_child(_status)
	_run()

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560, 96)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_buttons.add_child(b)
	return b

func _run() -> void:
	await get_tree().create_timer(DELAY, true, false, false).timeout   # game time: the slow motion stretches it
	Sfx.ui("game_over_sting", -2.0)
	var t := create_tween().set_parallel(true)
	t.set_ignore_time_scale(true)
	t.tween_property(_bg, "color:a", 0.82, 2.4)
	var vm := _veil.material as ShaderMaterial
	t.tween_method(func(v: float): vm.set_shader_parameter("amount", v), 0.0, 1.0, 2.0)
	t.tween_property(_title, "modulate:a", 1.0, 1.8).set_delay(0.5)
	_title.pivot_offset = _title.size / 2.0
	_title.scale = Vector2(1.08, 1.08)
	t.tween_property(_title, "scale", Vector2.ONE, 3.0).set_delay(0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_line, "modulate:a", 1.0, 1.4).set_delay(1.8)
	await t.finished
	_buttons.visible = true
	var t2 := create_tween()
	t2.set_ignore_time_scale(true)
	t2.tween_property(_buttons, "modulate:a", 1.0, 0.6)

func _on_continue() -> void:
	_continue.disabled = true
	if Net.is_coop():
		_status.text = "Waiting for %s..." % GameState.partner_character(GameState.local_character()).capitalize()
	var level := get_tree().get_first_node_in_group("level")
	if level:
		level.vote_continue()

## The host relays how many have pressed Continue.
func show_votes(have: int, need: int) -> void:
	if need > 1 and have < need:
		_status.text = "%d of %d ready" % [have, need] if _continue.disabled else "%s wants to go again. Press Continue." % GameState.partner_character(GameState.local_character()).capitalize()

func _on_quit() -> void:
	Engine.time_scale = 1.0
	Music.override_track = ""
	get_tree().paused = false
	Net.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
