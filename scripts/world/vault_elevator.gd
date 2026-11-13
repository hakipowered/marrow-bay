class_name VaultElevator
extends Node3D
## The vault elevator Hardass sends the survivors to: an old staff freight
## lift in the records vault's west wall, down to the service tunnels.
##
## Dead until the vault circuit is back (BreakerPanel in the boiler room). A
## note taped to its doors says where the breaker is. With power, the vault
## key card opens it; inside, "Go down" plays the descent (Chapter1Story's
## "elevator" scene), once both survivors are in the car.
##
## Placed in the wall: local +z points out into the vault, +x is the player's
## right as they face the doors, the origin is on the floor in the middle of
## the doorway, in the wall's centre plane. The car is built behind the wall.
##
## `arrived` builds the same car at the bottom of the shaft (chapter 2, the
## Undercroft): no note, the B2 sign, the car light dead after the ride with
## only a red battery lamp, the doors shut until the arrival scene opens
## them (flag c2_arrival), and no going back up.

const FLAG_OPEN := "lift:open"
const CARD := "vault_card"
const DOOR_W := 1.6
const DOOR_H := 2.4
## Inside of the car, local space: x from -CAR.x to CAR.x, z from -CAR.z to 0.
const CAR := Vector3(1.8, 2.7, 2.8)
const CAR_LIGHT := 0.5

var is_open := false
var arrived := false
var _leaves: Array[Node3D] = []
var _blocker: StaticBody3D
var _outer: Area3D
var _inner: Area3D
var _car_light: OmniLight3D
var _car_panel_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _button_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _line_cool := 0.0

func _ready() -> void:
	add_to_group("vault_elevator")
	if arrived:
		_build_doors()
		_build_front()
		_build_car()
		set_powered(false, false)
		var red := UndercroftPower.emergency_light(self, Vector3(CAR.x - 0.3, CAR.y - 0.35, -CAR.z + 0.4), -90.0, 0.35, 3.5)
		red.name = "CarBattery"
		if GameState.has_flag("c2_arrival"):
			_set_open(true, false)
		return
	add_to_group("vault_power")
	_build_doors()
	_build_front()
	_build_car()
	set_powered(VaultCircuit.is_on(), false)
	if GameState.has_flag(FLAG_OPEN):
		_set_open(true, false)

func _process(delta: float) -> void:
	_line_cool = maxf(_line_cool - delta, 0.0)

# ------------------------------------------------------------------ building

## Worn brushed steel. Kept dark and fairly rough: brighter steel turned
## into a blank white sheet in the flashlight.
func _steel(shade := 0.3) -> StandardMaterial3D:
	return Mats.trim(Color(shade, shade * 0.97, shade * 0.92), 0.55, 0.75)

func _collider(at: Vector3, size: Vector3, parent: Node3D = self) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = at
	parent.add_child(sb)
	return sb

func _area(at: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	a.add_child(cs)
	a.position = at
	a.set_script(preload("res://scripts/world/interact_proxy.gd"))
	a.target = self
	add_child(a)
	return a

## Two brushed-steel leaves that part to the sides, behind the wall.
func _build_doors() -> void:
	var half := DOOR_W / 2.0 + 0.01
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * half / 2.0, 0, -0.2)
		add_child(leaf)
		RoomBuilder._box(leaf, Vector3(0, DOOR_H / 2.0, 0), Vector3(half, DOOR_H, 0.04), _steel(0.24), false)
		# Pressed ribs and a kick plate, so the steel reads as a door.
		for k in 3:
			RoomBuilder._box(leaf, Vector3((k - 1) * half * 0.28, DOOR_H * 0.55, 0.025), Vector3(0.03, DOOR_H * 0.62, 0.012), _steel(0.3), false)
		RoomBuilder._box(leaf, Vector3(0, 0.18, 0.024), Vector3(half - 0.04, 0.32, 0.01), _steel(0.18), false)
		_leaves.append(leaf)
	_blocker = _collider(Vector3(0, DOOR_H / 2.0, -0.2), Vector3(DOOR_W, DOOR_H, 0.12))
	if arrived:
		return
	# A note taped to the right-hand leaf, beside the seam.
	var note := Label3D.new()
	note.text = "LIFT DEAD AGAIN.\nVault breaker tripped.\nReset it in the BOILER ROOM,\nthrough the vault, east door.\n            - O.V."
	note.font = load("res://assets/fonts/CormorantGaramond.ttf")
	note.font_size = 44
	note.outline_size = 0
	note.pixel_size = 0.0011
	note.modulate = Color(0.12, 0.08, 0.06)
	note.shaded = true
	note.position = Vector3(-0.12, 1.45, 0.035)
	var paper := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.3)
	paper.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.82, 0.78, 0.66)
	pm.roughness = 0.95
	paper.material_override = pm
	paper.position = Vector3(-0.12, 1.45, 0.03)
	paper.rotation.z = deg_to_rad(-3.0)
	note.rotation.z = paper.rotation.z
	_leaves[1].add_child(paper)
	_leaves[1].add_child(note)
	for x in [-0.18, 0.18]:
		var tape := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(0.09, 0.03)
		tape.mesh = tq
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.75, 0.7, 0.5, 0.8)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tape.material_override = tm
		tape.position = Vector3(-0.12 + x, 1.6, 0.033)
		tape.rotation.z = deg_to_rad(randf_range(-20, 20))
		_leaves[1].add_child(tape)

