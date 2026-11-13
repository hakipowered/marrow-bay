class_name Undercroft
extends LevelBase
## Chapter 2, "The Count": the Undercroft, the Archive's old service level
## two floors under the vault, where the vault elevator stops. Brick
## tunnels from 1902, the keeper's lodge, the survey room, the clock gallery
## that ran every clock in the building, the shelter staff's muster room,
## the engine hall with its dead diesel generator and the flood door, and a
## sunken coal yard open to the rain. Original setting (docs/chapter2.md).
##
## World layout (x east, z south), each room's pos is its north-west floor
## corner:
##   LiftPit        (0, 0, 0)    7 x 6       the lift arrives in its west wall
##   ServiceCorridor (7, 0, 1.5) 32 x 3      the spine, west to east
##   KeepersLodge   (8, 0, 4.5)  7 x 6       safe room, south of the corridor
##   SurveyRoom     (9, 0, -9.5) 12 x 11     the 1891 map, the clock key
##   ClockGallery   (21, 0, -9.5) 14 x 11    the master clock (the fuse)
##   BackStair      (31.5, 0, -12.5) 3 x 3   caved in: the Tallyman's way in
##   MusterRoom     (19, 0, 4.5) 14 x 10     barred; the Warden's arena
##   EngineHall     (39, 0, -6)  16 x 18     the generator, the flood door
##   CoalYard       (55, 0, -6)  22 x 18     outdoors: the diesel in the shed
##   DeepStacks     (43, 0, 12)  8 x 8       behind the flood door: the end

const WARM := Color(1.0, 0.72, 0.42)
const FIRE := Color(1.0, 0.45, 0.15)
const COLD := Color(0.62, 0.75, 1.0)
## The moon only lights the coal yard (the tunnels have ceilings, but a
## shadow map that far out would still leak it in): it and the yard's
## surfaces share this render layer.
const YARD_LAYER := 1 << 3

## Story marks (Chapter2Story reads these).
const GENERATOR_AT := Vector3(47.5, 0.0, -1.0)
const FLOOD_AT := Vector3(46.0, 0.0, 12.0)
const CLOCK_AT := Vector3(24.5, 0.0, -9.375)
const MUSTER_DOOR := Vector3(26.1, 0.0, 4.625)
const WARDEN_SEAT := Vector3(26.0, 0.0, 13.25)
## Where he stands up to, clear of his bench (sat on it, he is inside its
## collider and can neither move nor be shot in the legs).
const WARDEN_STAND := Vector3(26.0, 0.0, 12.25)
const PA_HORN := Vector3(39.35, 4.6, -1.6)
const STAIR_DOOR := Vector3(32.9, 0.0, -9.5)
const TALLY_IN := Vector3(33.0, 0.0, -11.4)
const LANYARD_AT := Vector3(46.4, 0.0, 16.6)
const CHALK_AT := Vector3(51.0 - RoomBuilder.WALL_T / 2.0, 1.6, 17.0)
const CHALK_FONT := preload("res://assets/fonts/RockSalt.ttf")

## Where the generator's noise brings infected in from, all out of the
## hall's sight: the yard behind the coal heap and the shed, the far end of
## the service tunnel, and down the coal chute (dropping inside its shaft).
const WAVE_ENTRIES := [
	{"pos": Vector3(74.5, 0.0, -4.4), "mode": ""},
	{"pos": Vector3(75.5, 0.0, 9.5), "mode": ""},
	{"pos": Vector3(61.5, 0.0, 10.6), "mode": ""},
	{"pos": Vector3(22.0, 0.0, 3.0), "mode": ""},
	{"pos": Vector3(13.5, 0.0, 2.6), "mode": ""},
	{"pos": Vector3(53.6, 5.2, -4.4), "mode": "drop"},
]

var _moon: DirectionalLight3D

func build() -> void:
	_environment()
	_lift_pit()
	_service_corridor()
	_keepers_lodge()
	_survey_room()
	_clock_gallery()
	_back_stair()
	_muster_room()
	_engine_hall()
	_coal_yard()
	_deep_stacks()
	_horror_beats()
	var power := UndercroftPower.new()
	power.name = "UndercroftPower"
	power.position = GENERATOR_AT + Vector3(0, 2.0, 0)
	add_child(power)
	var story := Chapter2Story.new()
	story.name = "Story"
	add_child(story)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.015, 0.02, 0.03)
	ps.sky_horizon_color = Color(0.14, 0.07, 0.05)   # the city burning above
	ps.ground_bottom_color = Color(0.01, 0.01, 0.01)
	ps.ground_horizon_color = Color(0.1, 0.06, 0.05)
	sky.sky_material = ps
	env.sky = sky
	# Darker and colder than the Archive: the battery lamps and the
	# flashlights do the work until the generator runs.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.29, 0.38)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.075, 0.085)
	env.fog_density = 0.024
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = COLD
	_moon.light_energy = 0.4
	_moon.rotation_degrees = Vector3(-62, 35, 0)
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 40.0
	_moon.light_cull_mask = YARD_LAYER
	add_child(_moon)

# ------------------------------------------------------------------ helpers

static func _steel(shade := 0.22, rough := 0.55) -> StandardMaterial3D:
	return Mats.trim(Color(shade, shade * 0.97, shade * 0.93), rough, 0.75)

## A pipe run along x or z with a bracket every 1.6 m.
func _pipe(parent: Node3D, from: Vector3, length: float, axis: String, radius: float, mat: Material) -> void:
	var dir := Vector3.RIGHT if axis == "x" else Vector3.BACK
	UndercroftKit.bar(parent, from + dir * length / 2.0, radius, length, mat, axis, 14)
	var bracket := _steel(0.12)
	var n := int(length / 1.6)
	for i in range(n + 1):
		var at := from + dir * (0.3 + i * 1.6)
		if (at - from).length() > length:
			break
		UndercroftKit.bar(parent, at, radius + 0.02, 0.06, bracket, axis, 14)

## Stencilled letters on a wall, facing local +z turned by `rot` (degrees).
func _stencil(parent: Node3D, text: String, at: Vector3, rot: float, size := 40, col := Color(0.82, 0.78, 0.66), pixel := 0.0022) -> Label3D:
	return UndercroftKit.label(parent, text, at, size, col, deg_to_rad(rot), pixel)

## A picture on a wall: a textured quad in a dark frame, facing local +z
## turned by `rot` (degrees).
func _picture(parent: Node3D, tex_path: String, at: Vector3, size: Vector2, rot: float, frame := Color(0.18, 0.11, 0.06)) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation_degrees.y = rot
	parent.add_child(n)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex_path)
	m.roughness = 0.8
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	q.material_override = m
	q.position.z = 0.025
	n.add_child(q)
	var fm := Mats.trim(frame, 0.6)
	for y in [-1.0, 1.0]:
		RoomBuilder._box(n, Vector3(0, y * (size.y / 2 + 0.03), 0.02), Vector3(size.x + 0.12, 0.06, 0.04), fm, false)
	for x in [-1.0, 1.0]:
		RoomBuilder._box(n, Vector3(x * (size.x / 2 + 0.03), 0, 0.02), Vector3(0.06, size.y, 0.04), fm, false)
	return n

## Every visual under `n` also on the yard's moonlit layer.
static func _moonlit(n: Node) -> void:
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		if vi is GeometryInstance3D:
			vi.layers |= YARD_LAYER

