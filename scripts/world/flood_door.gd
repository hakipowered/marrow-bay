class_name FloodDoor
extends Node3D
## The flood door between the engine hall and the deep stacks (chapter 2): a
## riveted steel slab in a channel frame that rises on a motor. Dead until
## the generator runs, and even then its control box is locked out until
## someone turns the Warden's key in its key switch (he carries it: the
## Warden fight). Then the klaxon sounds, the beacon over it turns, and it
## grinds up into the wall. The flags keep the key in and the door open after
## a load. A save from before the pump room (Chapter2Story.OLD_FLOW) opens it
## on power alone, as it did then.
##
## Placed in a doorway: local +z points into the room it's seen from (the
## engine hall), the origin is on the floor at the middle of the opening.

const W := 4.0
const H := 3.2
const FLAG := "c2_flood_open"
const TOP := 6.1   # the guides run this high (the engine hall's vault)
const KEY_FLAG := "c2_flood_key_in"
const KEY := "flood_key"
## The control box on the wall beside the door (local), and where that is
## from the door's origin as the Undercroft places it (turned to face north
## into the engine hall), for the camera.
const BOX := Vector3(-W / 2 - 0.62, 1.25, 0.215)
const BOX_FROM_HALL := Vector3(W / 2 + 0.62, 1.25, -0.215)

var _slab: Node3D
var _beacon: Node3D
var _beacon_light: SpotLight3D
var _beacon_mat: StandardMaterial3D
var _klaxon: AudioStreamPlayer3D
var _spinning := false
var _powered := false
## The control box's lamps: supply (amber), locked out (red), raising (green).
var _lamps := {}
var _key_vis: Node3D
var _key_turn: Node3D

func _ready() -> void:
	add_to_group("undercroft_power")
	add_to_group("flood_door")
	_powered = UndercroftPower.is_on()
	_build()
	_key_vis.visible = key_in()
	if key_in():
		_key_turn.rotation.z = -PI / 2
	if GameState.has_flag(FLAG):
		_slab.position.y = H - 0.35
	_lamp(GameState.has_flag(FLAG))

static func key_in() -> bool:
	return GameState.has_flag(KEY_FLAG)

## Whether this door still waits for the Warden's key once it has power.
static func needs_key() -> bool:
	return not GameState.has_flag(Chapter2Story.OLD_FLOW)

func _build() -> void:
	var steel := Mats.surface("flood_steel", {"tile_size": 1.6, "grime_amount": 0.6, "tint": Color(0.62, 0.6, 0.55)})
	var frame := Mats.trim(Color(0.16, 0.16, 0.15), 0.6, 0.7)
	var dark := Mats.trim(Color(0.05, 0.05, 0.05), 0.9, 0.2)
	# Channel guides up the wall, the slab rises between them to the motor
	# housing under the vault.
	for x in [-W / 2 - 0.1, W / 2 + 0.1]:
		RoomBuilder._box(self, Vector3(x, TOP / 2, 0.08), Vector3(0.22, TOP, 0.4), frame, true)
	RoomBuilder._box(self, Vector3(0, TOP + 0.2, 0.12), Vector3(W + 0.42, 0.4, 0.5), frame, false)
	UndercroftKit.bar(self, Vector3(-W / 2 + 0.6, TOP + 0.2, 0.42), 0.16, 0.5, frame, "x")
	RoomBuilder._box(self, Vector3(0, 0.01, 0.05), Vector3(W + 0.2, 0.02, 0.4), dark, false)
	# The slab: ribbed plate with a band of hazard stripes along its foot.
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	RoomBuilder._box(_slab, Vector3(0, H / 2, 0), Vector3(W, H, 0.16), steel, true)
	for i in 4:
		var y := 0.55 + i * 0.75
		RoomBuilder._box(_slab, Vector3(0, y, 0.1), Vector3(W - 0.1, 0.09, 0.05), steel, false)
	for x in [-W / 2 + 0.25, 0.0, W / 2 - 0.25]:
		RoomBuilder._box(_slab, Vector3(x, H / 2, 0.1), Vector3(0.1, H - 0.1, 0.05), steel, false)
	var stripes := StandardMaterial3D.new()
	stripes.albedo_texture = _stripe_texture()
	stripes.uv1_scale = Vector3(6, 1, 1)
	stripes.roughness = 0.7
	var band := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(W - 0.1, 0.32)
	band.mesh = q
	band.material_override = stripes
	band.position = Vector3(0, 0.2, 0.131)
	_slab.add_child(band)
	UndercroftKit.label(_slab, "FLOOD DOOR  No. 3", Vector3(0, 2.6, 0.131), 64, Color(0.82, 0.78, 0.66), 0.0, 0.0022)
	UndercroftKit.label(_slab, "KEEP  CLEAR  WHEN  ALARM  SOUNDS", Vector3(0, 2.3, 0.131), 34, Color(0.75, 0.2, 0.12), 0.0, 0.0022)
	# The beacon over it, dead until there's power.
	_beacon = Node3D.new()
	_beacon.position = Vector3(W / 2 - 0.3, H + 0.62, 0.3)
	add_child(_beacon)
	var cage := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.1
	cm.height = 0.16
	cage.mesh = cm
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.35, 0.18, 0.02)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.5, 0.05)
	_beacon_mat.emission_energy_multiplier = 0.0
	cage.material_override = _beacon_mat
	_beacon.add_child(cage)
	RoomBuilder._box(self, Vector3(W / 2 - 0.3, H + 0.52, 0.2), Vector3(0.2, 0.05, 0.3), frame, false)
	_beacon_light = SpotLight3D.new()
	_beacon_light.light_color = Color(1.0, 0.55, 0.1)
	_beacon_light.spot_range = 9.0
	_beacon_light.spot_angle = 28.0
	_beacon_light.light_energy = 0.0
	_beacon_light.rotation_degrees = Vector3(-15, 0, 0)
	_beacon.add_child(_beacon_light)
	_build_box()
	UndercroftKit.reach(self, self, Vector3(0, 1.2, 0.6), Vector3(W, 2.0, 0.8), 0)
	UndercroftKit.reach(self, self, BOX + Vector3(0, -0.1, 0.4), Vector3(0.8, 1.6, 0.7), 1)

