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

func _ready() -> void:
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	_speed = {"grenade": 22.0, "rocket": 34.0, "bolt": 60.0, "acid": 14.0}.get(w.get("projectile", ""), 26.0)
	_vel = direction * _speed
	var mesh := MeshInstance3D.new()
	if w.get("projectile") == "acid":
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		mesh.mesh = sm
		mesh.material_override = Mats.trim(Color(0.55, 0.9, 0.1), 0.2)
		add_child(mesh)
		return
	var m := CapsuleMesh.new()
	m.radius = 0.04
	m.height = 0.3 if w.get("projectile") != "grenade" else 0.12
	mesh.mesh = m
	mesh.rotation.x = PI / 2
	add_child(mesh)
	if w.get("projectile") == "rocket":
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.6, 0.2)
		l.omni_range = 4.0
		add_child(l)

func _physics_process(delta: float) -> void:
	_life -= delta
	var w: Dictionary = WeaponDB.WEAPONS[weapon_id]
	if w.get("projectile") in ["grenade", "acid"]:
		_vel.y -= 9.8 * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + _vel * delta, (1 | 2) if hostile else (1 | 8))
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if not hit.is_empty() or _life <= 0:
		_impact(hit)
		return
	global_position += _vel * delta
	if _vel.length() > 0.1:
		look_at(global_position + _vel, Vector3.UP)

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
	if w.has("radius"):
		Combat.explode(pos, w["damage"], w["radius"], weapon_id)
	elif not hit.is_empty() and hit.collider.has_meta("hit_zone") and authoritative:
		hit.collider.get_meta("enemy").take_hit(w["damage"], weapon_id, hit.collider.get_meta("hit_zone"), _vel.normalized())
	queue_free()
