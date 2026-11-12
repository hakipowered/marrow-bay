class_name Projectile
extends Node3D

var weapon_id := "gl"
var direction := Vector3.FORWARD
var owner_peer := 1
var authoritative := false
var hostile := false
var _speed := 26.0
var _life := 6.0
var _vel := Vector3.ZERO
var _fuse := -1.0   # throwables bounce until the fuse runs out
var _spin: Node3D = null    # a thrown grenade tumbling
var _trail: Node3D = null   # smoke behind it, left to fade when it lands

func _ready() -> void:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	_speed = {"grenade": 22.0, "rocket": 34.0, "bolt": 60.0, "acid": 14.0}.get(w.get("projectile", ""), 26.0)
	if w["kind"] == "throwable":
		_speed = 13.0
		_fuse = 1.8
	_vel = direction * _speed
	_build_look(w)

## What flies: a bolt with fletching, a launcher grenade trailing smoke, a
## rocket with its exhaust flame and smoke trail, a thrown grenade (the same
## model she holds, tumbling), or a glob of acid.
func _build_look(w: Dictionary) -> void:
	var kind: String = w.get("projectile", "")
	if w["kind"] == "throwable":
		var g := HeldWeapon.build_model(weapon_id)
		if g:
			_spin = Node3D.new()
			var box: AABB = g.get_meta("aabb", AABB())
			g.position = -box.get_center()
			_spin.add_child(g)
			add_child(_spin)
			return
	match kind:
		"acid":
			var sm := SphereMesh.new()
			sm.radius = 0.1
			sm.height = 0.2
			_add_mesh(sm, Mats.trim(Color(0.55, 0.9, 0.1), 0.2))
		"bolt":
			var rod := CylinderMesh.new()
			rod.top_radius = 0.007
			rod.bottom_radius = 0.007
			rod.height = 0.42
			_add_mesh(rod, Mats.trim(Color(0.16, 0.15, 0.14), 0.5), Vector3.ZERO, true)
			var tip := CylinderMesh.new()
			tip.top_radius = 0.0
			tip.bottom_radius = 0.012
			tip.height = 0.05
			_add_mesh(tip, Mats.trim(Color(0.6, 0.6, 0.62), 0.25), Vector3(0, 0, -0.23), true)
			for i in 3:
				var vane := BoxMesh.new()
				vane.size = Vector3(0.002, 0.03, 0.07)
				var m := _add_mesh(vane, Mats.trim(Color(0.55, 0.12, 0.08), 0.8), Vector3(0, 0, 0.17))
				m.rotation.z = TAU * i / 3.0
				m.position += m.basis.y * 0.016
		"grenade":
			var shell := CapsuleMesh.new()
			shell.radius = 0.02
			shell.height = 0.09
			_add_mesh(shell, Mats.trim(Color(0.25, 0.27, 0.2), 0.6), Vector3.ZERO, true)
			_trail = _smoke_trail(18, 0.9, 0.12, Color(0.55, 0.55, 0.55, 0.35))
		"rocket":
			var body := CylinderMesh.new()
			body.top_radius = 0.042
			body.bottom_radius = 0.042
			body.height = 0.46
			_add_mesh(body, Mats.trim(Color(0.28, 0.3, 0.22), 0.6), Vector3.ZERO, true)
			var nose := CylinderMesh.new()
			nose.top_radius = 0.0
			nose.bottom_radius = 0.042
			nose.height = 0.14
			_add_mesh(nose, Mats.trim(Color(0.2, 0.21, 0.18), 0.5), Vector3(0, 0, -0.3), true)
			_trail = _smoke_trail(60, 1.8, 0.22, Color(0.62, 0.6, 0.58, 0.55))
			var flame := GPUParticles3D.new()
			flame.amount = 14
			flame.lifetime = 0.12
			flame.position = Vector3(0, 0, 0.26)
			flame.local_coords = false
			flame.draw_pass_1 = Effects._quad(1, 1)
			flame.material_override = Effects._sprite_mat(Effects.FIREBALL_TEX, true, 2.0)
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(0, 0, 1)
			pm.spread = 6.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3.ZERO
			pm.scale_min = 0.18
			pm.scale_max = 0.28
			pm.angle_max = 360.0
			pm.anim_offset_max = 1.0
			flame.process_material = pm
			_trail.add_child(flame)
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.6, 0.25)
			l.light_energy = 2.5
			l.omni_range = 5.0
			l.position = Vector3(0, 0, 0.4)
			add_child(l)
		_:
			var m := CapsuleMesh.new()
			m.radius = 0.04
			m.height = 0.3
			_add_mesh(m, null, Vector3.ZERO, true)

