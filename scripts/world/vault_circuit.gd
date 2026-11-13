class_name VaultCircuit
extends Node3D
## The records vault's own electrical circuit: the ceiling tubes over the
## stacks and the vault elevator. It is dead when the survivors first come
## down (downtown lost power at 23:10 and the vault breaker tripped), and the
## breaker panel in the boiler room (BreakerPanel) brings it back.
##
## Anything that changes when the power returns joins the "vault_power" group
## and has set_powered(on, animate). Every phone runs the change itself (the
## breaker's RPC is call_local), and the flag below comes back with a save, so
## a loaded game builds everything already lit.
##
## The lights hang under this node, not under the RecordsVault room, so the
## vault's lights-out scare (HorrorDirector) can't switch them back on.

const FLAG := "power:vault"
const TUBE := Color(0.82, 0.95, 0.88)
## Where the tubes' buzz comes from when they start (middle of the stacks).
const HUM_AT := Vector3(-4.0, 2.6, 21.0)

## Ceiling tubes over the vault aisles: [position, yaw, flickers].
const TUBES := [
	[Vector3(-6.0, 3.17, 17.3), 0.0, false],
	[Vector3(-1.0, 3.17, 20.0), 0.0, true],
	[Vector3(-7.0, 3.17, 23.3), 0.0, false],
	[Vector3(-2.2, 3.17, 23.4), 0.0, false],
]

var powered := false
var _lights: Array[OmniLight3D] = []
var _glass: Array[StandardMaterial3D] = []
var _flicker_on: Array[bool] = []

static func is_on() -> bool:
	return GameState.has_flag(FLAG)

func _ready() -> void:
	add_to_group("vault_power")
	for t in TUBES:
		_tube(t[0], t[1], t[2])
	set_powered(is_on(), false)

## One fluorescent fixture: the scanned housing, its glass made to glow, and
## a cold light under it. All dark until the power comes back.
func _tube(at: Vector3, yaw: float, flicker: bool) -> void:
	var p := RoomBuilder.prop(self, "mounted_fluorescent_lights/mounted_fluorescent_lights_d", at, yaw, 1.4, false)
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D and "glass" in str(m.resource_name).to_lower():
				var g: StandardMaterial3D = m.duplicate()
				g.emission_enabled = true
				g.emission = TUBE
				g.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, g)
				_glass.append(g)
	# Dim and cold: enough to see the stacks, not enough to feel safe.
	var l := RoomBuilder.light(self, at + Vector3(0, -0.3, 0), TUBE, 0.42, 5.0, false, flicker)
	_lights.append(l)
	_flicker_on.append(flicker)

func set_powered(on: bool, animate: bool) -> void:
	powered = on
	if not animate or not on:
		for i in _lights.size():
			_lights[i].visible = on
			_lights[i].set_process(on and _flicker_on[i])
		for g in _glass:
			g.emission_energy_multiplier = 2.2 if on else 0.0
		return
	# The tubes come on one after another, each with a couple of false
	# starts, the way old starters do.
	Sfx.play_at("power_up", HUM_AT, "", 0.0, 14.0)
	for i in _lights.size():
		_light_up(i, 0.35 + i * 0.45)

func _light_up(i: int, delay: float) -> void:
	var l := _lights[i]
	l.set_process(false)
	var t := create_tween()
	t.tween_interval(delay)
	for k in 3:
		t.tween_callback(func(): l.visible = true; _glow(2.2))
		t.tween_interval(randf_range(0.04, 0.09))
		t.tween_callback(func(): l.visible = false; _glow(0.0))
		t.tween_interval(randf_range(0.08, 0.22))
	t.tween_callback(func():
		l.visible = true
		_glow(2.2)
		l.set_process(_flicker_on[i]))

func _glow(e: float) -> void:
	for g in _glass:
		g.emission_energy_multiplier = e

## A survivor says one of their own lines out loud (voice on their body,
## subtitle on every phone). `lines` maps character -> [line id, text].
## Lines live in res://assets/audio/voice/<character>/<id>.ogg.
static func survivor_line(tree: SceneTree, peer_id: int, lines: Dictionary) -> void:
	var speaker: Node3D = null
	for p in tree.get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			speaker = p
	var character: String = speaker.character if speaker else GameState.character_by_peer.get(peer_id, GameState.local_character())
	var l: Array = lines.get(character, [])
	if l.is_empty():
		return
	var path := "res://assets/audio/voice/%s/%s.ogg" % [character, l[0]]
	if speaker and ResourceLoader.exists(path):
		var a := AudioStreamPlayer3D.new()
		a.stream = load(path)
		a.unit_size = 8.0
		a.bus = "Voice"
		speaker.add_child(a)
		a.position.y = 1.6
		a.play()
		a.finished.connect(a.queue_free)
	var hud := tree.get_first_node_in_group("hud")
	if hud:
		hud.show_subtitle(character.capitalize(), l[1], 3.2)
