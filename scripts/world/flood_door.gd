class_name FloodDoor
extends Node3D
## The flood door between the engine hall and the deep stacks (chapter 2): a
## riveted steel slab in a channel frame that rises on a motor. Dead until
## the generator runs; then the klaxon sounds, the beacon over it turns, and
## it grinds up into the wall. The flag keeps it open after a load.
##
## Placed in a doorway: local +z points into the room it's seen from (the
## engine hall), the origin is on the floor at the middle of the opening.

const W := 4.0
const H := 3.2
const FLAG := "c2_flood_open"
const TOP := 6.1   # the guides run this high (the engine hall's vault)

var _slab: Node3D
var _beacon: Node3D
var _beacon_light: SpotLight3D
var _beacon_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D
var _klaxon: AudioStreamPlayer3D
var _spinning := false

func _ready() -> void:
	add_to_group("undercroft_power")
	_build()
	if GameState.has_flag(FLAG):
		_slab.position.y = H - 0.35
		_lamp(true)

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
	# The motor's push-button box beside it, its panel lamp dead.
	var box := Node3D.new()
	box.position = Vector3(-W / 2 - 0.55, 1.2, 0.18)
	add_child(box)
	RoomBuilder._box(box, Vector3.ZERO, Vector3(0.3, 0.42, 0.16), Mats.trim(Color(0.2, 0.24, 0.2), 0.6, 0.4), false)
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.albedo_color = Color(0.2, 0.05, 0.03)
	_panel_mat.emission_enabled = true
	_panel_mat.emission = Color(0.2, 1.0, 0.3)
	_panel_mat.emission_energy_multiplier = 0.0
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.028
	lamp.mesh = sm
	lamp.material_override = _panel_mat
	lamp.position = Vector3(0, 0.12, 0.085)
	box.add_child(lamp)
	RoomBuilder._box(box, Vector3(0, -0.04, 0.085), Vector3(0.07, 0.07, 0.02), Mats.trim(Color(0.6, 0.06, 0.04), 0.4), false)
	UndercroftKit.label(box, "RAISE", Vector3(0, -0.13, 0.082), 18, Color(0.8, 0.78, 0.7))
	UndercroftKit.reach(self, self, Vector3(0, 1.2, 0.6), Vector3(W, 2.0, 0.8))

func _stripe_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var on := ((x + y) / 8) % 2 == 0
			img.set_pixel(x, y, Color(0.78, 0.6, 0.08) if on else Color(0.05, 0.05, 0.04))
	return ImageTexture.create_from_image(img)

func interact_text(_player: Node, _handle := -1) -> String:
	return "" if GameState.has_flag(FLAG) or _spinning else "Check the flood door"

func interact(_player: Node, _handle := -1) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and not GameState.has_flag(FLAG):
		hud.toast("Dead. The motor needs power from the generator.")

## UndercroftPower: the generator came on.
func set_powered(on: bool, animate: bool) -> void:
	if not on or GameState.has_flag(FLAG):
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

func _lamp(on: bool) -> void:
	_panel_mat.emission_energy_multiplier = 2.5 if on else 0.0
	_beacon_mat.emission_energy_multiplier = 2.0 if on else 0.0

func _process(delta: float) -> void:
	if _spinning:
		_beacon.rotate_y(delta * 5.0)
		_beacon_light.light_energy = 3.0
	elif _beacon_light.light_energy > 0.0:
		_beacon_light.light_energy = move_toward(_beacon_light.light_energy, 0.0, delta * 2.0)
