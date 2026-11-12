extends OmniLight3D
## Faulty-fixture flicker: mostly steady, with occasional stutters.
## Glowing materials (a neon sign's tubes) that stutter together with the light.
var linked: Array = []
var _base := 1.0
var _linked_base: Array = []
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
		var k := light_energy / maxf(_base, 0.001)
		if _linked_base.size() != linked.size():
			_linked_base = linked.map(func(m): return m.emission_energy_multiplier)
		for i in linked.size():
			linked[i].emission_energy_multiplier = _linked_base[i] * lerpf(0.08, 1.0, k)
