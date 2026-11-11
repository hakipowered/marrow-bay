extends Node
## Lightweight one-shot visual effects (tracers, sparks, blood, explosions, flame).

func _scene() -> Node:
	return get_tree().current_scene

func _spawn_particles(pos: Vector3, normal: Vector3, color: Color, amount: int, speed: float, size: float, life := 0.5, gravity := 9.8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	_scene().add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)

func blood(pos: Vector3, normal: Vector3) -> void:
	_spawn_particles(pos, normal, Color(0.35, 0.02, 0.02), 14, 3.0, 1.6, 0.6)
	Decals.splat("blood", pos, normal)

func impact(pos: Vector3, normal: Vector3, _col: Object) -> void:
	_spawn_particles(pos, normal, Color(1.0, 0.8, 0.45), 8, 4.0, 0.8, 0.25)
	_spawn_particles(pos, normal, Color(0.5, 0.48, 0.45), 6, 1.2, 2.2, 0.8, 1.0)
	Decals.splat("bullet_hole", pos, normal)

func tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	_scene().add_child(mi)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.light_energy = 3.0
	flash.omni_range = 5.0
	_scene().add_child(flash)
	flash.global_position = from
	get_tree().create_timer(0.04).timeout.connect(func(): mi.queue_free(); flash.queue_free())

func flame(from: Vector3, dir: Vector3, length: float) -> void:
	_spawn_particles(from, dir, Color(1.0, 0.5, 0.1), 10, length * 1.8, 6.0, 0.35, -2.0)

func explosion(pos: Vector3, radius: float) -> void:
	_spawn_particles(pos, Vector3.UP, Color(1.0, 0.55, 0.15), 40, radius * 3.0, 8.0, 0.6, 2.0)
	_spawn_particles(pos, Vector3.UP, Color(0.15, 0.13, 0.12), 30, radius, 14.0, 1.6, -0.5)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 12.0
	l.omni_range = radius * 3.0
	_scene().add_child(l)
	l.global_position = pos
	var t := l.create_tween()
	t.tween_property(l, "light_energy", 0.0, 0.5)
	t.tween_callback(l.queue_free)