## An invisible wall (a gate the model has no collision for).
func _wall_collider(parent: Node3D, center: Vector3, ext: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = ext
	cs.shape = bs
	sb.add_child(cs)
	sb.position = center
	parent.add_child(sb)

## A solid box with collision, outside any room (rubble, plinths, columns).
## A lamp prop whose own light sits inside it: it mustn't throw its arm or
## cage across the ceiling as a giant black shape.
static func _unshadowed(n: Node) -> Node:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_unshadowed(c)
	return n

## Chalk on a wall, in a scrawled hand.
func _chalk(parent: Node3D, text: String, at: Vector3, rot: float, size: int, pixel: float, col := Color(0.88, 0.88, 0.84)) -> Label3D:
	var l := _stencil(parent, text, at, rot, size, col, pixel)
	l.font = CHALK_FONT
	return l

func _block(parent: Node3D, center: Vector3, ext: Vector3, mat: Material) -> void:
	RoomBuilder._box(parent, center, ext, mat, true)

# ------------------------------------------------------------------ the lift pit

func _lift_pit() -> void:
	var r := RoomBuilder.build(self, {
		"id": "LiftPit", "pos": Vector3(0, 0, 0), "size": Vector3(7, 4.6, 6),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor", "trim": Color(0.16, 0.15, 0.14),
		"floor_look": {"tile_size": 2.0, "wetness": 0.4, "puddles": 0.4, "grime_amount": 0.7},
		"wall_look": {"tile_size": 2.4, "grime_amount": 0.8, "grime_height": 1.6, "stain_amount": 0.6},
		"ceiling_look": {"tint": Color(0.45, 0.44, 0.42)},
		"openings": {"w": [[2.2, VaultElevator.DOOR_W, VaultElevator.DOOR_H, {"frame": false}]], "e": [[2.3, 1.4, 2.5]]},
		"decals": {"blood": 1, "stain": 3, "wall_blood": 1},
		"papers": 6,
		"probe": true,
	})
	var lift := VaultElevator.new()
	lift.name = "VaultElevator"
	lift.arrived = true
	lift.position = Vector3(0, 0, 3)
	lift.rotation_degrees.y = 90.0
	add_child(lift)
	_stencil(r, "B2", Vector3(5.4, 3.3, 0.14), 0, 220, Color(0.85, 0.8, 0.6), 0.0026)
	_stencil(r, "UNDERCROFT  SERVICE  LEVEL\nNO  UNACCOMPANIED  ENTRY", Vector3(5.4, 2.55, 0.14), 0, 34)
	_stencil(r, "ENGINE HALL  ->", Vector3(6.86, 2.75, 4.6), -90, 30)
	var pipe := _steel(0.2, 0.5)
	_pipe(r, Vector3(0.2, 4.25, 0.36), 6.6, "x", 0.09, pipe)
	_pipe(r, Vector3(0.2, 4.1, 0.66), 6.6, "x", 0.05, Mats.trim(Color(0.32, 0.12, 0.08), 0.6, 0.4))
	_pipe(r, Vector3(6.6, 4.3, 0.2), 5.6, "z", 0.06, pipe)
	RoomBuilder.prop(r, "painted_wooden_bench", Vector3(4.4, 0, 0.5), 0)
	RoomBuilder.prop(r, "korean_fire_extinguisher_01", Vector3(6.7, 0, 0.45), -90)
	RoomBuilder.prop(r, "hand_truck", Vector3(5.9, 0, 5.4), 200)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(4.9, 0, 5.5), 15)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(4.95, 0.34, 5.45), 70, 1.0, false)
	RoomBuilder.prop(r, "WetFloorSign_01", Vector3(2.6, 0, 1.2), 30)
	RoomBuilder.prop(r, "fire_alarm", Vector3(1.4, 1.5, 0.14), 0, 1.0, false)
	RoomBuilder.prop(r, "security_camera_01", Vector3(6.75, 3.9, 0.3), -135, 1.0, false)
	UndercroftPower.emergency_light(r, Vector3(2.4, 3.2, 0.13), 0.0, 0.55, 6.0)
	UndercroftPower.emergency_light(r, Vector3(6.87, 3.0, 1.4), -90.0, 0.4, 5.0)
	UndercroftPower.work_light(r, Vector3(3.5, 4.55, 3.0), 0.0, 0.7, 7.0)
	# They arrive in the car (its battery lamp, then the doors open on this).
	place_checkpoint("ch2_lift", Vector3(-1.4, 0, 3.0), Vector3(2.4, 3, 3))
	place_pickup("ammo:9mm", Vector3(4.45, 0.47, 0.5), "c2_lift_ammo")

# ------------------------------------------------------------------ the service corridor

func _service_corridor() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ServiceCorridor", "pos": Vector3(7, 0, 1.5), "size": Vector3(32, 3.4, 3),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor", "trim": Color(0.16, 0.15, 0.14),
		"floor_look": {"tile_size": 2.0, "wetness": 0.6, "puddles": 0.6, "grime_amount": 0.8},
		"wall_look": {"tile_size": 2.2, "grime_amount": 0.9, "grime_height": 1.5, "stain_amount": 0.8, "wall_wet": 0.5},
		"ceiling_look": {"tint": Color(0.4, 0.39, 0.37)},
		"look": {"variation": 0.35},
		# North: the survey room and the clock gallery; south: the keeper's
		# lodge and the muster room. Each of those insets its own wall and
		# frames the doorway through both.
		"openings": {
			"n": [[4.4, 1.2, 2.3, {"frame": false}], [23.4, 1.4, 2.4, {"frame": false}]],
			"s": [[3.4, 1.2, 2.3, {"frame": false}], [18.4, 1.4, 2.4, {"frame": false}]],
		},
		"skip_walls": ["w", "e"],
		"pilasters": {"sides": ["n", "s"], "spacing": 3.6, "width": 0.42, "depth": 0.12, "slot": "undercroft_brick", "cap": Color(0.24, 0.22, 0.2)},
		"beams": {"axis": "z", "spacing": 3.6, "depth": 0.28, "width": 0.42, "slot": "undercroft_brick"},
		# Caved in over the muster room door (the "c2_corridor_drop" scare).
		"ceiling_holes": [[21.4, 0.5, 1.1, 1.1]],
		"decals": {"blood": 4, "stain": 6, "wall_blood": 3},
		"papers": 10,
	})
	var pipe := _steel(0.2, 0.5)
	var rust := Mats.trim(Color(0.3, 0.13, 0.07), 0.7, 0.4)
	_pipe(r, Vector3(0.1, 2.98, 0.34), 31.8, "x", 0.1, pipe)
	_pipe(r, Vector3(0.1, 2.8, 0.36), 31.8, "x", 0.055, rust)
	_pipe(r, Vector3(0.1, 2.95, 2.64), 31.8, "x", 0.07, pipe)
	# Cable tray along the south side.
	RoomBuilder._box(r, Vector3(16, 3.12, 2.42), Vector3(31.8, 0.03, 0.3), _steel(0.15), false)
	for i in 6:
		RoomBuilder.prop(r, "modular_electric_cables", Vector3(2.5 + i * 5.2, 3.0, 2.86), 180, 1.0, false)
	# Signs over the doorways.
	var paint := Color(0.86, 0.82, 0.7)
	_stencil(r, "SURVEY ROOM", Vector3(5.0, 2.6, 0.15), 0, 30, paint)
	_stencil(r, "CLOCK GALLERY", Vector3(24.1, 2.7, 0.15), 0, 30, paint)
	_stencil(r, "KEEPER", Vector3(4.0, 2.6, 2.85), 180, 30, paint)
	_stencil(r, "MUSTER ROOM  -  SHELTER STAFF", Vector3(19.1, 2.7, 2.85), 180, 26, paint)
	_stencil(r, "<-  LIFT", Vector3(9.5, 1.9, 0.15), 0, 30, paint)
	_stencil(r, "ENGINE HALL  ->", Vector3(14.5, 1.9, 0.15), 0, 30, paint)
	_stencil(r, "ENGINE HALL  ->", Vector3(28.6, 1.9, 2.85), 180, 30, paint)
	# Things left behind in the dark.
	RoomBuilder.prop(r, "wheelchair_01", Vector3(11.8, 0, 2.3), 140)
	RoomBuilder.prop(r, "industrial_storage_cart", Vector3(27.2, 0, 0.75), 4)
	RoomBuilder.prop(r, "wooden_crate_02", Vector3(30.8, 0, 2.3), 90)
	RoomBuilder.prop(r, "wooden_crate_01", Vector3(30.8, 0.46, 2.3), 80, 1.0, false)
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_rust", Vector3(15.6, 0, 0.45), 0)
	RoomBuilder.prop(r, "korean_fire_extinguisher_01", Vector3(21.4, 0, 0.45), 0)
	RoomBuilder.prop(r, "vintage_suitcase", Vector3(7.6, 0, 2.55), 100, 1.0, false)
	RoomBuilder.prop(r, "trashbag", Vector3(26.0, 0, 2.65), 20, 1.0, false)
	var cdrum := Breakable.make(r, "fuel_drum", Vector3(13.3, 0, 0.5), 20.0, "c2_corridor_drum")
	cdrum.name = "CorridorDrum"
	var crate := Breakable.make(r, "wood", Vector3(29.2, 0, 2.55), 10.0, "c2_corridor_crate", "wooden_crate_01")
	crate.drop_table = "crate"
	for x in [5.5, 15.0, 25.5]:
		UndercroftPower.emergency_light(r, Vector3(x, 2.5, 2.86), 180.0, 0.45, 5.5)
	UndercroftPower.emergency_light(r, Vector3(10.6, 2.5, 0.14), 0.0, 0.35, 5.0)
	for x in [3.0, 9.0, 15.0, 21.0, 27.0]:
		UndercroftPower.work_light(r, Vector3(x, 3.36, 1.5), 90.0, 0.55, 6.0, x == 21.0)
	place_zombie("Z_c2_corr1", Vector3(17.5, 0, 2.6), 90, "shambler", false, "mechanic")
	place_zombie("Z_c2_corr_crawl", Vector3(24.0, 0, 3.7), 60, "crawler", false, "cop")
	place_zombie("Z_c2_corr2", Vector3(34.5, 0, 2.1), 100, "shambler", true, "cook")
	place_pickup("herb_green", Vector3(37.9, 0.1, 4.05), "c2_corr_herb")

