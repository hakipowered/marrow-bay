class_name Hazard
extends Area3D
## Lingering damage zone: bloater acid gas or a fire pool.
var kind := "acid_gas"
var radius := 3.0
var duration := 6.0
var _tick := 0.0
var _fx: Node3D
var _active := true

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	add_child(cs)
	# Rolling gas or a burning pool, not flat coloured squares.
	if kind == "acid_gas":
		_fx = Effects.gas_cloud(radius)
		add_child(_fx)
		var glow := OmniLight3D.new()   # the cloud gives off a faint sick glow
		glow.light_color = Color(0.55, 0.75, 0.2)
		glow.light_energy = 0.35
		glow.omni_range = radius + 1.5
		glow.position = Vector3(0, 0.8, 0)
		glow.shadow_enabled = false
		add_child(glow)
		var t := create_tween()
		t.tween_interval(maxf(duration - 1.5, 0.1))
		t.tween_property(glow, "light_energy", 0.0, 1.5)
	else:
		_fx = Effects.make_fire(Vector3(radius * 0.6, 0.05, radius * 0.6), clampf(radius / 2.0, 0.6, 1.5))
		add_child(_fx)
	# The cloud drifts off: no new puffs for the last stretch, then it's gone.
	get_tree().create_timer(maxf(duration - 2.0, 0.1)).timeout.connect(func():
		if _fx is GPUParticles3D:
			(_fx as GPUParticles3D).emitting = false
		else:
			Effects.put_out(_fx))
	get_tree().create_timer(duration + 2.0).timeout.connect(queue_free)
	get_tree().create_timer(duration).timeout.connect(func(): _active = false)

func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0 or not _active:
		return
	_tick = 0.5
	for b in get_overlapping_bodies():
		if b is Player and b.is_multiplayer_authority():
			b.apply_damage(6.0 if kind == "acid_gas" else 8.0, self)
