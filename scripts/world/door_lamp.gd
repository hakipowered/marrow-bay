class_name DoorLamp
extends Node3D
## A caged lamp on the wall beside a barred steel door in the Undercroft: dark
## while the power is off, red while the door is barred, green once it opens
## for the survivors (the flag "unlocked:<door_id>"). The muster room's is the
## only green light down there, so from the engine hall it shows the way to
## the Warden: Hardass draws the bar over the tannoy (Chapter2Story's intercom
## scene), it goes red again while he fights them behind it, and green when
## he's down.
##
## Every phone works it out for itself from the power and the flag, so a
## loaded game, a skipped scene or a late joiner shows the right colour. The
## story calls refresh_all() when it changes the flag, so it switches at once.

const GROUP := "door_lamps"

const RED := Color(1.0, 0.12, 0.06)
const GREEN := Color(0.3, 1.0, 0.38)
const DARK := 0
const BARRED := 1
const OPEN := 2

var door_id := ""
var _glass: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _state := -1
var _check := 0.0

static func make(parent: Node3D, at: Vector3, yaw: float, door: String) -> DoorLamp:
	var d := DoorLamp.new()
	d.name = "DoorLamp_" + door
	d.door_id = door
	d.position = at
	parent.add_child(d)
	d._build(yaw)
	return d

## Every lamp shows what it should now (after the story changes a door).
static func refresh_all(tree: SceneTree) -> void:
	for l in tree.get_nodes_in_group(GROUP):
		l.refresh()

func refresh() -> void:
	var w := want()
	if w != _state:
		_apply(w)

func _build(yaw: float) -> void:
	add_to_group(GROUP)
	var cage := RoomBuilder.prop(self, "industrial_wall_lamp", Vector3.ZERO, yaw, 0.85, false)
	for mi in cage.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var n := str(m.resource_name).to_lower() if m else ""
			if m is StandardMaterial3D and ("glass" in n or "bulb" in n):
				var g: StandardMaterial3D = m.duplicate()
				g.emission_enabled = true
				g.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, g)
				_glass.append(g)
	var out := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.22)
	# A signal lamp, not a work light: it glows and tints the door, it
	# doesn't flood the tunnel.
	_light = RoomBuilder.light(self, Vector3(0, -0.12, 0) + out, GREEN, 0.3, 2.4)
	_light.visible = false
	_apply(want())

## What the lamp should show now.
func want() -> int:
	if not UndercroftPower.is_on():
		return DARK
	return OPEN if GameState.has_flag("unlocked:" + door_id) else BARRED

func state() -> int:
	return _state

func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	refresh()

func _apply(w: int) -> void:
	_state = w
	var c := GREEN if w == OPEN else RED
	_light.visible = w != DARK
	_light.light_color = c
	_light.light_energy = (0.3 if w == OPEN else 0.2) * RoomBuilder.LIGHT_SCALE
	for g in _glass:
		g.albedo_color = Color(0.25, 0.25, 0.25) if w == DARK else c.lerp(Color.WHITE, 0.25)
		g.emission = c
		g.emission_energy_multiplier = 0.0 if w == DARK else (5.0 if w == OPEN else 3.5)
