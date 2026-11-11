extends CanvasLayer
## Screen grade + heartbeat. Reads the local player's health and the director's fear level.
var rect: ColorRect
var mat: ShaderMaterial
var fear := 0.0
var _heart: AudioStreamPlayer
var _heart_t := 0.0

func _ready() -> void:
	layer = 5
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/post_fx.gdshader")
	rect.material = mat
	add_child(rect)
	_heart = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/sfx/heartbeat.ogg"):
		_heart.stream = load("res://assets/audio/sfx/heartbeat.ogg")
	add_child(_heart)

func _process(delta: float) -> void:
	fear = move_toward(fear, 0.0, delta * 0.35)
	var hurt := 0.0
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			hurt = clamp(1.0 - p.hp / p.max_hp * 1.6, 0.0, 1.0)
	mat.set_shader_parameter("hurt", hurt)
	mat.set_shader_parameter("fear", fear)
	_heart_t -= delta
	if (hurt > 0.3 or fear > 0.5) and _heart_t <= 0 and _heart.stream:
		_heart.volume_db = linear_to_db(clamp(max(hurt, fear), 0.2, 1.0))
		_heart.play()
		_heart_t = lerp(1.0, 0.45, max(hurt, fear))

func spike(amount: float) -> void:
	fear = clamp(fear + amount, 0.0, 1.0)