## The vault side: steel frame, the floor lamp over the doors, the call
## panel with its card reader, and the stencilled sign.
func _build_front() -> void:
	var face := 0.125 + 0.03
	var frame := _steel(0.3)
	for side in [-1.0, 1.0]:
		RoomBuilder._box(self, Vector3(side * (DOOR_W / 2.0 + 0.06), (DOOR_H + 0.1) / 2.0, face), Vector3(0.12, DOOR_H + 0.1, 0.06), frame, false)
	RoomBuilder._box(self, Vector3(0, DOOR_H + 0.25, face), Vector3(DOOR_W + 0.24, 0.36, 0.06), frame, false)
	# The lamp over the doors: dark, then amber once the lift has power.
	var lamp := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.06
	lc.bottom_radius = 0.06
	lc.height = 0.03
	lamp.mesh = lc
	lamp.rotation.x = PI / 2
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.25, 0.16, 0.05)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.6, 0.15)
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, DOOR_H + 0.25, face + 0.04)
	add_child(lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.62, 0.25)
	_lamp_light.omni_range = 2.6
	_lamp_light.position = Vector3(0, DOOR_H + 0.15, face + 0.4)
	add_child(_lamp_light)
	var sign := Label3D.new()
	sign.text = "B2  -  UNDERCROFT  SERVICE  LEVEL" if arrived else "STAFF LIFT  -  SERVICE TUNNELS"
	sign.font_size = 36
	sign.outline_size = 0
	sign.pixel_size = 0.0016
	sign.modulate = Color(0.82, 0.78, 0.64)
	sign.shaded = true
	sign.position = Vector3(0, DOOR_H + 0.13, face + 0.035)
	add_child(sign)
	# Call panel on the right: a key card reader with its light, one button.
	var px := DOOR_W / 2.0 + 0.32
	RoomBuilder._box(self, Vector3(px, 1.22, face - 0.005), Vector3(0.18, 0.34, 0.05), _steel(0.36), false)
	RoomBuilder._box(self, Vector3(px, 1.3, face + 0.025), Vector3(0.11, 0.1, 0.02), Mats.trim(Color(0.04, 0.04, 0.045), 0.5, 0.2), false)
	RoomBuilder._box(self, Vector3(px, 1.3, face + 0.036), Vector3(0.07, 0.006, 0.004), Mats.trim(Color(0.0, 0.0, 0.0), 0.9), false)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.1, 0.02, 0.02)
	_led_mat.emission_enabled = true
	var led := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.008
	ls.height = 0.012
	led.mesh = ls
	led.material_override = _led_mat
	led.position = Vector3(px + 0.04, 1.34, face + 0.038)
	add_child(led)
	_button_mat = StandardMaterial3D.new()
	_button_mat.albedo_color = Color(0.25, 0.2, 0.12)
	_button_mat.emission_enabled = true
	_button_mat.emission = Color(1.0, 0.6, 0.18)
	var btn := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.025
	bc.bottom_radius = 0.028
	bc.height = 0.02
	btn.mesh = bc
	btn.rotation.x = PI / 2
	btn.material_override = _button_mat
	btn.position = Vector3(px, 1.13, face + 0.03)
	add_child(btn)
	_outer = _area(Vector3(0.2, 1.1, 0.75), Vector3(DOOR_W + 1.0, 1.7, 1.2))

