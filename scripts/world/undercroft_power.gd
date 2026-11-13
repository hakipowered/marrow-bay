class_name UndercroftPower
extends Node3D
## The Undercroft's lights (chapter 2). When the survivors ride down, the
## service level is on its battery lamps: a few caged red emergency lights,
## most of them dying. The old diesel generator in the engine hall
## (GeneratorSet) brings the work lights back, room by room, and powers the
## flood door (FloodDoor).
##
## Lights are made with work_light() and emergency_light(), which put them in
## the groups below; anything else that changes with the power joins
## "undercroft_power" and has set_powered(on, animate). The flag comes back
## with a save, so a loaded game builds everything already lit. Every phone
## runs the change itself (the generator's RPC is call_local).

const FLAG := "power:undercroft"
const TUBE := Color(0.82, 0.93, 1.0)
const EMERGENCY := Color(1.0, 0.16, 0.08)
const WORK := "uc_work_light"
const RED := "uc_emergency_light"

var powered := false

static func is_on() -> bool:
	return GameState.has_flag(FLAG)

func _ready() -> void:
	add_to_group("undercroft_power")
	set_powered.call_deferred(is_on(), false)

## A fluorescent fitting under the ceiling: the scanned housing, its glass
## made to glow, and a cold light under it. Dark until the generator runs.
static func work_light(parent: Node3D, at: Vector3, yaw := 0.0, energy := 0.6, range_m := 6.0, flicker := false) -> OmniLight3D:
	var p := RoomBuilder.prop(parent, "mounted_fluorescent_lights/mounted_fluorescent_lights_d", at, yaw, 1.4, false)
	var glass: Array = []
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D and "glass" in str(m.resource_name).to_lower():
				var g: StandardMaterial3D = m.duplicate()
				g.emission_enabled = true
				g.emission = TUBE
				g.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, g)
				glass.append(g)
	var l := RoomBuilder.light(parent, at + Vector3(0, -0.3, 0), TUBE, energy, range_m, false, flicker)
	l.set_meta("glass", glass)
	l.set_meta("flicker", flicker)
	l.visible = false
	l.set_process(false)
	l.add_to_group(WORK)
	return l

## A caged battery lamp: a red glow behind wire mesh, slowly failing.
static func emergency_light(parent: Node3D, at: Vector3, yaw := 0.0, energy := 0.5, range_m := 5.0) -> OmniLight3D:
	var cage := RoomBuilder.prop(parent, "industrial_wall_lamp", at, yaw, 1.0, false)
	for mi in cage.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D and ("glass" in str(m.resource_name).to_lower() or "bulb" in str(m.resource_name).to_lower()):
				var g: StandardMaterial3D = m.duplicate()
				g.emission_enabled = true
				g.emission = EMERGENCY
				g.emission_energy_multiplier = 2.0
				mi.set_surface_override_material(s, g)
	var l := RoomBuilder.light(parent, at + Vector3(0, -0.15, 0) + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.25), EMERGENCY, energy, range_m, false, true)
	l.set_meta("base", l.light_energy)
	l.add_to_group(RED)
	return l

func set_powered(on: bool, animate: bool) -> void:
	powered = on
	var lights := get_tree().get_nodes_in_group(WORK)
	# The battery lamps stay on, dimmed, once the real lights are back.
	for e in get_tree().get_nodes_in_group(RED):
		e.light_energy = float(e.get_meta("base", e.light_energy)) * (0.3 if on else 1.0)
	if not animate:
		for l in lights:
			_set_light(l, on)
		return
	# The tubes come on one after another down the tunnels, from the engine
	# hall outwards, each with a couple of false starts.
	var from := global_position
	lights.sort_custom(func(a, b): return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	for i in lights.size():
		_light_up(lights[i], 0.3 + i * 0.12)

func _set_light(l: OmniLight3D, on: bool) -> void:
	l.visible = on
	l.set_process(on and l.get_meta("flicker", false))
	for g in l.get_meta("glass", []):
		g.emission_energy_multiplier = 2.2 if on else 0.0

func _light_up(l: OmniLight3D, delay: float) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	for k in 2:
		t.tween_callback(func(): _set_light(l, true))
		t.tween_interval(randf_range(0.04, 0.09))
		t.tween_callback(func(): _set_light(l, false))
		t.tween_interval(randf_range(0.08, 0.2))
	t.tween_callback(func(): _set_light(l, true))
