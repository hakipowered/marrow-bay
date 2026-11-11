class_name Hazard
extends Area3D
## Lingering damage zone: bloater acid gas or a fire pool.
var kind := "acid_gas"
var radius := 3.0
var duration := 6.0
var _tick := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	add_child(cs)
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.7
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.15)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.5, 0.75, 0.1, 0.18) if kind == "acid_gas" else Color(1.0, 0.45, 0.1, 0.5)
	q.material = m
	p.mesh = q
	add_child(p)
	get_tree().create_timer(duration).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0:
		return
	_tick = 0.5
	for b in get_overlapping_bodies():
		if b is Player and b.is_multiplayer_authority():
			b.apply_damage(6.0 if kind == "acid_gas" else 8.0, self)
