class_name Hazard
extends Area3D
## Lingering damage zone: bloater acid gas or a fire pool. A fire pool also
## burns the infected who walk into it and cooks off drums standing in it.
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
	# (Tweens on the hazard itself, so a level reload leaves nothing waiting.)
	_after(maxf(duration - 2.0, 0.1), _wind_down)
	_after(duration, func(): _active = false)
	_after(duration + 2.0, queue_free)

func _after(secs: float, what: Callable) -> void:
	var t := create_tween()
	t.tween_interval(secs)
	t.tween_callback(what)

func _wind_down() -> void:
	if _fx is GPUParticles3D:
		(_fx as GPUParticles3D).emitting = false
		for g in _fx.find_children("*", "GPUParticles3D", true, false):
			g.emitting = false
	else:
		Effects.put_out(_fx)

func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0 or not _active:
		return
	_tick = 0.5
	for b in get_overlapping_bodies():
		if b is Player and b.is_multiplayer_authority():
			b.apply_damage(6.0 if kind == "acid_gas" else 8.0, self)
	if kind != "fire":
		return
	# A burning pool sets the infected who walk through it alight (every phone
	# sees them burn; the host hurts them) and cooks off drums standing in it.
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.get("state") == Zombie.S.DEAD or z.get("data").get("fire_immune", false):
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0.0
		if to.length() < radius + 0.3:
			Effects.ignite(z, 2.5)
			if multiplayer.is_server():
				z.take_hit(7.0, "flamer", "torso", Vector3.ZERO)
	if multiplayer.is_server():
		for br in get_tree().get_nodes_in_group("breakables"):
			if not br.broken and br.explosive() and (br.global_transform * br.center).distance_to(global_position) < radius + 0.6:
				br.host_damage(0.0, "fire", global_position, Vector3.UP)
