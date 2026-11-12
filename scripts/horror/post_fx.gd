extends CanvasLayer
## Screen grade + heartbeat. Reads the local player's health and the director's fear level.
var rect: ColorRect
var mat: ShaderMaterial
var fear := 0.0
var _heart: AudioStreamPlayer
var _heart_t := 0.0
var _flash := 0.0
var _flash_dir := Vector2.ZERO

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
	_flash = move_toward(_flash, 0.0, delta * 2.2)
	mat.set_shader_parameter("flash", _flash)
	mat.set_shader_parameter("flash_dir", _flash_dir)
	_heart_t -= delta
	if (hurt > 0.3 or fear > 0.5) and _heart_t <= 0 and _heart.stream:
		_heart.volume_db = linear_to_db(clamp(max(hurt, fear), 0.2, 1.0))
		_heart.play()
		_heart_t = lerp(1.0, 0.45, max(hurt, fear))

func spike(amount: float) -> void:
	fear = clamp(fear + amount, 0.0, 1.0)

## Taking a hit: a red flash that floods in from the side the blow came from
## (dir in screen space, x right, y down; zero for all round), then fades.
func hit_flash(strength: float, dir := Vector2.ZERO) -> void:
	_flash = clampf(max(_flash, strength), 0.0, 1.0)
	_flash_dir = dir
	fear = clampf(fear + strength * 0.25, 0.0, 1.0)
