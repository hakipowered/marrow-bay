extends OmniLight3D
## Faulty-fixture flicker: mostly steady, with occasional stutters.
var _base := 1.0
var _t := 0.0
func _ready() -> void:
	_base = light_energy
	_t = randf_range(1.0, 5.0)
func _process(delta: float) -> void:
	_t -= delta
	if _t < 0.0:
		light_energy = _base * randf_range(0.0, 0.4)
		if _t < -randf_range(0.05, 0.25):
			light_energy = _base
			_t = randf_range(0.8, 6.0)