## The car behind the wall: rusted steel box, anti-slip floor, a caged light,
## a handrail and the floor buttons.
func _build_car() -> void:
	var walls := Mats.surface("boiler_wall", {"tile_size": 1.6, "grime_amount": 0.8, "grime_height": 1.2, "tint": Color(0.5, 0.46, 0.42), "floor_y": 0.0, "ceiling_y": CAR.y})
	var floor_m := Mats.surface("boiler_floor", {"tile_size": 1.0, "grime_amount": 0.6})
	var z0 := -0.27
	var cz := (-CAR.z + z0) / 2.0   # middle of the car, front to back
	var dz := CAR.z + z0            # its depth
	# Floor (walkable), back and side walls, ceiling.
	RoomBuilder._box(self, Vector3(0, -0.05, cz), Vector3(CAR.x * 2 + 0.2, 0.1, dz + 0.1), floor_m, true)
	# Steel sill across the doorway, over the gap in the vault's wall.
	RoomBuilder._box(self, Vector3(0, -0.01, -0.06), Vector3(DOOR_W + 0.1, 0.03, 0.42), _steel(0.35), true)
	RoomBuilder._box(self, Vector3(0, CAR.y / 2.0, -CAR.z - 0.05), Vector3(CAR.x * 2 + 0.2, CAR.y, 0.1), walls, true)
	for side in [-1.0, 1.0]:
		RoomBuilder._box(self, Vector3(side * (CAR.x + 0.05), CAR.y / 2.0, cz), Vector3(0.1, CAR.y, dz + 0.1), walls, true)
		# Inside face of the front wall, beside the door pocket.
		RoomBuilder._box(self, Vector3(side * (DOOR_W / 2.0 + (CAR.x - DOOR_W / 2.0) / 2.0), CAR.y / 2.0, z0), Vector3(CAR.x - DOOR_W / 2.0, CAR.y, 0.04), _steel(0.33), true)
	RoomBuilder._box(self, Vector3(0, (CAR.y + DOOR_H) / 2.0, z0), Vector3(DOOR_W, CAR.y - DOOR_H, 0.04), _steel(0.33), false)
	RoomBuilder._box(self, Vector3(0, CAR.y + 0.05, cz), Vector3(CAR.x * 2 + 0.2, 0.1, dz + 0.1), _steel(0.25), false)
	# Handrail round the back.
	RoomBuilder._box(self, Vector3(0, 0.95, -CAR.z + 0.08), Vector3(CAR.x * 2 - 0.2, 0.04, 0.04), _steel(0.55), false)
	for side in [-1.0, 1.0]:
		RoomBuilder._box(self, Vector3(side * (CAR.x - 0.08), 0.95, cz - 0.3), Vector3(0.04, 0.04, dz - 0.9), _steel(0.55), false)
	# Ceiling light: a caged lamp, dark until the power is back.
	RoomBuilder._box(self, Vector3(0, CAR.y - 0.04, cz), Vector3(0.7, 0.05, 0.25), _steel(0.2), false)
	var panel := MeshInstance3D.new()
	var pq := BoxMesh.new()
	pq.size = Vector3(0.6, 0.02, 0.18)
	panel.mesh = pq
	_car_panel_mat = StandardMaterial3D.new()
	_car_panel_mat.albedo_color = Color(0.7, 0.7, 0.62)
	_car_panel_mat.emission_enabled = true
	_car_panel_mat.emission = Color(1.0, 0.9, 0.72)
	panel.material_override = _car_panel_mat
	panel.position = Vector3(0, CAR.y - 0.075, cz)
	add_child(panel)
	_car_light = OmniLight3D.new()
	_car_light.light_color = Color(1.0, 0.86, 0.66)
	_car_light.light_energy = CAR_LIGHT
	_car_light.omni_range = 3.6
	_car_light.shadow_enabled = true
	_car_light.position = Vector3(0, CAR.y - 0.35, cz)
	add_child(_car_light)
	# Floor buttons on the right-hand wall by the doors (as you stand inside
	# facing out, that's the car's -x side).
	var bx := -CAR.x + 0.02
	RoomBuilder._box(self, Vector3(bx, 1.25, z0 - 0.45), Vector3(0.03, 0.42, 0.2), _steel(0.5), false)
	var floor_lbl := Label3D.new()
	floor_lbl.text = "G\n\nB2"
	floor_lbl.font_size = 34
	floor_lbl.outline_size = 0
	floor_lbl.pixel_size = 0.0016
	floor_lbl.modulate = Color(0.1, 0.1, 0.1)
	floor_lbl.shaded = true
	floor_lbl.position = Vector3(bx + 0.017, 1.25, z0 - 0.5)
	floor_lbl.rotation.y = PI / 2
	add_child(floor_lbl)
	_inner = _area(Vector3(0, 1.1, cz), Vector3(CAR.x * 2 - 0.2, 1.7, dz - 0.1))