## The motor's control box on the wall beside the door: a painted steel case
## on a backplate, with an enamel plate, three lamps (SUPPLY, LOCKED OUT,
## RAISING), the key switch (OFF / ON, WARDEN'S KEY ONLY), a black RAISE
## and a red STOP button, and its conduits.
func _build_box() -> void:
	var box := Node3D.new()
	box.name = "ControlBox"
	box.position = BOX
	add_child(box)
	var paint := Mats.surface("cabinet_paint", {"tile_size": 0.5, "grime_amount": 0.7, "tint": Color(0.62, 0.66, 0.62)})
	var steel := Mats.trim(Color(0.3, 0.29, 0.28), 0.4, 0.85)
	var chrome := Mats.trim(Color(0.62, 0.62, 0.6), 0.22, 1.0)
	var black := Mats.trim(Color(0.03, 0.03, 0.03), 0.45, 0.1)
	var enamel := Mats.trim(Color(0.84, 0.8, 0.68), 0.45)
	var ink := Color(0.1, 0.08, 0.06)
	# Backplate, case, the door's rim and its four screws.
	RoomBuilder._box(box, Vector3(0, -0.05, -0.08), Vector3(0.5, 0.8, 0.02), steel, false)
	RoomBuilder._box(box, Vector3(0, 0, 0), Vector3(0.42, 0.62, 0.16), paint, true)
	RoomBuilder._box(box, Vector3(0, 0, 0.081), Vector3(0.39, 0.59, 0.004), paint, false)
	for c in [Vector2(-0.17, 0.27), Vector2(0.17, 0.27), Vector2(-0.17, -0.27), Vector2(0.17, -0.27)]:
		UndercroftKit.bar(box, Vector3(c.x, c.y, 0.085), 0.008, 0.006, chrome, "z", 8)
	# Plate.
	RoomBuilder._box(box, Vector3(0, 0.23, 0.085), Vector3(0.32, 0.08, 0.004), enamel, false)
	UndercroftKit.label(box, "FLOOD DOOR No.3\nMOTOR CONTROL", Vector3(0, 0.23, 0.088), 22, ink, 0.0, 0.00085)
	# Lamps in chrome bezels.
	var names := {"supply": ["SUPPLY", Color(1.0, 0.62, 0.18)], "locked": ["LOCKED OUT", Color(1.0, 0.1, 0.05)], "raise": ["RAISING", Color(0.3, 1.0, 0.35)]}
	var i := 0
	for k in names:
		var x := -0.12 + i * 0.12
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.017
		tm.outer_radius = 0.025
		ring.mesh = tm
		ring.material_override = chrome
		ring.rotation.x = PI / 2
		ring.position = Vector3(x, 0.12, 0.086)
		box.add_child(ring)
		var lens := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.02
		lens.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (names[k][1] as Color) * 0.25
		mat.emission_enabled = true
		mat.emission = names[k][1]
		mat.emission_energy_multiplier = 0.0
		mat.roughness = 0.2
		lens.material_override = mat
		lens.position = Vector3(x, 0.12, 0.088)
		box.add_child(lens)
		UndercroftKit.label(box, names[k][0], Vector3(x, 0.083, 0.087), 13, Color(0.86, 0.84, 0.76), 0.0, 0.00085)
		var glow := OmniLight3D.new()
		glow.light_color = names[k][1]
		glow.omni_range = 0.8
		glow.light_energy = 0.0
		glow.position = Vector3(x, 0.12, 0.2)
		box.add_child(glow)
		_lamps[k] = [mat, glow]
		i += 1
	# The key switch: a chrome bezel, black face, the keyway; OFF and ON
	# either side of it, and who holds the key under it.
	UndercroftKit.bar(box, Vector3(-0.05, -0.04, 0.088), 0.036, 0.016, chrome, "z", 20)
	UndercroftKit.bar(box, Vector3(-0.05, -0.04, 0.097), 0.028, 0.004, black, "z", 20)
	RoomBuilder._box(box, Vector3(-0.05, -0.04, 0.1), Vector3(0.006, 0.026, 0.002), Mats.trim(Color(0.0, 0.0, 0.0), 0.9), false)
	UndercroftKit.label(box, "OFF", Vector3(-0.1, 0.0, 0.087), 13, Color(0.86, 0.84, 0.76), 0.0, 0.00085)
	UndercroftKit.label(box, "ON", Vector3(-0.005, -0.04, 0.087), 13, Color(0.86, 0.84, 0.76), 0.0, 0.00085)
	RoomBuilder._box(box, Vector3(-0.05, -0.105, 0.085), Vector3(0.15, 0.03, 0.003), Mats.trim(Color(0.6, 0.1, 0.06), 0.5), false)
	UndercroftKit.label(box, "WARDEN'S KEY ONLY", Vector3(-0.05, -0.105, 0.088), 11, Color(0.92, 0.88, 0.78), 0.0, 0.00085)
	# The Warden's key, once it's in: an iron bow and its brass tag.
	_key_turn = Node3D.new()
	_key_turn.position = Vector3(-0.05, -0.04, 0.1)
	box.add_child(_key_turn)
	_key_vis = Node3D.new()
	_key_turn.add_child(_key_vis)
	var iron := Mats.trim(Color(0.16, 0.15, 0.14), 0.35, 0.85)
	UndercroftKit.bar(_key_vis, Vector3(0, 0, 0.012), 0.006, 0.024, iron, "z", 8)
	var bow := MeshInstance3D.new()
	var bt := TorusMesh.new()
	bt.inner_radius = 0.011
	bt.outer_radius = 0.019
	bow.mesh = bt
	bow.material_override = iron
	bow.rotation.z = PI / 2
	bow.position = Vector3(0, 0, 0.04)
	_key_vis.add_child(bow)
	var tag := Node3D.new()
	tag.position = Vector3(0, -0.04, 0.045)
	_key_vis.add_child(tag)
	RoomBuilder._box(tag, Vector3.ZERO, Vector3(0.03, 0.045, 0.003), Mats.trim(Color(0.62, 0.47, 0.22), 0.35, 0.85), false)
	_key_vis.visible = false
	# Push buttons: black RAISE, red mushroom STOP.
	for b in [[0.09, -0.04, Color(0.04, 0.04, 0.04), "RAISE"], [0.09, -0.17, Color(0.6, 0.05, 0.03), "STOP"]]:
		UndercroftKit.bar(box, Vector3(b[0], b[1], 0.087), 0.024, 0.012, chrome, "z", 16)
		UndercroftKit.bar(box, Vector3(b[0], b[1], 0.1), 0.02 if b[3] == "RAISE" else 0.03, 0.02, Mats.trim(b[2], 0.4, 0.1), "z", 16)
		UndercroftKit.label(box, b[3], Vector3(b[0], b[1] - 0.045, 0.087), 12, Color(0.86, 0.84, 0.76), 0.0, 0.00085)
	# Conduit down the wall into the floor, and a gland on top up to the
	# motor.
	UndercroftKit.bar(box, Vector3(0.12, -0.31 - 0.47, -0.02), 0.018, 0.94, steel, "y", 10)
	UndercroftKit.bar(box, Vector3(-0.12, 0.31 + 0.6, -0.02), 0.014, 1.2, steel, "y", 10)
	UndercroftKit.bar(box, Vector3(0.12, -0.32, -0.02), 0.026, 0.03, chrome, "y", 10)