# ------------------------------------------------------------------ the keeper's lodge (safe room)

func _keepers_lodge() -> void:
	var r := RoomBuilder.build(self, {
		"id": "KeepersLodge", "pos": Vector3(8, 0, 4.5), "size": Vector3(7, 3, 6),
		"floor": "wood_floor_old", "wall": "lodge_wall", "wainscot": "plank_painted", "wainscot_height": 0.95,
		"trim": Color(0.3, 0.18, 0.1),
		"floor_look": {"tile_size": 1.6, "grime_amount": 0.4},
		"wall_look": {"tile_size": 2.0, "tint": Color(0.9, 0.82, 0.68), "stain_amount": 0.4},
		"look": {"grime_amount": 0.3},
		"openings": {"n": [[2.4, 1.2, 2.3]]},
		"wall_inset": {"n": RoomBuilder.WALL_T},   # back to back with the corridor's south wall
		"papers": 3,
	})
	place_door(Vector3(11.0, 0, 4.5 + RoomBuilder.WALL_T / 2.0), 0, Door.Kind.MANUAL, "wood_panel", 1.2, 2.3, "lodge_door")
	# Orrin Vell's lodge: thirty-one years of nights. The cot, the kettle,
	# the radio, his chair, and the visitors' ledger on the desk.
	RoomBuilder.prop(r, "vintage_day_bed", Vector3(6.4, 0, 3.2), -90)
	RoomBuilder.prop(r, "metal_office_desk", Vector3(0.62, 0, 4.4), 90)
	RoomBuilder.prop(r, "vintage_radio_transceiver", Vector3(0.55, 0.79, 5.1), 90, 1.0, false)
	_unshadowed(RoomBuilder.prop(r, "desk_lamp_arm_01", Vector3(0.45, 0.79, 3.7), 70, 1.0, false))
	RoomBuilder.prop(r, "binder_notebook", Vector3(0.7, 0.79, 4.35), 95, 1.0, false)
	RoomBuilder.prop(r, "WoodenChair_01", Vector3(1.45, 0, 4.4), -90)
	RoomBuilder.prop(r, "ArmChair_01", Vector3(3.0, 0, 3.6), 200)
	RoomBuilder.prop(r, "wooden_bookshelf_worn", Vector3(3.6, 0, 5.62), 180)
	RoomBuilder.prop(r, "side_table_01", Vector3(6.3, 0, 0.95), 0)
	RoomBuilder.prop(r, "vintage_electric_kettle", Vector3(6.25, 0.55, 0.9), 40, 1.0, false)
	_unshadowed(RoomBuilder.prop(r, "vintage_oil_lamp", Vector3(6.45, 0.55, 1.1), 0, 1.0, false))
	RoomBuilder.prop(r, "vintage_telephone_wall_clock", Vector3(5.0, 1.9, 0.4), 0, 1.0, false)
	RoomBuilder.prop(r, "hanging_picture_frame_02", Vector3(0.14, 1.9, 2.0), 90, 1.0, false)
	RoomBuilder.prop(r, "old_gas_mask", Vector3(6.85, 2.05, 5.2), -90, 1.0, false)
	RoomBuilder.prop(r, "vintage_flashlight", Vector3(3.3, 1.07, 5.55), 30, 1.0, false)
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_handle", Vector3(1.6, 0, 0.75), 0)
	# A keeper's lamps: still burning low on their oil.
	var lamp := RoomBuilder.light(r, Vector3(0.6, 1.25, 3.75), WARM, 1.1, 5.0, true)
	lamp.name = "DeskLamp"
	RoomBuilder.light(r, Vector3(6.45, 1.2, 1.1), Color(1.0, 0.62, 0.3), 0.8, 4.0, false, true)
	UndercroftPower.work_light(r, Vector3(3.5, 2.96, 3.0), 0.0, 0.5, 6.0)
	place_checkpoint("ch2_lodge", Vector3(11.5, 0, 7.6), Vector3(6.2, 3, 5.2), true)
	place_pickup("file:keeper_ledger", Vector3(8.75, 0.8, 8.6), "c2_ledger")
	place_pickup("ink_ribbon", Vector3(8.7, 0.8, 9.6), "c2_lodge_ribbon")
	place_pickup("herb_green", Vector3(11.0, 1.15, 10.1), "c2_lodge_herb")
	place_pickup("ammo:shells", Vector3(14.3, 0.56, 5.35), "c2_lodge_shells")

# ------------------------------------------------------------------ the survey room

func _survey_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "SurveyRoom", "pos": Vector3(9, 0, -9.5), "size": Vector3(12, 4, 11),
		"floor": "map_room_floor", "wall": "map_room_wall", "trim": Color(0.25, 0.16, 0.09),
		"floor_look": {"tile_size": 1.6, "grime_amount": 0.5, "stain_amount": 0.4},
		"wall_look": {"tile_size": 2.2, "stain_amount": 0.6},
		"look": {"grime_amount": 0.45},
		"openings": {"s": [[2.4, 1.2, 2.3]]},
		"skip_walls": ["e"],   # the clock gallery's west wall
		"wall_inset": {"s": RoomBuilder.WALL_T},
		"beams": {"axis": "x", "spacing": 3.0, "depth": 0.3, "width": 0.26, "slot": "plank_painted"},
		"decals": {"blood": 2, "stain": 3, "wall_blood": 1},
		"papers": 26,
		"probe": true,
	})
	place_door(Vector3(12.0, 0, 1.5 - RoomBuilder.WALL_T / 2.0), 0, Door.Kind.MANUAL, "wood_panel", 1.2, 2.3, "survey_door")
	# The 1891 survey of the river district on the north wall: the walled
	# street, the burial ground, the line of the Deep Tunnel inked in later.
	_picture(r, "res://assets/textures/undercroft/survey_map_1891.jpg", Vector3(6.0, 2.15, 0.13), Vector2(3.9, 2.6), 0.0)
	_stencil(r, "CITY  SURVEY  OFFICE   -   RIVER  DISTRICT   1891", Vector3(6.0, 3.7, 0.13), 0, 30, Color(0.86, 0.8, 0.62))
	# The keeper's tally on the west wall: hundreds of marks, in fives,
	# scratched into the plaster, and the last ones still fresh.
	var tally := ""
	for row in 7:
		var line := ""
		for g in 9 - (row % 3):
			line += "IIII  "
		tally += line.strip_edges() + "\n"
	var t := _chalk(r, tally, Vector3(0.14, 1.9, 7.6), 90, 34, 0.0025, Color(0.12, 0.1, 0.09))
	t.modulate.a = 0.85
	# The plan chests, the map table, the drawing board.
	RoomBuilder.prop(r, "dining_table", Vector3(6.0, 0, 5.8), 0)
	RoomBuilder.prop(r, "office_notepads", Vector3(5.7, 0.88, 5.8), 8, 1.0, false)
	RoomBuilder.prop(r, "clipboard", Vector3(6.9, 0.88, 5.4), -30, 1.0, false)
	RoomBuilder.prop(r, "binder_notebook", Vector3(5.2, 0.88, 6.2), 60, 1.0, false)
	RoomBuilder.prop(r, "WoodenChair_01", Vector3(4.4, 0, 6.6), 110)
	RoomBuilder.prop(r, "WoodenChair_01", Vector3(7.8, 0, 4.9), -80)
	RoomBuilder.prop(r, "drawer_cabinet", Vector3(0.52, 0, 3.0), 90)
	RoomBuilder.prop(r, "drawer_cabinet", Vector3(0.52, 0, 4.3), 90)
	RoomBuilder.prop(r, "wooden_display_shelves_01", Vector3(0.45, 0, 9.4), 0)
	RoomBuilder.prop(r, "wooden_bookshelf_worn", Vector3(8.6, 0, 10.4), 180)
	RoomBuilder.prop(r, "standing_chalkboard_01", Vector3(10.4, 0, 7.6), -70)
	RoomBuilder.prop(r, "metal_office_desk", Vector3(9.9, 0, 1.0), 180)
	_unshadowed(RoomBuilder.prop(r, "desk_lamp_arm_01", Vector3(10.6, 0.79, 0.85), 200, 1.0, false))
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_rust", Vector3(11.3, 0, 2.2), 0)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(1.4, 0, 10.4), 10)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(1.9, 0, 10.3), 75)
	RoomBuilder.prop(r, "fancy_picture_frame_01", Vector3(11.6, 1.8, 4.0), -90, 1.0, false)
	var lamp := RoomBuilder.light(r, Vector3(10.5, 1.3, 1.1), WARM, 0.9, 5.0, true, true)
	lamp.name = "DeskLamp"
	UndercroftPower.emergency_light(r, Vector3(0.14, 2.9, 6.0), 90.0, 0.4, 6.0)
	for x in [3.0, 9.0]:
		UndercroftPower.work_light(r, Vector3(x, 3.66, 5.5), 0.0, 0.6, 7.0)
	place_pickup("key:clock_key", Vector3(19.3, 0.8, -8.55), "c2_clock_key")
	place_pickup("file:survey_note", Vector3(14.6, 0.89, -3.3), "c2_survey_note")
	place_pickup("ammo:9mm", Vector3(9.6, 1.6, -0.55), "c2_survey_ammo")
	place_zombie("Z_c2_survey1", Vector3(13.0, 0, -2.3), 160, "shambler", true, "office")
	place_zombie("Z_c2_survey2", Vector3(18.4, 0, -4.6), 230, "possum")

