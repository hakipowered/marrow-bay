class_name BreakerPanel
extends Node3D
## The vault breaker in the boiler room. Hardass tells the survivors the
## vault elevator needs power; this is where it comes from. Its red fault lamp
## blinks and its handle catches the light until someone throws it, then the
## vault's tubes and the elevator come on (VaultCircuit, "vault_power" group)
## and the objective moves on to the elevator.
##
## Placed on a wall: local +z points out of the wall into the room, +x is the
## player's right as they face it, the origin is on the floor at the wall face.
## Either survivor can throw it; the host decides and every phone plays it.

const HANDLE_ON := -PI * 0.92

var _handle: Node3D
var _fault: MeshInstance3D
var _fault_mat: StandardMaterial3D
var _fault_light: OmniLight3D
var _glint: OmniLight3D
var _blink := 0.0
var _busy := false

func _ready() -> void:
	add_to_group("vault_power")
	_build()
	_set_state(VaultCircuit.is_on(), false)

func _build() -> void:
	# The scanned breaker box, door hanging open, its rows of breakers tripped.
	RoomBuilder.prop(self, "power_box_01", Vector3(-0.12, 1.42, 0.075), 0.0, 1.25, false)
	# The main switch beside it: a painted steel case with a big side handle.
	var paint := Mats.trim(Color(0.16, 0.2, 0.18), 0.65, 0.4)
	var steel := Mats.trim(Color(0.36, 0.35, 0.33), 0.5, 0.8)
	RoomBuilder._box(self, Vector3(0.42, 1.36, 0.1), Vector3(0.34, 0.54, 0.2), paint, false)
	RoomBuilder._box(self, Vector3(0.42, 1.34, 0.205), Vector3(0.26, 0.4, 0.012), Mats.trim(Color(0.11, 0.14, 0.13), 0.7, 0.35), false)
	# Conduit from the case up into the ceiling.
	RoomBuilder._box(self, Vector3(0.42, 2.7, 0.04), Vector3(0.035, 2.1, 0.035), steel, false)
	# Enamel plate over it, so it reads from across the room.
	RoomBuilder._box(self, Vector3(0.42, 1.7, 0.03), Vector3(0.3, 0.085, 0.012), Mats.trim(Color(0.78, 0.74, 0.62), 0.6), false)
	_label("VAULT  /  LIFT", Vector3(0.42, 1.7, 0.038), 30, Color(0.45, 0.06, 0.04))
	_label("ON", Vector3(0.62, 1.58, 0.213), 20, Color(0.7, 0.68, 0.6))
	_label("OFF", Vector3(0.62, 1.12, 0.213), 20, Color(0.7, 0.68, 0.6))
	_handle = Node3D.new()
	_handle.position = Vector3(0.62, 1.36, 0.12)
	add_child(_handle)
	var hub := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.045
	hc.bottom_radius = 0.045
	hc.height = 0.05
	hub.mesh = hc
	hub.rotation.z = PI / 2
	hub.material_override = steel
	_handle.add_child(hub)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.03, 0.34, 0.03)
	arm.mesh = am
	arm.position = Vector3(0.03, -0.17, 0)
	arm.material_override = steel
	_handle.add_child(arm)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.028
	gm.bottom_radius = 0.028
	gm.height = 0.16
	grip.mesh = gm
	grip.rotation.z = PI / 2
	grip.position = Vector3(0.08, -0.34, 0)
	grip.material_override = Mats.trim(Color(0.6, 0.05, 0.03), 0.45, 0.1)
	_handle.add_child(grip)
	# Fault lamp on the case: blinks red while the circuit is down, steady
	# green once it's back. A chrome bezel round it.
	RoomBuilder._box(self, Vector3(0.3, 1.56, 0.205), Vector3(0.06, 0.06, 0.02), steel, false)
	_fault = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.024
	sm.height = 0.03
	_fault.mesh = sm
	_fault_mat = StandardMaterial3D.new()
	_fault_mat.albedo_color = Color(0.2, 0.02, 0.02)
	_fault_mat.emission_enabled = true
	_fault.material_override = _fault_mat
	_fault.position = Vector3(0.3, 1.56, 0.218)
	add_child(_fault)
	_fault_light = OmniLight3D.new()
	_fault_light.omni_range = 1.8
	_fault_light.position = Vector3(0.3, 1.58, 0.35)
	add_child(_fault_light)
	# A soft glint on the handle every couple of seconds, like the items on
	# the floor: this is something to use.
	_glint = OmniLight3D.new()
	_glint.light_color = Color(1.0, 0.86, 0.62)
	_glint.omni_range = 1.1
	_glint.light_energy = 0.0
	_glint.position = Vector3(0.7, 1.1, 0.35)
	add_child(_glint)
	# What the survivor's reach ray finds (layer 16, like doors).
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.4, 1.7, 1.1)
	cs.shape = b
	a.add_child(cs)
	a.position = Vector3(0.25, 1.05, 0.55)
	a.set_script(preload("res://scripts/world/interact_proxy.gd"))
	a.target = self
	add_child(a)