func _stripe_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var on := ((x + y) / 8) % 2 == 0
			img.set_pixel(x, y, Color(0.78, 0.6, 0.08) if on else Color(0.05, 0.05, 0.04))
	return ImageTexture.create_from_image(img)

func interact_text(player: Node, handle := -1) -> String:
	if GameState.has_flag(FLAG) or _spinning:
		return ""
	if handle == 1 and needs_key() and not key_in() and _has_key(player):
		return "Turn the Warden's key"
	if handle == 1:
		return "Check the control box"
	return "Check the flood door"

func interact(player: Node, handle := -1) -> void:
	if GameState.has_flag(FLAG) or _spinning:
		return
	if handle == 1 and needs_key() and not key_in() and _has_key(player):
		_rpc_key_request.rpc_id(1, player.peer_id)
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if not _powered:
		if needs_key() and not key_in():
			hud.toast("Dead. The motor needs power from the generator, and its control box is locked: WARDEN'S KEY ONLY.")
		else:
			hud.toast("Dead. The motor needs power from the generator.")
	else:
		hud.toast("The motor has power, but the control box is LOCKED OUT. The key switch needs the Warden's key.")

func _has_key(player: Node) -> bool:
	return Cheats.on("unlock_doors") or player.inventory.key_items.has(KEY)