# ------------------------------------------------------------------ the clock gallery

func _clock_gallery() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ClockGallery", "pos": Vector3(21, 0, -9.5), "size": Vector3(14, 5, 11),
		"floor": "clock_floor", "wall": "clock_wall", "trim": Color(0.22, 0.14, 0.08),
		"floor_look": {"tile_size": 1.4, "grime_amount": 0.4},
		"wall_look": {"tile_size": 2.4, "stain_amount": 0.4},
		"look": {"grime_amount": 0.4},
		"openings": {"s": [[9.4, 1.4, 2.4]], "w": [[4.5, 1.2, 2.3]], "n": [[11.2, 1.4, 2.4]]},
		"wall_inset": {"s": RoomBuilder.WALL_T},
		"pilasters": {"sides": ["e"], "spacing": 2.6, "width": 0.4, "depth": 0.14, "slot": "plank_painted", "cap": Color(0.3, 0.2, 0.1)},
		"decals": {"blood": 2, "stain": 3},
		"papers": 8,
		"probe": true,
	})
	place_door(Vector3(21.0, 0, -4.4), 90, Door.Kind.MANUAL, "wood_panel", 1.2, 2.3, "gallery_west_door")
	# The master clock against the north wall, the slave dials to its right.
	var clock := MasterClock.new()
	clock.name = "MasterClock"
	clock.position = CLOCK_AT
	add_child(clock)
	# An inspection lamp hung over the clock for whoever kept it wound.
	_unshadowed(RoomBuilder.prop(r, "caged_hanging_light", Vector3(3.5, 4.98, 1.4), 0, 1.0, false))
	var hang := RoomBuilder.light(r, Vector3(3.5, 4.0, 1.5), WARM, 1.3, 6.5, true, true)
	hang.name = "ClockLamp"
	# The east wall: a row of the building's old clocks, all stopped.
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	for i in 9:
		var z := 1.4 + i * 1.0
		var y := rng.randf_range(1.5, 2.6)
		RoomBuilder.prop(r, "wall_clock", Vector3(13.86, y, z), -90, rng.randf_range(0.9, 1.6), false)
	# The clockmaker's bench in the south-east corner.
	RoomBuilder._box(r, Vector3(12.2, 0.45, 9.85), Vector3(2.6, 0.9, 0.75), Mats.surface("plank_painted", {"tile_size": 1.0, "tint": Color(0.45, 0.32, 0.2), "grime_amount": 0.5}), true)
	RoomBuilder.prop(r, "bench_vice_01", Vector3(11.4, 0.9, 9.8), 180, 1.0, false)
	RoomBuilder.prop(r, "metal_toolbox", Vector3(12.6, 0.9, 9.9), 170, 1.0, false)
	RoomBuilder.prop(r, "mantel_clock_01", Vector3(13.1, 0.9, 9.7), 200, 1.0, false)
	RoomBuilder.prop(r, "alarm_clock_01", Vector3(11.9, 0.9, 9.6), 160, 1.0, false)
	_unshadowed(RoomBuilder.prop(r, "desk_lamp_arm_01", Vector3(13.2, 0.9, 10.1), 220, 1.0, false))
	RoomBuilder.prop(r, "wooden_ladder", Vector3(6.4, 0, 0.75), 0)
	RoomBuilder.prop(r, "metal_tool_chest", Vector3(0.6, 0, 9.6), 90)
	RoomBuilder.prop(r, "wooden_display_shelves_01", Vector3(0.45, 0, 2.0), 0)
	RoomBuilder.prop(r, "Rockingchair_01", Vector3(9.2, 0, 4.2), 200)
	_stencil(r, "MASTER  REGULATOR  -  KEEP  WOUND", Vector3(1.2, 3.85, 0.14), 0, 30, Color(0.82, 0.74, 0.5))
	UndercroftPower.emergency_light(r, Vector3(0.14, 3.1, 8.0), 90.0, 0.4, 6.0)
	UndercroftPower.emergency_light(r, Vector3(13.86, 3.2, 6.0), -90.0, 0.35, 6.0)
	for x in [3.5, 10.5]:
		UndercroftPower.work_light(r, Vector3(x, 4.66, 5.5), 0.0, 0.7, 8.0)
	place_zombie("Z_c2_gallery1", Vector3(30.5, 0, -3.0), 200, "shambler", false, "suit")
	place_zombie("Z_c2_gallery_crawl", Vector3(33.0, 0, -1.6), 160, "crawler", false, "office")
	place_pickup("ammo:shells", Vector3(33.6, 0.92, -0.05), "c2_gallery_shells")
	place_pickup("herb_red", Vector3(21.5, 1.05, -7.5), "c2_gallery_red")

# ------------------------------------------------------------------ the back stair

func _back_stair() -> void:
	var r := RoomBuilder.build(self, {
		"id": "BackStair", "pos": Vector3(31.5, 0, -12.5), "size": Vector3(3, 6, 3),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor",
		"floor_look": {"tile_size": 2.0, "grime_amount": 0.9},
		"wall_look": {"tile_size": 2.0, "grime_amount": 0.9, "stain_amount": 0.8},
		"skip_walls": ["s"],
		"decals": {"blood": 1},
	})
	place_door(STAIR_DOOR, 0, Door.Kind.MANUAL, "steel", 1.4, 2.4, "stair_door")
	# The stair up to the vault level, caved in a few steps up: whatever
	# comes down here comes over the rubble.
	var stone := Mats.surface("undercroft_floor", {"tile_size": 1.0, "grime_amount": 0.9})
	for i in 5:
		_block(r, Vector3(1.5, 0.09 + i * 0.18, 1.0 - i * 0.18), Vector3(2.4, 0.18, 0.3 + i * 0.36), stone)
	var rubble := Mats.surface("undercroft_brick", {"tile_size": 0.8, "grime_amount": 1.0})
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in 9:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(0.4, 1.0), rng.randf_range(0.25, 0.6), rng.randf_range(0.3, 0.7))
		mi.mesh = bm
		mi.material_override = rubble
		mi.position = Vector3(rng.randf_range(0.5, 2.5), 1.1 + rng.randf_range(0.0, 1.4), rng.randf_range(0.2, 0.9))
		mi.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf(), rng.randf_range(-0.6, 0.6))
		r.add_child(mi)
	RoomBuilder.prop(r, "dead_tree_trunk", Vector3(1.5, 1.6, 0.6), 20, 1.0, false)
	UndercroftPower.emergency_light(r, Vector3(2.86, 2.4, 2.0), -90.0, 0.25, 3.5)