func _add_mesh(mesh: Mesh, mat: Material, at := Vector3.ZERO, along_z := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = at
	if along_z:
		mi.rotation.x = PI / 2
	add_child(mi)
	return mi

## Smoke left hanging in the air behind it.
func _smoke_trail(amount: int, life: float, size: float, col: Color) -> Node3D:
	var root := Node3D.new()
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.position = Vector3(0, 0, 0.2)
	p.draw_pass_1 = Effects._quad(1, 1)
	p.material_override = Effects._sprite_mat(Effects.SMOKE_TEX, false, 1.0, 0.2)
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = size
	pm.scale_max = size * 1.4
	pm.scale_curve = Effects._curve_tex([[0, 0.5], [1, 3.0]])
	pm.angle_max = 360.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = Effects._ramp_tex([[0.0, Color(col.r, col.g, col.b, 0.0)], [0.08, col], [1.0, Color(col.r, col.g, col.b, 0.0)]])
	p.process_material = pm
	root.add_child(p)
	add_child(root)
	return root

func _physics_process(delta: float) -> void:
	_life -= delta
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	if w.get("projectile") in ["grenade", "acid"] or w["kind"] == "throwable":
		_vel.y -= 9.8 * delta
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			_detonate(global_position)
			return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + _vel * delta, (1 | 2) if hostile else (1 | 8))
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if _fuse > 0.0 and not hit.is_empty():
		# Bounce off walls and floors, losing energy.
		_vel = _vel.bounce(hit.normal) * 0.3
		global_position = hit.position + hit.normal * 0.05
		if _vel.length() > 1.5:
			Sfx.play_at("grenade_bounce", global_position, "", -6.0, 10.0)
		return
	if not hit.is_empty() or _life <= 0:
		_impact(hit)
		return
	global_position += _vel * delta
	if _vel.length() > 0.1 and absf(_vel.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + _vel, Vector3.UP)
	if _spin:
		_spin.rotate_x(-delta * 14.0)

func _impact(hit: Dictionary) -> void:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	var pos: Vector3 = hit.get("position", global_position)
	if hostile:
		Sfx.play_at("acid_splash", pos, "", 0.0, 8.0)
		Decals.splat("acid", pos, hit.get("normal", Vector3.UP))
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_multiplayer_authority() and p.global_position.distance_to(pos) < 1.6:
				p.apply_damage(w["damage"], self)
		queue_free()
		return
	_drop_trail()
	if w.has("radius"):
		Combat.explode(pos, w["damage"], w["radius"], weapon_id, owner_peer)
	elif not hit.is_empty() and hit.collider.has_meta("hit_zone"):
		Effects.blood(pos, hit.get("normal", -_vel.normalized()), _vel.normalized(), 1.6)
		if authoritative:
			hit.collider.get_meta("enemy").take_hit(w["damage"], weapon_id, hit.collider.get_meta("hit_zone"), _vel.normalized())
	elif not hit.is_empty():
		Effects.impact(pos, hit.get("normal", Vector3.UP), hit.collider)
	queue_free()

func _drop_trail() -> void:
	if _trail and is_instance_valid(_trail):
		Effects.detach_trail(_trail)
		_trail = null

func _detonate(pos: Vector3) -> void:
	_drop_trail()
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	if w.get("effect") == "flash":
		Combat.flash(pos, 10.0)
	else:
		Combat.explode(pos, w.get("damage", 200.0), w.get("radius", 5.0), weapon_id, owner_peer)
	queue_free()