## Small painted lettering on the case.
func _label(text: String, at: Vector3, size: int, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 0
	l.pixel_size = 0.0011
	l.modulate = color
	l.shaded = true
	l.double_sided = false
	l.position = at
	add_child(l)

func _process(delta: float) -> void:
	if VaultCircuit.is_on() or _busy:
		return
	_blink += delta
	var lit := fmod(_blink, 1.1) < 0.45
	_fault_mat.emission_energy_multiplier = 3.0 if lit else 0.15
	_fault_light.light_energy = 0.55 if lit else 0.0
	var g := fmod(_blink, 2.6)
	_glint.light_energy = clampf(1.0 - absf(g - 0.4) / 0.4, 0.0, 1.0) * 0.6

func interact_text(_player: Node, _handle_id := -1) -> String:
	if VaultCircuit.is_on() or _busy:
		return ""
	return "Turn on the power"

func interact(player: Node, _handle_id := -1) -> void:
	if VaultCircuit.is_on() or _busy:
		return
	_rpc_request.rpc_id(1, player.peer_id)

@rpc("any_peer", "reliable", "call_local")
func _rpc_request(by_peer: int) -> void:
	if not multiplayer.is_server() or VaultCircuit.is_on() or _busy:
		return
	_rpc_power_on.rpc(by_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_power_on(by_peer: int) -> void:
	if VaultCircuit.is_on():
		return
	GameState.set_flag(VaultCircuit.FLAG)
	_busy = true
	var at := global_position + global_transform.basis * Vector3(0.5, 1.4, 0.2)
	Sfx.play_at("breaker_throw", at, "", 2.0, 8.0)
	var t := create_tween()
	t.tween_property(_handle, "rotation:x", HANDLE_ON, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		_busy = false
		_set_state(true, true)
		get_tree().call_group("vault_power", "set_powered", true, true))
	get_tree().create_timer(2.4).timeout.connect(func():
		VaultCircuit.survivor_line(get_tree(), by_peer, {
			"zegan": ["z_power_on", "That's the power. The elevator should run now."],
			"obcera": ["o_power_on", "Lights. Now let's get to that elevator."]}))
	Cutscenes.set_objective("Take the vault elevator down")

func set_powered(on: bool, _animate: bool) -> void:
	_set_state(on, false)

func _set_state(on: bool, _animate: bool) -> void:
	if on:
		_handle.rotation.x = HANDLE_ON
		_fault_mat.albedo_color = Color(0.03, 0.2, 0.05)
		_fault_mat.emission = Color(0.25, 1.0, 0.35)
		_fault_mat.emission_energy_multiplier = 2.2
		_fault_light.light_color = Color(0.3, 1.0, 0.4)
		_fault_light.light_energy = 0.35
		_glint.light_energy = 0.0
	else:
		_handle.rotation.x = 0.0
		_fault_mat.emission = Color(1.0, 0.12, 0.06)
		_fault_light.light_color = Color(1.0, 0.15, 0.08)