# ------------------------------------------------------------------ the muster room (the Warden)

func _muster_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "MusterRoom", "pos": Vector3(19, 0, 4.5), "size": Vector3(14, 3.6, 10),
		"floor": "muster_floor", "wall": "plaster_old", "wainscot": "plaster_old", "wainscot_height": 1.35, "trim": Color(0.2, 0.22, 0.2),
		# Shelter paint: cream over a dado of institutional green.
		"wainscot_look": {"tint": Color(0.42, 0.56, 0.44), "tile_size": 1.6, "grime_amount": 0.7, "grime_height": 0.5},
		"floor_look": {"tile_size": 1.6, "grime_amount": 0.6, "stain_amount": 0.5},
		"wall_look": {"tile_size": 2.2, "grime_amount": 0.6, "grime_height": 1.2},
		"look": {"grime_amount": 0.5},
		"openings": {"n": [[6.4, 1.4, 2.4]]},
		"wall_inset": {"n": RoomBuilder.WALL_T},
		"beams": {"axis": "z", "spacing": 3.5, "depth": 0.32, "width": 0.3, "slot": "undercroft_floor"},
		"decals": {"blood": 3, "stain": 4, "wall_blood": 2},
		"papers": 12,
		"probe": true,
	})
	# Barred from inside: Hardass unbars it over the PA (the intercom scene).
	place_door(MUSTER_DOOR, 0, Door.Kind.LOCKED, "steel", 1.4, 2.4, "muster_door", "barred_from_inside")
	var concrete := Mats.surface("undercroft_floor", {"tile_size": 1.2, "grime_amount": 0.7, "tint": Color(0.7, 0.7, 0.68)})
	for x in [4.2, 9.8]:
		_block(r, Vector3(x, 1.8, 5.0), Vector3(0.6, 3.6, 0.6), concrete)
	# The shelter staff's lockers, benches, the riot kit rack, the drill poster.
	UndercroftKit.meshy(r, "lockers", Vector3(2.6, 0, 0.72), 0.0, 2.2)
	UndercroftKit.meshy(r, "lockers", Vector3(11.2, 0, 0.72), 0.0, 2.2)
	UndercroftKit.meshy(r, "lockers", Vector3(13.45, 0, 3.6), -90.0, 2.2)
	RoomBuilder.prop(r, "painted_wooden_bench", Vector3(2.6, 0, 2.1), 0)
	RoomBuilder.prop(r, "painted_wooden_bench", Vector3(11.2, 0, 2.1), 0)
	RoomBuilder.prop(r, "painted_wooden_bench", Vector3(7.0, 0, 8.75), 0)
	RoomBuilder.prop(r, "worn_metal_rack", Vector3(0.45, 0, 3.4), 90)
	RoomBuilder.prop(r, "Megaphone_01", Vector3(0.45, 1.05, 3.4), 90, 1.0, false)
	RoomBuilder.prop(r, "vintage_flashlight", Vector3(0.45, 1.5, 3.1), 0, 1.0, false)
	_picture(r, "res://assets/textures/undercroft/drill_poster.jpg", Vector3(0.14, 1.65, 6.6), Vector2(1.0, 1.4), 90.0, Color(0.1, 0.1, 0.1))
	_stencil(r, "MUSTER  POINT  B", Vector3(7.0, 3.0, 9.86), 180, 44, Color(0.82, 0.8, 0.7))
	_stencil(r, "STAFF  ONLY", Vector3(13.86, 2.8, 7.4), -90, 30, Color(0.82, 0.8, 0.7))
	RoomBuilder.prop(r, "medical_box", Vector3(13.7, 1.3, 8.6), -90, 1.0, false)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(12.9, 0, 9.4), 25)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(1.0, 0, 9.3), -10)
	Breakable.make(r, "fuel_drum", Vector3(12.6, 0, 6.6), 30.0, "c2_muster_drum")
	Breakable.make(r, "propane", Vector3(1.0, 0, 7.8), 0.0, "c2_muster_propane")
	# Hardass's lantern on the floor by his bench, the only light in here.
	_unshadowed(RoomBuilder.prop(r, "vintage_oil_lamp", Vector3(8.3, 0, 9.1), 0, 1.0, false))
	var lan := RoomBuilder.light(r, Vector3(8.3, 0.75, 9.1), WARM, 1.6, 7.5, true, true)
	lan.name = "Lantern"
	UndercroftPower.emergency_light(r, Vector3(0.14, 2.8, 8.4), 90.0, 0.4, 6.0)
	UndercroftPower.emergency_light(r, Vector3(13.86, 2.8, 2.0), -90.0, 0.3, 5.0)
	for x in [3.5, 10.5]:
		for z in [2.8, 7.4]:
			UndercroftPower.work_light(r, Vector3(x, 3.26, z), 90.0, 0.55, 6.5)
	place_pickup("ammo:shells", Vector3(32.0, 0.1, 5.2), "c2_muster_shells")
	place_pickup("ammo:9mm", Vector3(20.0, 0.1, 13.5), "c2_muster_ammo")
	place_pickup("herb_green", Vector3(31.6, 0.1, 13.6), "c2_muster_herb")

# ------------------------------------------------------------------ the engine hall