# ------------------------------------------------------------------ state

func set_powered(on: bool, _animate: bool) -> void:
	_lamp_mat.emission_energy_multiplier = 2.5 if on else 0.0
	_lamp_light.light_energy = 0.6 if on else 0.0
	_button_mat.emission_energy_multiplier = 1.8 if on else 0.0
	_led_mat.emission = Color(0.2, 1.0, 0.3) if is_open else Color(1.0, 0.12, 0.05)
	_led_mat.emission_energy_multiplier = 2.5 if on else 0.0
	_car_light.visible = on
	_car_panel_mat.emission_energy_multiplier = 1.6 if on else 0.0

func _set_open(open: bool, animate: bool) -> void:
	is_open = open
	if open and not arrived:
		GameState.set_flag(FLAG_OPEN)
	_blocker.collision_layer = 0 if open else 1
	_outer.collision_layer = 0 if open else 16
	_inner.collision_layer = 16 if open else 0
	_led_mat.emission = Color(0.2, 1.0, 0.3) if open else Color(1.0, 0.12, 0.05)
	var half := DOOR_W / 2.0 + 0.01
	for i in _leaves.size():
		var side := -1.0 if i == 0 else 1.0
		var x: float = side * (half / 2.0 + (half - 0.04 if open else 0.0))
		if animate:
			create_tween().tween_property(_leaves[i], "position:x", x, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			_leaves[i].position.x = x
	if animate:
		Sfx.play_at("lift_doors", global_position + Vector3.UP * 1.4, "", 0.0, 9.0)

## Shuts the doors for the ride (no collision change: the survivors are
## already inside, and the scene ends with them open again).
func close_for_ride() -> void:
	var half := DOOR_W / 2.0 + 0.01
	for i in _leaves.size():
		var side := -1.0 if i == 0 else 1.0
		create_tween().tween_property(_leaves[i], "position:x", side * half / 2.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play_at("lift_doors", global_position + Vector3.UP * 1.4, "", 0.0, 9.0)

func reopen_after_ride() -> void:
	_set_open(true, false)
	_car_light.light_energy = CAR_LIGHT
	_car_panel_mat.emission_energy_multiplier = 1.6

## The car light stutters and dies on the way down.
func flicker_car() -> void:
	var t := create_tween()
	for k in 6:
		t.tween_callback(func(): _car_light.light_energy = randf_range(0.0, 0.4); _car_panel_mat.emission_energy_multiplier = 0.2)
		t.tween_interval(randf_range(0.05, 0.14))
		t.tween_callback(func(): _car_light.light_energy = CAR_LIGHT; _car_panel_mat.emission_energy_multiplier = 1.6)
		t.tween_interval(randf_range(0.1, 0.5))
	t.tween_callback(func(): _car_light.light_energy = 0.0; _car_panel_mat.emission_energy_multiplier = 0.0)

## Where the survivors stand for the ride, in world space.
func ride_spot(i: int) -> Vector3:
	return to_global(Vector3(-0.55 if i == 0 else 0.55, 0.0, -1.3))

func doors_point() -> Vector3:
	return to_global(Vector3(0, 1.4, 0.0))

func car_point(local: Vector3) -> Vector3:
	return to_global(local)

## True when a world position is inside the car.
func in_car(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < CAR.x and l.z < 0.05 and l.z > -CAR.z

# ------------------------------------------------------------------ use

## The arrival scene: the doors grind open on the service level.
func open_on_arrival(animate := true) -> void:
	_set_open(true, animate)
	if animate:
		Sfx.play_at("flood_door_grind", global_position + Vector3.UP * 1.4, "metal_bang", -6.0, 8.0)

func interact_text(player: Node, _handle := -1) -> String:
	if arrived:
		return "Go back up" if is_open and in_car(player.global_position) else ""
	if is_open:
		return "Go down" if in_car(player.global_position) else ""
	if not VaultCircuit.is_on():
		return "Call the elevator"
	if not _has_card(player):
		return "Locked (needs a key card)"
	return "Use the vault key card"

func interact(player: Node, _handle := -1) -> void:
	if arrived:
		Sfx.play_at("lift_dead", doors_point(), "", 0.0, 6.0)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Dead. The car isn't going back up. The only way is on.")
		return
	if is_open:
		if in_car(player.global_position):
			_rpc_ride.rpc_id(1, player.peer_id)
		return
	if not VaultCircuit.is_on():
		Sfx.play_at("lift_dead", doors_point(), "", 0.0, 6.0)
		if _line_cool <= 0.0:
			_line_cool = 6.0
			_rpc_dead.rpc(player.peer_id)
		# The note on the doors goes into the bag, where it can be reread.
		if player.is_multiplayer_authority() and not player.inventory.files.has("lift_note"):
			player.inventory.add_file("lift_note")
			player.inventory_changed.emit()
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_file_hint"):
				get_tree().create_timer(3.4).timeout.connect(func(): hud.show_file_hint("lift_note"))
		return
	if not _has_card(player):
		Sfx.play_at("door_locked", doors_point(), "", 0.0, 6.0)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("It needs the vault elevator key card")
		return
	_rpc_request_open.rpc_id(1)

func _has_card(player: Node) -> bool:
	return Cheats.on("unlock_doors") or player.inventory.key_items.has(CARD)

## Pressing the dead call button: the presser says so, both phones hear it,
## and the objective comes back up to say where the power is.
@rpc("any_peer", "reliable", "call_local")
func _rpc_dead(by_peer: int) -> void:
	VaultCircuit.survivor_line(get_tree(), by_peer, {
		"zegan": ["z_lift_dead", "It's dead. No power to it."],
		"obcera": ["o_lift_dead", "Elevator's dead. We need the power on."]})
	if GameState.has_flag("story_warden"):
		get_tree().create_timer(3.0).timeout.connect(Cutscenes.show_objective)

@rpc("any_peer", "reliable", "call_local")
func _rpc_request_open() -> void:
	if multiplayer.is_server() and not is_open and VaultCircuit.is_on():
		_rpc_open.rpc()

@rpc("authority", "reliable", "call_local")
func _rpc_open() -> void:
	Sfx.play_at("card_beep", to_global(Vector3(DOOR_W / 2.0 + 0.32, 1.3, 0.3)), "", 0.0, 5.0)
	_led_mat.emission = Color(0.2, 1.0, 0.3)
	get_tree().create_timer(0.5).timeout.connect(func(): _set_open(true, true))

## Inside, "Go down": everyone has to be in the car first.
@rpc("any_peer", "reliable", "call_local")
func _rpc_ride(by_peer: int) -> void:
	if not multiplayer.is_server() or Cutscenes.active:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if not in_car(p.global_position) and not p.downed:
			_rpc_wait.rpc(by_peer)
			return
	Cutscenes.play("elevator")

@rpc("authority", "reliable", "call_local")
func _rpc_wait(by_peer: int) -> void:
	if _line_cool <= 0.0:
		_line_cool = 4.0
		VaultCircuit.survivor_line(get_tree(), by_peer, {
			"zegan": ["z_lift_wait", "Get in. We go down together."],
			"obcera": ["o_lift_wait", "In here. We go down together."]})
	if multiplayer.get_unique_id() == by_peer:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_coop_wait()
