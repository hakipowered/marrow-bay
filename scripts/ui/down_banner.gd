extends CanvasLayer
## Co-op: while a survivor is down, a banner counts down the time left to
## revive them, on both phones ("BLEEDING OUT" for the one on the ground,
## "<NAME> IS DOWN" for the partner, who has to get there).

var _label: Label
var _pulse := 0.0

func _ready() -> void:
	layer = 11
	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 0.2
	_label.anchor_bottom = 0.2
	_label.offset_left = -500
	_label.offset_right = 500
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/Oswald.ttf")
	f.spacing_glyph = 4
	_label.add_theme_font_override("font", f)
	_label.add_theme_font_size_override("font_size", 44)
	_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.15))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = false
	add_child(_label)

func _process(delta: float) -> void:
	var text := ""
	for p in get_tree().get_nodes_in_group("players"):
		if not p.downed or p.dead:
			continue
		var left := maxi(0, int(ceil(p.REVIVE_WINDOW - p._downed_t)))
		var clock := "0:%02d" % left
		if p.is_multiplayer_authority():
			text = "BLEEDING OUT  %s\nCall %s!" % [clock, GameState.partner_character(p.character).capitalize()]
		else:
			text = "%s IS DOWN  %s\nGet to %s and press INTERACT" % [p.character.to_upper(), clock, "her" if p.character == "obcera" else "him"]
	_label.visible = text != ""
	if _label.visible:
		_label.text = text
		_pulse += delta * 4.0
		_label.modulate.a = 0.75 + 0.25 * sin(_pulse)