func _engine_hall() -> void:
	var r := RoomBuilder.build(self, {
		"id": "EngineHall", "pos": Vector3(39, 0, -6), "size": Vector3(16, 6.5, 18),
		"floor": "engine_floor", "wall": "engine_wall", "ceiling": "undercroft_floor", "trim": Color(0.18, 0.18, 0.17),
		"floor_look": {"tile_size": 2.0, "grime_amount": 0.8, "stain_amount": 0.7, "wetness": 0.3},
		"wall_look": {"tile_size": 2.6, "grime_amount": 0.8, "grime_height": 2.0, "stain_amount": 0.6},
		"ceiling_look": {"tint": Color(0.35, 0.34, 0.33)},
		"openings": {
			"w": [[7.5, 3.0, 3.4]],
			"e": [[8.0, 4.0, 3.4]],
			"s": [[5.0, FloodDoor.W, FloodDoor.H, {"frame": false}]],
		},
		"pilasters": {"sides": ["n", "e", "w"], "spacing": 4.0, "width": 0.36, "depth": 0.3, "slot": "flood_steel", "cap": Color(0.16, 0.16, 0.15)},
		"beams": {"axis": "x", "spacing": 4.0, "depth": 0.5, "width": 0.34, "slot": "flood_steel"},
		"decals": {"blood": 3, "stain": 8, "scorch": 2, "wall_blood": 2},
		"papers": 10,
		"probe": true,
	})
	# The generator on its plinth, crank end west toward the tunnel.
	var gen := GeneratorSet.new()
	gen.name = "GeneratorSet"
	gen.position = GENERATOR_AT
	gen.entries = WAVE_ENTRIES.duplicate(true)
	add_child(gen)
	var door := FloodDoor.new()
	door.name = "FloodDoor"
	door.position = FLOOD_AT
	door.rotation_degrees.y = 180.0
	add_child(door)
	_stencil(r, "ENGINE  HALL", Vector3(4.5, 4.6, 0.32), 0, 70, Color(0.86, 0.82, 0.7), 0.003)
	_stencil(r, "No. 2  STANDBY  SET   -   ROTHWELL  &  SONS   1958", Vector3(8.5, 3.9, 0.32), 0, 30, Color(0.8, 0.76, 0.62))
	# The diesel day tank on the north wall, dry, piped down to the set.
	var tank := Mats.surface("flood_steel", {"tile_size": 1.2, "grime_amount": 0.7, "tint": Color(0.42, 0.44, 0.34)})
	var dark := _steel(0.12)
	UndercroftKit.bar(r, Vector3(9.0, 2.6, 0.95), 0.62, 2.8, tank, "x", 24)
	for x in [7.9, 10.1]:
		RoomBuilder._box(r, Vector3(x, 1.4, 0.95), Vector3(0.12, 2.0, 0.9), dark, true)
	_stencil(r, "DIESEL  DAY  TANK", Vector3(9.0, 2.75, 1.58), 0, 34, Color(0.9, 0.85, 0.3))
	_stencil(r, "EMPTY", Vector3(9.0, 2.4, 1.58), 0, 40, Color(0.85, 0.2, 0.12))
	_pipe(r, Vector3(9.0, 1.95, 0.95), 3.2, "z", 0.035, dark)
	# The switchboard beside it.
	RoomBuilder.prop(r, "utility_box_02", Vector3(12.6, 0, 0.55), 0)
	RoomBuilder.prop(r, "power_box_01", Vector3(13.8, 1.7, 0.32), 0, 1.0, false)
	RoomBuilder.prop(r, "power_box_01", Vector3(14.5, 1.7, 0.32), 0, 1.0, false)
	RoomBuilder.prop(r, "modular_electric_cables", Vector3(13.4, 2.6, 0.3), 0, 1.0, false)
	# The coal chute in the north-east corner: a steel hopper shaft down
	# from the yard's drop, its mouth over a spill of coal. The engine's
	# noise brings infected down it (they come down inside, out of sight).
	var chute := Node3D.new()
	chute.name = "CoalChute"
	chute.position = Vector3(14.6, 0, 1.6)
	r.add_child(chute)
	var plate := Mats.surface("flood_steel", {"tile_size": 1.0, "grime_amount": 0.9, "tint": Color(0.3, 0.28, 0.25)})
	for s in [[Vector3(0, 4.75, -0.72), Vector3(1.5, 3.5, 0.08)], [Vector3(0, 4.75, 0.72), Vector3(1.5, 3.5, 0.08)],
			[Vector3(-0.72, 4.75, 0), Vector3(0.08, 3.5, 1.5)], [Vector3(0.72, 4.75, 0), Vector3(0.08, 3.5, 1.5)]]:
		RoomBuilder._box(chute, s[0], s[1], plate, true)
	RoomBuilder._box(chute, Vector3(0, 3.0, 0), Vector3(1.66, 0.12, 1.66), dark, false)
	_stencil(chute, "COAL  DROP", Vector3(0, 3.5, 0.77), 0, 30, Color(0.85, 0.8, 0.6))
	_coal_heap(chute, Vector3(0, 0, 0.3), Vector3(1.6, 0.35, 1.3), false)
	# A gantry girder across the hall with the chain block that lifted the set.
	RoomBuilder._box(r, Vector3(8.0, 5.7, 7.0), Vector3(15.6, 0.45, 0.3), _steel(0.18), false)
	UndercroftKit.bar(r, Vector3(8.4, 4.6, 7.0), 0.025, 2.0, _steel(0.1), "y")
	RoomBuilder._box(r, Vector3(8.4, 3.55, 7.0), Vector3(0.18, 0.2, 0.12), Mats.trim(Color(0.6, 0.45, 0.08), 0.5, 0.5), false)
	# Workshop clutter.
	RoomBuilder.prop(r, "tool_cart", Vector3(1.2, 0, 1.3), 90)
	RoomBuilder.prop(r, "metal_tool_chest", Vector3(0.55, 0, 3.0), 90)
	RoomBuilder.prop(r, "pipe_wrench", Vector3(1.2, 0.97, 1.0), 0, 1.0, false)
	RoomBuilder.prop(r, "metal_jerrycan", Vector3(3.6, 0, 0.55), 10)
	RoomBuilder.prop(r, "Barrel_01", Vector3(15.3, 0, 16.0), 0)
	RoomBuilder.prop(r, "Barrel_01", Vector3(14.6, 0, 16.6), 40)
	RoomBuilder.prop(r, "hand_truck", Vector3(13.0, 0, 16.9), 160)
	RoomBuilder.prop(r, "old_tyre", Vector3(2.5, 0.08, 16.4), 0, 1.0, false)
	RoomBuilder.prop(r, "sledgehammer_01", Vector3(0.4, 0.8, 15.0), 90, 1.0, false)
	Breakable.make(r, "fuel_drum", Vector3(14.9, 0, 14.4), 0.0, "c2_hall_drum_1")
	Breakable.make(r, "fuel_drum", Vector3(1.0, 0, 11.6), 50.0, "c2_hall_drum_2")
	var hcrate := Breakable.make(r, "wood", Vector3(2.0, 0, 15.6), 30.0, "c2_hall_crate", "wooden_crate_01")
	hcrate.drop_table = "crate"
	# The tannoy horn the Warden speaks from (the intercom scene).
	RoomBuilder.prop(r, "Megaphone_01", PA_HORN - r.position, 90, 2.2, false)
	RoomBuilder._box(r, PA_HORN - r.position + Vector3(-0.12, 0.0, 0), Vector3(0.12, 0.4, 0.3), dark, false)
	_stencil(r, "FLOOD  DOOR  No. 3   -   DEEP  STACKS", Vector3(7.0, 4.4, 17.86), 180, 34, Color(0.86, 0.82, 0.7))
	# Lights: battery lamps on the walls until the set runs, then the
	# high-bay tubes.
	UndercroftPower.emergency_light(r, Vector3(0.18, 3.6, 2.0), 90.0, 0.55, 8.0)
	UndercroftPower.emergency_light(r, Vector3(15.82, 3.6, 13.0), -90.0, 0.5, 8.0)
	UndercroftPower.emergency_light(r, Vector3(4.0, 3.8, 17.82), 180.0, 0.5, 8.0)
	UndercroftPower.emergency_light(r, Vector3(11.0, 3.8, 0.18), 0.0, 0.5, 8.0)
	for x in [3.5, 8.0, 12.5]:
		for z in [3.5, 10.5, 15.5]:
			UndercroftPower.work_light(r, Vector3(x, 6.36, z), 0.0, 0.85, 9.0)
	place_checkpoint("ch2_hall", Vector3(43.0, 0, 3.0), Vector3(6, 3, 6))
	place_zombie("Z_c2_hall1", Vector3(52.0, 0, 7.5), 120, "shambler", true, "mechanic")
	place_zombie("Z_c2_hall2", Vector3(42.0, 0, 9.5), 30, "possum")
	place_pickup("ammo:9mm", Vector3(40.2, 0.97, -4.7), "c2_hall_ammo")
	place_pickup("gunpowder", Vector3(53.9, 0.1, 5.7), "c2_hall_powder")
	place_pickup("ammo:fuel", Vector3(42.6, 0.1, -5.3), "c2_hall_fuel")

## A heap of coal: a squashed dome with the coal surface, solid unless
## `flat` (a spill only ankle deep).
func _coal_heap(parent: Node3D, at: Vector3, size: Vector3, solid := true) -> Node3D:
	# A slumped mound, lumpy rather than smooth (a sphere pushed in and out
	# by noise), in a dark broken-rock coal texture, with loose lumps
	# rolled down around its foot.
	var seed_i := int(absf(at.x) * 13.0 + absf(at.z) * 7.0 + size.x * 31.0)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 40
	sm.rings = 20
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 1.3
	var fine := FastNoiseLite.new()
	fine.seed = seed_i + 1
	fine.frequency = 5.0
	for i in verts.size():
		var v: Vector3 = verts[i]
		var k := 1.0 + noise.get_noise_3dv(v) * 0.16 + fine.get_noise_3dv(v) * 0.05
		# Coal slumps: the top is flattened and the flanks spread.
		v = Vector3(v.x * k, v.y * k * (0.85 if v.y > 0.6 else 1.0), v.z * k)
		verts[i] = v * size
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = at
	mi.material_override = Mats.surface("coal", {"tile_size": 0.9, "tint": Color(0.2, 0.2, 0.22), "roughness_mul": 0.7, "grime_amount": 0.0, "variation": 0.3})
	parent.add_child(mi)
	# Loose lumps around the foot and on the flanks.
	var lump := SphereMesh.new()
	lump.radius = 0.5
	lump.height = 0.8
	lump.radial_segments = 6
	lump.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lump
	var n := clampi(int(size.x * size.z * 5.0), 10, 60)
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for i in n:
		var a := rng.randf() * TAU
		var f := rng.randf_range(0.7, 1.25)
		# On the flank (f < 1) a lump sits on the mound's surface; past the
		# foot it lies on the ground.
		var y := maxf(at.y + size.y * sqrt(maxf(0.0, 1.0 - f * f)) * 0.9, 0.03)
		var sc := rng.randf_range(0.1, 0.32) * (1.0 if f > 1.0 else 0.7)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.55, 0.9), sc * rng.randf_range(0.7, 1.1)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * size.x * f, y, sin(a) * size.z * f)))
	var lumps := MultiMeshInstance3D.new()
	lumps.multimesh = mm
	lumps.position = Vector3(at.x, 0.0, at.z)
	lumps.material_override = mi.material_override
	parent.add_child(lumps)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var pts := PackedVector3Array()
		for v in sm.get_faces():
			if v.y >= 0.0:
				pts.append(v * size)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		sb.add_child(cs)
		sb.position = at
		parent.add_child(sb)
	return mi

