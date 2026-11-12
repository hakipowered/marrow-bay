class_name Crosshair
extends Control
## Aiming dot in the middle of the screen, where every shot is aimed (shots
## leave along the camera's centre line). Bright while aiming, faint with a gun
## lowered (hip-fire goes there too), red over an infected, amber over
## something that will blow up (a fuel drum, a gas cylinder). Hidden for the
## knife and the hatchet.

const HITBOX_MASK := 1 | 8

var _alpha := 0.0
var _want := 0.0
var _on_enemy := false
var _on_explosive := false
var _ring := 0.0

func update_from(p: Node) -> void:
	_want = 0.0
	_on_enemy = false
	_on_explosive = false
	if p == null or not is_instance_valid(p) or p.get("input_locked") or p.get("downed"):
		_fade()
		return
	var w: Dictionary = p.weapon()
	if w.is_empty() or w["kind"] == "melee":
		_fade()
		return
	var raised: bool = p.aiming or p.get("_hip_t") > 0.0
	_want = 1.0 if raised else 0.4
	var cam: Camera3D = p.camera
	# A ring for the spread (shots land within ±half of it): the dot alone for
	# a steady aimed pistol, open from the hip and for shotguns.
	var spread := deg_to_rad(float(w.get("spread", 0.0))) * (1.0 if p.aiming else 2.0)
	if cam:
		_ring = minf(tan(spread * 0.5) / tan(deg_to_rad(cam.fov) * 0.5) * size.y * 0.5, 140.0)
	if cam and raised:
		var from: Vector3 = cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * 60.0, HITBOX_MASK, [p.get_rid()])
		q.collide_with_areas = true
		var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
		_on_enemy = not hit.is_empty() and hit.collider.has_meta("hit_zone")
		var b := Breakable.of(hit.get("collider"))
		_on_explosive = b != null and not b.broken and b.explosive()
	_fade()

func _fade() -> void:
	_alpha = move_toward(_alpha, _want, get_process_delta_time() * 6.0)
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.01:
		return
	var c := size * 0.5
	var col := Color(1.0, 0.28, 0.22) if _on_enemy else (Color(1.0, 0.62, 0.15) if _on_explosive else Color(1, 1, 1))
	col.a = _alpha
	var shade := Color(0, 0, 0, 0.55 * _alpha)
	draw_circle(c, 7.5, shade)
	draw_circle(c, 5.0, col)
	if _ring > 14.0:
		var ring := col
		ring.a *= 0.45
		draw_arc(c, _ring, 0.0, TAU, 48, Color(0, 0, 0, 0.3 * _alpha), 4.0, true)
		draw_arc(c, _ring, 0.0, TAU, 48, ring, 2.0, true)