@rpc("any_peer", "reliable", "call_local")
func _rpc_key_request(by_peer: int) -> void:
	if multiplayer.is_server() and not key_in():
		_rpc_key.rpc(by_peer)

## Every phone: the key goes in and turns to ON; with power on, the door
## goes up.
@rpc("authority", "reliable", "call_local")
func _rpc_key(_by_peer: int) -> void:
	GameState.set_flag(KEY_FLAG)
	# Keys belong to both survivors (Pickup "party"): turned in the switch,
	# it goes from both bags, each phone taking it from its own survivor's.
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			p.inventory.remove_key(KEY)
	_key_vis.visible = true
	_key_turn.rotation.z = 0.0
	Sfx.play_at("key_switch", global_transform * BOX, "breaker_throw", 0.0, 5.0)
	var t := create_tween()
	t.tween_interval(0.35)
	t.tween_property(_key_turn, "rotation:z", -PI / 2, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_lamp(false)
	get_tree().call_group("story", "flood_key_turned", _powered)
	if _powered and not GameState.has_flag(FLAG):
		GameState.set_flag(FLAG)
		await get_tree().create_timer(0.8).timeout
		_open()

## UndercroftPower: the generator came on (or is on when the level loads).
func set_powered(on: bool, animate: bool) -> void:
	_powered = on
	if not on or GameState.has_flag(FLAG):
		_lamp(GameState.has_flag(FLAG))
		return
	if needs_key() and not key_in():
		# Live, but locked out until the Warden's key turns.
		_lamp(false)
		if animate:
			Sfx.play_at("breaker_throw", global_transform * BOX, "", -6.0, 5.0)
		return
	GameState.set_flag(FLAG)
	if not animate:
		_slab.position.y = H - 0.35
		_lamp(true)
		return
	_open()

func _open() -> void:
	_spinning = true
	_lamp(true)
	await get_tree().create_timer(1.5).timeout
	_klaxon = Sfx.loop_on("flood_alarm", _beacon, 2.0, 16.0)
	await get_tree().create_timer(2.0).timeout
	Sfx.play_at("flood_door_grind", global_transform * Vector3(0, H, 0.4), "metal_bang", 4.0, 14.0)
	var t := create_tween()
	t.tween_property(_slab, "position:y", H - 0.35, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	Sfx.play_at("metal_bang", global_transform * Vector3(0, H, 0.4), "", 2.0, 12.0)
	if _klaxon:
		var f := create_tween()
		f.tween_property(_klaxon, "volume_db", -40.0, 2.0)
		f.tween_callback(_klaxon.queue_free)
	_spinning = false

## The beacon and the RAISING lamp (on: rising or up); the box's other two
## lamps follow the power and the key.
func _lamp(on: bool) -> void:
	_beacon_mat.emission_energy_multiplier = 2.0 if on else 0.0
	var states := {
		"supply": _powered or GameState.has_flag(FLAG),
		"locked": _powered and needs_key() and not key_in() and not GameState.has_flag(FLAG),
		"raise": on,
	}
	for k in _lamps:
		var mat: StandardMaterial3D = _lamps[k][0]
		var glow: OmniLight3D = _lamps[k][1]
		mat.emission_energy_multiplier = 3.0 if states[k] else 0.0
		glow.light_energy = 0.35 if states[k] else 0.0

func _process(delta: float) -> void:
	if _spinning:
		_beacon.rotate_y(delta * 5.0)
		_beacon_light.light_energy = 3.0
	elif _beacon_light.light_energy > 0.0:
		_beacon_light.light_energy = move_toward(_beacon_light.light_energy, 0.0, delta * 2.0)