# ------------------------------------------------------------------ the coal yard

func _coal_yard() -> void:
	var r := RoomBuilder.build(self, {
		"id": "CoalYard", "pos": Vector3(55, 0, -6), "size": Vector3(22, 10, 18),
		"floor": "yard_ground", "wall": "yard_wall", "outdoor": true,
		"floor_look": {"tile_size": 3.0, "wetness": 0.85, "puddles": 1.0, "rain": 1.0, "grime_amount": 0.6},
		"wall_look": {"tile_size": 3.0, "grime_amount": 0.8, "grime_height": 2.2, "wall_wet": 1.0},
		"look": {"variation": 0.35},
		"openings": {"e": [[7.0, 4.0, 3.6]]},
		"skip_walls": ["w"],
		"decals": {"stain": 6, "blood": 2, "scorch": 2},
		"papers": 12,
	})
	# Above the engine hall's roof line the yard's west wall carries on up.
	var wall := Mats.surface("yard_wall", {"tile_size": 3.0, "grime_amount": 0.8, "wall_wet": 1.0})
	RoomBuilder._box(r, Vector3(0, 8.25, 9.0), Vector3(RoomBuilder.WALL_T, 3.5, 18.0), wall, false)
	# The ramp gate at the east end, chained, a burning lorry wedged against
	# it on the far side: no way out, but enough firelight to see by.
	var gate_mat := _steel(0.1, 0.7)
	RoomBuilder.prop(r, "large_iron_gate", Vector3(21.85, 0, 9.0), -90, 1.36, false)
	_wall_collider(r, Vector3(22.0, 1.8, 9.0), Vector3(0.3, 3.6, 4.0))
	for z in [7.6, 10.4]:
		UndercroftKit.bar(r, Vector3(21.7, 1.3, z), 0.03, 0.5, gate_mat, "x")
	UndercroftKit.meshy(r, "ambulance_wreck", Vector3(25.6, 0, 9.0), 70.0, 5.5, false)
	var fire := RoomBuilder.light(r, Vector3(23.5, 1.8, 9.0), FIRE, 3.2, 12.0, true, true)
	fire.name = "WreckFire"
	var flames := Effects.make_fire(Vector3(1.2, 0.3, 0.8), 1.8, true, false)
	flames.position = Vector3(25.0, 0.8, 9.0)
	r.add_child(flames)
	var embers := Effects.make_fire(Vector3(0.25, 0.05, 0.25), 0.5, true, false)
	embers.position = Vector3(9.5, 0.86, 9.5)
	r.add_child(embers)
	# The coal heap, banked against the north wall under the street drop.
	_coal_heap(r, Vector3(15.5, -0.6, 3.0), Vector3(4.2, 2.6, 2.9))
	_coal_heap(r, Vector3(10.6, -0.2, 1.6), Vector3(2.0, 0.9, 1.4))
	RoomBuilder.prop(r, "rusted_spade_01", Vector3(12.4, 0.5, 4.0), 30, 1.0, false)
	# The fuel shed in the south-west corner: corrugated iron on a timber
	# frame, open to the north. The keeper's diesel is inside.
	_fuel_shed(r, Vector3(1.0, 0, 12.0))
	# The keeper's brazier, a lorry tyre, crates, a coal cart.
	RoomBuilder.prop(r, "barrel_stove", Vector3(9.5, 0, 9.5), 0)
	var stove := RoomBuilder.light(r, Vector3(9.5, 1.3, 9.5), FIRE, 2.0, 8.0, true, true)
	stove.name = "Brazier"
	RoomBuilder.prop(r, "industrial_storage_cart", Vector3(6.0, 0, 3.0), 70)
	RoomBuilder.prop(r, "old_tyre", Vector3(13.0, 0.3, 11.2), 80, 1.0, false)
	RoomBuilder.prop(r, "wooden_crate_02", Vector3(18.6, 0, 15.6), 20)
	RoomBuilder.prop(r, "wooden_crate_01", Vector3(19.4, 0, 16.4), 75)
	RoomBuilder.prop(r, "concrete_road_barrier", Vector3(19.0, 0, 12.4), 90)
	# One standing double flood light from the kit (it also holds a single
	# one and a wall lamp), dead, by the shed.
	RoomBuilder.prop(r, "flood_lights/flood_lights_standing_double", Vector3(11.2, 0, 17.1), 200)
	RoomBuilder.prop(r, "modular_chainlink_fence", Vector3(4.0, 0, 7.6), 0)
	Breakable.make(r, "fuel_drum", Vector3(20.6, 0, 1.4), 15.0, "c2_yard_drum_1")
	Breakable.make(r, "fuel_drum", Vector3(17.4, 0, 14.6), 60.0, "c2_yard_drum_2")
	Breakable.make(r, "jerrycan", Vector3(8.6, 0, 10.6), 30.0, "c2_yard_jerrycan")
	Rain.add(r, Vector3(11, 10, 9), Vector3(10.6, 0, 8.6))
	_moonlit(r)
	place_zombie("Z_c2_yard1", Vector3(63.0, 0, 1.0), 270, "shambler", false, "mechanic")
	place_zombie("Z_c2_yard2", Vector3(66.5, 0, 6.5), 300, "shambler", false, "jogger")
	place_zombie("Z_c2_yard_run", Vector3(71.0, 0, 9.4), 260, "runner", true)
	place_zombie("Z_c2_yard_hound", Vector3(68.6, 0, -0.9), 240, "hound", true)
	place_zombie("Z_c2_yard3", Vector3(73.5, 0, 4.5), 250, "shambler", true, "cop")
	place_pickup("ammo:9mm", Vector3(63.4, 0.1, 9.6), "c2_yard_ammo")
	place_pickup("ammo:shells", Vector3(73.6, 0.1, 10.9), "c2_yard_shells")
	place_pickup("herb_green", Vector3(60.6, 0.1, -4.9), "c2_yard_herb")

func _fuel_shed(r: Node3D, at: Vector3) -> void:
	var shed := Node3D.new()
	shed.name = "FuelShed"
	shed.position = at
	r.add_child(shed)
	var iron := Mats.surface("corrugated_rust", {"tile_size": 1.6, "wall_wet": 0.8, "grime_amount": 0.5})
	var timber := Mats.trim(Color(0.22, 0.14, 0.08), 0.85)
	# 5 m wide (x), 4.5 m deep (z), open on its north side, roof pitched to
	# the south.
	RoomBuilder._box(shed, Vector3(0.05, 1.3, 2.25), Vector3(0.1, 2.6, 4.5), iron, true)
	RoomBuilder._box(shed, Vector3(4.95, 1.3, 2.25), Vector3(0.1, 2.6, 4.5), iron, true)
	RoomBuilder._box(shed, Vector3(2.5, 1.3, 4.45), Vector3(5.0, 2.6, 0.1), iron, true)
	var roof := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(5.4, 0.06, 5.0)
	roof.mesh = rb
	roof.material_override = iron
	roof.position = Vector3(2.5, 2.85, 2.2)
	roof.rotation.x = 0.12
	shed.add_child(roof)
	for x in [0.1, 2.5, 4.9]:
		UndercroftKit.bar(shed, Vector3(x, 1.4, 0.1), 0.06, 2.8, timber, "y")
	RoomBuilder._box(shed, Vector3(2.5, 2.75, 0.1), Vector3(5.0, 0.14, 0.14), timber, false)
	_stencil(shed, "FUEL  -  NO  NAKED  LIGHTS", Vector3(2.5, 2.45, 0.2), 0, 30, Color(0.86, 0.78, 0.3))
	RoomBuilder.prop(shed, "Barrel_01", Vector3(0.6, 0, 3.8), 0)
	RoomBuilder.prop(shed, "Barrel_01", Vector3(1.25, 0, 3.95), 30)
	RoomBuilder.prop(shed, "metal_jerrycan", Vector3(4.3, 0, 3.9), 80)
	RoomBuilder.prop(shed, "small_lpg_tank", Vector3(4.4, 0, 1.2), 0)
	RoomBuilder.prop(shed, "wooden_crate_02", Vector3(2.3, 0, 4.0), 90)
	RoomBuilder.prop(shed, "metal_toolbox", Vector3(2.3, 0.46, 4.0), 15, 1.0, false)
	RoomBuilder.prop(shed, "hanging_industrial_lamp", Vector3(2.5, 2.7, 2.2), 0, 1.0, false)
	var l := RoomBuilder.light(shed, Vector3(2.5, 1.6, 2.2), WARM, 0.7, 4.5, false, true)
	l.name = "ShedLamp"
	place_pickup("key:diesel_can", r.position + at + Vector3(3.3, 0.02, 3.5), "c2_diesel")

# ------------------------------------------------------------------ the deep stacks

func _deep_stacks() -> void:
	var r := RoomBuilder.build(self, {
		"id": "DeepStacks", "pos": Vector3(43, 0, 12), "size": Vector3(8, 4, 8),
		"floor": "basement_floor", "wall": "basement_wall", "ceiling": "undercroft_floor", "trim": Color(0.2, 0.2, 0.2),
		"floor_look": {"tile_size": 2.0, "wetness": 1.0, "puddles": 1.0, "grime_amount": 0.8},
		"wall_look": {"tile_size": 2.0, "stain_amount": 0.9, "grime_amount": 0.9, "grime_height": 1.4, "wall_wet": 0.8},
		"skip_walls": ["n"],
		"decals": {"stain": 4, "blood": 1},
		"papers": 30,
	})
	for i in 3:
		_record_shelf(r, Vector3(1.2 + i * 2.2, 0, 3.6), 0, 2.0, 2.6, 0.5, 11 + i)
		_record_shelf(r, Vector3(1.2 + i * 2.2, 0, 7.5), 180, 2.0, 2.6, 0.5, 21 + i)
	# What the water knocked off them.
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(3.3, 0, 5.2), 38, 0.9, false).rotation_degrees.z = 82
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(6.1, 0, 5.9), -20, 0.85, false)
	RoomBuilder.prop(r, "binder_notebook", Vector3(2.4, 0.01, 5.7), 70, 1.0, false)
	RoomBuilder.prop(r, "binder_notebook", Vector3(5.2, 0.01, 4.9), 140, 1.0, false)
	# The bulkhead on to the records annex (chapter 3), dogged shut.
	var bulk := Mats.surface("flood_steel", {"tile_size": 1.2, "grime_amount": 0.8})
	RoomBuilder._box(r, Vector3(0.16, 1.2, 5.6), Vector3(0.1, 2.2, 1.3), bulk, true)
	UndercroftKit.bar(r, Vector3(0.24, 1.2, 5.6), 0.22, 0.04, _steel(0.25), "x", 20)
	_stencil(r, "RECORDS  ANNEX", Vector3(0.14, 2.6, 5.6), 90, 30, Color(0.82, 0.8, 0.7))
	# Nasri's staff lanyard on the wet floor, and the chalk on the wall.
	var lan := Node3D.new()
	lan.name = "Lanyard"
	lan.position = LANYARD_AT - r.position
	lan.rotation.y = 0.6
	r.add_child(lan)
	RoomBuilder._box(lan, Vector3(0, 0.004, 0), Vector3(0.055, 0.004, 0.085), Mats.trim(Color(0.85, 0.85, 0.82), 0.5), false)
	RoomBuilder._box(lan, Vector3(0, 0.0055, -0.012), Vector3(0.04, 0.002, 0.03), Mats.trim(Color(0.2, 0.32, 0.55), 0.6), false)
	var strap := Mats.trim(Color(0.55, 0.08, 0.06), 0.8)
	for i in 6:
		RoomBuilder._box(lan, Vector3(sin(i * 0.9) * 0.08, 0.003, -0.06 - i * 0.05), Vector3(0.012, 0.003, 0.055), strap, false)
	var chalk := _chalk(r, "THE COUNT\nIS WRONG", CHALK_AT - r.position + Vector3(0, 0.15, 0), -90, 64, 0.0026)
	chalk.name = "Chalk"
	var marks := _chalk(r, "IIII  IIII  IIII  IIII  IIII  IIII  IIII  IIII  II", CHALK_AT - r.position + Vector3(0, -0.55, 0), -90, 34, 0.0022, Color(0.85, 0.85, 0.8))
	marks.modulate.a = 0.8
	UndercroftPower.emergency_light(r, Vector3(7.86, 2.8, 2.0), -90.0, 0.3, 5.0)
	UndercroftPower.work_light(r, Vector3(4.0, 3.86, 2.2), 90.0, 0.6, 7.0)
	place_pickup("ammo:9mm", Vector3(49.6, 0.1, 13.0), "c2_stacks_ammo")

## A records rack in the deep stacks: steel uprights and boards (as
## RoomBuilder.shelf_unit) loaded with the archive's real boxes, ledgers and
## binders, some pushed askew, gaps where things have gone.
func _record_shelf(parent: Node3D, pos: Vector3, rot_deg: float, w: float, h: float, d: float, seed_i: int) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = rot_deg
	parent.add_child(n)
	var steel := _steel(0.2, 0.6)
	var board := Mats.surface("plank_painted", {"tile_size": 1.0, "tint": Color(0.42, 0.4, 0.36), "grime_amount": 0.6})
	for x in [-w / 2 + 0.02, w / 2 - 0.02]:
		for z in [-d / 2 + 0.02, d / 2 - 0.02]:
			RoomBuilder._box(n, Vector3(x, h / 2, z), Vector3(0.04, h, 0.04), steel, false)
	var levels := [0.08, h * 0.27, h * 0.51, h * 0.75, h - 0.03]
	for y in levels:
		RoomBuilder._box(n, Vector3(0, y, 0), Vector3(w, 0.03, d), board, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for i in levels.size() - 1:
		var y0: float = levels[i] + 0.015
		var x := -w / 2 + 0.06
		while x < w / 2 - 0.3:
			var k := rng.randi() % 7
			if k == 0:
				x += rng.randf_range(0.15, 0.4)   # a gap
			elif k <= 3:
				# An archive box (0.39 wide as it comes), turned a little.
				var sc := rng.randf_range(0.82, 0.95)
				RoomBuilder.prop(n, "cardboard_box_01", Vector3(x + 0.2 * sc, y0, rng.randf_range(-0.02, 0.02)), rng.randf_range(-7.0, 7.0), sc, false)
				x += 0.4 * sc + 0.03
			elif k <= 5:
				# A run of bound ledgers standing on the board.
				RoomBuilder.prop(n, "book_encyclopedia_set_01", Vector3(x + 0.01, y0, -0.02), rng.randf_range(-4.0, 4.0), 1.0, false)
				x += 0.58
			else:
				# Binders lying in a stack.
				var stack := 2 + rng.randi() % 4
				for j in stack:
					RoomBuilder.prop(n, "binder_notebook", Vector3(x + 0.12, y0 + j * 0.032, 0.0), rng.randf_range(-12.0, 12.0), 1.0, false)
				x += 0.32
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, d)
	cs.shape = bs
	cs.position = Vector3(0, h / 2, 0)
	sb.add_child(cs)
	n.add_child(sb)

# ------------------------------------------------------------------ scares

func _horror_beats() -> void:
	# Something heavy walking the tunnel overhead, then a voice.
	place_scare("c2_corridor_whisper", "whisper", Vector3(20.0, 0, 1.6), Vector3(2, 3, 2.8), {"target": Vector3(26.0, 1.8, 3.0), "text": "...forty-three..."})
	# Past the muster door, the ceiling over it caves in and one drops through.
	place_scare("c2_corridor_drop", "body_drop", Vector3(31.5, 0, 1.6), Vector3(2.4, 3, 2.8), {"target": Vector3(28.95, 3.65, 2.55)})
	place_scare("c2_hall_sting", "stinger", Vector3(40.0, 0, 1.6), Vector3(2, 3, 2.8))
	place_scare("c2_gallery_lights", "lights_out", Vector3(29.6, 0, -1.0), Vector3(3.0, 3, 1.6), {"room": "ClockGallery", "duration": 5.0})
	place_scare("c2_yard_sting", "stinger", Vector3(57.0, 0, 4.0), Vector3(2, 3, 4))
	# The Tallyman waits up the back stair until the fuse comes out of the
	# clock (Chapter2Story's "hunt" scene wakes him).
	place_stalker(TALLY_IN, GameState.has_flag("c2_hunt") and not GameState.has_flag("c2_hunt_over"))
