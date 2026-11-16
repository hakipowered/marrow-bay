class_name Undercroft
extends LevelBase
## Chapter 2, "The Count": the Undercroft, the Archive's old service level
## two floors under the vault, where the vault elevator stops. Brick
## tunnels from 1902, the keeper's lodge, the survey room, the clock gallery
## that ran every clock in the building, the shelter staff's muster room,
## the river pump room with its flooded sump, the engine hall with its dead
## diesel generator and the flood door, and a sunken coal yard open to the
## rain. Original setting (docs/chapter2.md).
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
##   PumpRoom       (33, 0, 4.5) 6 x 7.5     the flooded sump: the starting handle
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
## The pump room's floor corner (its sump: PumpRoom).
const PUMP_AT := Vector3(33.0, 0.0, 4.5)
const TALLY_IN := Vector3(33.0, 0.0, -11.4)
const LANYARD_AT := Vector3(46.4, 0.0, 16.6)
const CHALK_AT := Vector3(51.0 - RoomBuilder.WALL_T / 2.0, 1.6, 17.0)

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
	_pump_room()
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

## Stencilled paint (Signage.paint) on a wall, facing local +z turned by
## `rot` (degrees); `at` is on the wall's face. On a room's wall the paint
## takes the brick's texture.
func _stencil(parent: Node3D, lines: Array, at: Vector3, rot, size: Vector2, col := Color(0.86, 0.82, 0.7), extra := {}) -> MeshInstance3D:
	var spec := {"size": size, "kind": "stencil", "lines": lines, "color": col, "wear": 0.5}
	spec.merge(extra, true)
	return Signage.paint(parent, at, rot, spec)

## A vitreous enamel plate bolted to a wall: cream, black letters, a black
## line round it, chipped, and rusting from its bolts.
func _enamel(parent: Node3D, lines: Array, at: Vector3, rot, size: Vector2, extra := {}) -> MeshInstance3D:
	var spec := {"size": size, "style": "enamel", "lines": lines, "border": 0.007, "wear": 0.5, "rust": 0.55, "track": 0.05}
	spec.merge(extra, true)
	return Signage.plate(parent, at, rot, spec)

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
func _chalk(parent: Node3D, lines: Array, at: Vector3, rot, size: Vector2, extra := {}) -> MeshInstance3D:
	var spec := {"size": size, "kind": "chalk", "lines": lines, "color": Color(0.88, 0.88, 0.84), "wear": 0.25}
	spec.merge(extra, true)
	return Signage.paint(parent, at, rot, spec)

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
	# The level number stencilled big, the rules on an enamel plate under it,
	# and the way on painted by the door.
	_stencil(r, ["B2"], Vector3(5.4, 3.32, 0.125), 0, Vector2(0.8, 0.62), Color(0.85, 0.8, 0.6), {"wear": 0.55})
	_enamel(r, ["UNDERCROFT SERVICE LEVEL", ["NO UNACCOMPANIED ENTRY", 0.62]], Vector3(5.4, 2.5, 0.125), 0, Vector2(1.3, 0.3))
	_stencil(r, ["ENGINE HALL"], Vector3(6.875, 2.6, 4.6), -90, Vector2(1.3, 0.24), Color(0.86, 0.82, 0.7), {"arrow": "left"})
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
			"s": [[3.4, 1.2, 2.3, {"frame": false}], [18.4, 1.4, 2.4, {"frame": false}], [27.0, 1.2, 2.3, {"frame": false}]],
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
	# Enamel plates over the doorways, the ways on stencilled at eye height
	# between the pilasters. (The south wall reads with -x on the right.)
	_enamel(r, ["SURVEY ROOM"], Vector3(5.0, 2.62, 0.125), 0, Vector2(0.95, 0.2))
	_enamel(r, ["CLOCK GALLERY"], Vector3(24.1, 2.66, 0.125), 0, Vector2(1.05, 0.2))
	_enamel(r, ["KEEPER'S LODGE"], Vector3(4.0, 2.6, 2.875), 180, Vector2(1.05, 0.2))
	_enamel(r, ["MUSTER ROOM", ["SHELTER STAFF", 0.55]], Vector3(19.1, 2.68, 2.875), 180, Vector2(1.0, 0.26))
	_enamel(r, ["PUMP ROOM", ["SUMP B", 0.55]], Vector3(27.6, 2.6, 2.875), 180, Vector2(0.9, 0.26))
	_stencil(r, ["LIFT"], Vector3(9.5, 1.85, 0.125), 0, Vector2(0.75, 0.2), Color(0.86, 0.82, 0.7), {"arrow": "left"})
	_stencil(r, ["ENGINE HALL"], Vector3(12.45, 1.85, 0.125), 0, Vector2(1.3, 0.2), Color(0.86, 0.82, 0.7), {"arrow": "right"})
	_stencil(r, ["ENGINE HALL"], Vector3(30.4, 1.85, 2.875), 180, Vector2(1.3, 0.2), Color(0.86, 0.82, 0.7), {"arrow": "left"})
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
	# The item box, the same store as the office's: a supply crate in the
	# corner between the bookshelf and the cot.
	place_item_box(Vector3(13.65, 0, 9.92), 180, "lodge")
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
	# Signwritten on the plaster above it, in faded gilt.
	_stencil(r, ["CITY SURVEY OFFICE  -  RIVER DISTRICT  1891"], Vector3(6.0, 3.66, 0.125), 0, Vector2(3.8, 0.2),
		Color(0.74, 0.6, 0.34), {"kind": "brush", "font": "roman", "wear": 0.6, "track": 0.08})
	# The keeper's tally on the west wall: hundreds of marks, in fives,
	# scratched into the plaster, and the last ones still fresh.
	var counts: Array = []
	for row in 7:
		counts.append((9 - (row % 3)) * 5 - (3 if row == 6 else 0))
	Signage.paint(r, Vector3(0.125, 1.9, 7.6), 90, {"size": Vector2(1.5, 0.85), "kind": "scratch", "name": "Tally",
		"color": Color(0.82, 0.79, 0.72), "wear": 0.2, "strokes": Signage.tally(counts, Vector2(1.5, 0.85), 0.085, 71), "stroke_w": 0.0045})
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
	# The maker's brass plaque on the wall over the master clock.
	Signage.plate(r, CLOCK_AT - r.position + Vector3(0, 2.86, 0), 0, {"size": Vector2(0.6, 0.16), "style": "brass",
		"lines": ["MASTER REGULATOR", ["KEEP WOUND", 0.7]], "font": "roman", "border": 0.003, "wear": 0.55})
	UndercroftPower.emergency_light(r, Vector3(0.14, 3.1, 8.0), 90.0, 0.4, 6.0)
	UndercroftPower.emergency_light(r, Vector3(13.86, 3.2, 6.0), -90.0, 0.35, 6.0)
	for x in [3.5, 10.5]:
		UndercroftPower.work_light(r, Vector3(x, 4.66, 5.5), 0.0, 0.7, 8.0)
	place_zombie("Z_c2_gallery1", Vector3(30.5, 0, -3.0), 200, "shambler", false, "suit")
	place_zombie("Z_c2_gallery_crawl", Vector3(33.0, 0, -1.6), 160, "crawler", false, "office")
	place_pickup("ammo:shells", Vector3(33.6, 0.92, -0.05), "c2_gallery_shells")
	place_pickup("herb_red", Vector3(21.5, 1.05, -7.5), "c2_gallery_red")

# ------------------------------------------------------------------ the back stair

## The north stair (BackStair room, local metres): a landing inside the
## door, then one flight rising north toward the vault level. The upper
## flight and the floor above it came down on its top half: a heap of brick
## and concrete fills the north end up under the hole they left, and that
## dark gap is the way down for whatever comes.
const STAIR_FOOT := 5.6       # local z of the first riser
const STAIR_RISE := 0.18
const STAIR_GOING := 0.29
const STAIR_STEPS := 14
const STAIR_X := Vector2(0.125, 2.875)   # wall face to wall face

var _heap_noise: FastNoiseLite

func _back_stair() -> void:
	var r := RoomBuilder.build(self, {
		"id": "BackStair", "pos": Vector3(31.5, 0, -17.5), "size": Vector3(3, 5.0, 8),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor",
		"floor_look": {"tile_size": 2.0, "grime_amount": 0.9},
		"wall_look": {"tile_size": 2.0, "grime_amount": 0.9, "stain_amount": 0.8},
		"skip_walls": ["s"],
		# Where the floor above came through, over the top of the heap.
		"ceiling_holes": [[0.35, 0.2, 2.3, 2.5]],
		"decals": {"blood": 1},
	})
	place_door(STAIR_DOOR, 0, Door.Kind.MANUAL, "steel", 1.4, 2.4, "stair_door")
	_heap_noise = FastNoiseLite.new()
	_heap_noise.seed = 1891
	_heap_noise.frequency = 0.9
	_heap_noise.fractal_octaves = 3
	# The flight: solid concrete steps with steel nosings, and the half
	# landing at its head.
	var stone := Mats.surface("undercroft_floor", {"tile_size": 1.0, "grime_amount": 0.9})
	var nosing := _steel(0.16, 0.45)
	var w := STAIR_X.y - STAIR_X.x
	for i in STAIR_STEPS:
		var top := STAIR_RISE * (i + 1)
		var z1 := STAIR_FOOT - STAIR_GOING * i
		var z0 := z1 - STAIR_GOING
		_block(r, Vector3(1.5, top / 2.0, (z0 + z1) / 2.0), Vector3(w, top, z1 - z0), stone)
		RoomBuilder._box(r, Vector3(1.5, top + 0.003, z1 - 0.018), Vector3(w - 0.02, 0.006, 0.036), nosing, false)
	var head := STAIR_FOOT - STAIR_GOING * STAIR_STEPS
	var land := STAIR_RISE * STAIR_STEPS
	_block(r, Vector3(1.5, land / 2.0, (0.125 + head) / 2.0), Vector3(w, land, head - 0.125), stone)
	# The heap, and what lies on it.
	_heap(r)
	_heap_wreck(r)
	# A tube handrail on brackets up the east wall, running into the heap.
	var rail := _steel(0.2, 0.4)
	var z := STAIR_FOOT + 0.25
	var last := z
	while z > 1.0:
		if _heap_y(STAIR_X.y - 0.12, z) > _rail_y(z) - 0.06:
			break
		last = z
		z -= 0.05
	var a := Vector3(STAIR_X.y - 0.075, _rail_y(STAIR_FOOT + 0.25), STAIR_FOOT + 0.25)
	var b := Vector3(STAIR_X.y - 0.075, _rail_y(last - 0.15), last - 0.15)
	_strut(r, a, b, 0.022, rail, 10)
	var k := 0.0
	while k < 1.0:
		var p := a.lerp(b, k)
		_strut(r, p, Vector3(STAIR_X.y, p.y - 0.04, p.z), 0.009, rail, 6)
		k += 1.0 / maxf(1.0, round(a.distance_to(b) / 1.1))
	# Dust still sifting down from the hole, in the torchlight.
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.position = Vector3(1.5, 4.8, 1.4)
	dust.amount = 26
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.0, 0.1, 1.1)
	dust.direction = Vector3.DOWN
	dust.spread = 25.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.14
	dust.gravity = Vector3(0, -0.04, 0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var dq := QuadMesh.new()
	dq.size = Vector2(0.008, 0.008)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.75, 0.7, 0.62, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.roughness = 1.0
	dq.material = dm
	dust.mesh = dq
	r.add_child(dust)
	# Nobody climbs the heap to the hole: the way up stops at its toe.
	_wall_collider(r, Vector3(1.5, 2.3, 4.3), Vector3(w, 4.0, 0.1))
	# The way up, stencilled on the landing wall; the keeper's count
	# scratched beside the door; the plate over the door on the gallery side.
	_stencil(r, ["VAULT LEVEL"], Vector3(STAIR_X.x, 1.75, 6.5), 90, Vector2(1.2, 0.2), Color(0.86, 0.82, 0.7), {"arrow": "right"})
	Signage.paint(r, Vector3(STAIR_X.x, 1.3, 7.3), 90, {"size": Vector2(0.55, 0.32), "kind": "scratch", "name": "Tally",
		"color": Color(0.78, 0.74, 0.66), "wear": 0.15, "strokes": Signage.tally([23, 17, 9], Vector2(0.55, 0.32), 0.07, 1891),
		"stroke_w": 0.004})
	_enamel(self, ["NORTH STAIR", ["STAFF ONLY", 0.55]], Vector3(STAIR_DOOR.x, 2.66, STAIR_DOOR.z + RoomBuilder.WALL_T / 2.0), 0,
		Vector2(0.9, 0.24))
	UndercroftPower.emergency_light(r, Vector3(STAIR_X.y, 2.4, 7.0), -90.0, 0.25, 3.5)

## Where the steps' tops are at local z (0 on the landing).
static func _stair_y(z: float) -> float:
	if z >= STAIR_FOOT:
		return 0.0
	var i := int(floor((STAIR_FOOT - z) / STAIR_GOING))
	return STAIR_RISE * mini(i + 1, STAIR_STEPS)

## The handrail's height over the nosings.
static func _rail_y(z: float) -> float:
	return 0.92 + STAIR_RISE + maxf(0.0, STAIR_FOOT - z) * STAIR_RISE / STAIR_GOING

## The heap's surface: from a ragged toe a few steps up, rising at about the
## angle loose brick settles at to a crest against the north wall, slumped
## further to the west where the upper flight came down. Below the steps
## where there is no heap.
func _heap_y(x: float, z: float) -> float:
	var toe := 4.45 + 0.28 * sin(x * 2.3 + 0.7) + 0.12 * sin(x * 5.1)
	var t := clampf((toe - z) / (toe - 0.3), 0.0, 1.0)
	var crest := 3.75 + 0.3 * (1.0 - x / 3.0)
	var y := lerpf(_stair_y(toe) - 0.12, crest, pow(t, 0.82))
	y += _heap_noise.get_noise_2d(x * 1.4, z * 1.4) * 0.22 * smoothstep(0.0, 0.25, t)
	y += _heap_noise.get_noise_2d(x * 6.0 + 40.0, z * 6.0) * 0.05
	return y

## The heap as one mesh: a height field from wall to wall, cut off where it
## dips under the steps, with a skirt down into them along its toe. Crushed
## brick texture, and solid to walk on.
func _heap(r: Node3D) -> void:
	var xs: Array = []
	var zs: Array = []
	var x := STAIR_X.x - 0.1
	while x < STAIR_X.y + 0.1:
		xs.append(x)
		x += 0.09
	xs.append(STAIR_X.y + 0.1)
	var z := 0.0
	while z < STAIR_FOOT:
		zs.append(z)
		z += 0.07
	var hs := {}
	for i in xs.size():
		for j in zs.size():
			hs[Vector2i(i, j)] = _heap_y(xs[i], zs[j])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}
	var tris: Array = []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var q := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				var ok := true
				for v in tri:
					if hs[v] < _stair_y(zs[v.y]) + 0.015:
						ok = false
				if not ok:
					continue
				tris.append(tri)
				for e in 3:
					var a: Vector2i = tri[e]
					var b: Vector2i = tri[(e + 1) % 3]
					edges[_edge_key(a, b)] = edges.get(_edge_key(a, b), 0) + 1
	var pos := func(v: Vector2i) -> Vector3:
		return Vector3(xs[v.x], hs[v], zs[v.y])
	var nrm := func(v: Vector2i) -> Vector3:
		var e := 0.05
		var px: float = xs[v.x]
		var pz: float = zs[v.y]
		return Vector3(_heap_y(px - e, pz) - _heap_y(px + e, pz), 2.0 * e, _heap_y(px, pz - e) - _heap_y(px, pz + e)).normalized()
	for tri in tris:
		var p := [pos.call(tri[0]), pos.call(tri[1]), pos.call(tri[2])]
		var order := [0, 1, 2]
		if ((p[2] - p[0]).cross(p[1] - p[0])).y < 0.0:
			order = [0, 2, 1]
		for o in order:
			st.set_normal(nrm.call(tri[o]))
			st.set_uv(Vector2(p[o].x, p[o].z))
			st.add_vertex(p[o])
		# Along the heap's open edges, a skirt down into the steps.
		for e in 3:
			var a: Vector2i = tri[e]
			var b: Vector2i = tri[(e + 1) % 3]
			if edges[_edge_key(a, b)] != 1:
				continue
			var pa: Vector3 = pos.call(a)
			var pb: Vector3 = pos.call(b)
			var c: Vector3 = (p[0] + p[1] + p[2]) / 3.0
			var out := ((pa + pb) / 2.0 - c)
			out.y = 0.0
			out = out.normalized()
			var da := pa - Vector3(0, 0.35, 0)
			var db := pb - Vector3(0, 0.35, 0)
			var quad := [pa, pb, db, pa, db, da]
			if ((quad[2] - quad[0]).cross(quad[1] - quad[0])).dot(out) < 0.0:
				quad = [pa, db, pb, pa, da, db]
			for v in quad:
				st.set_normal(out)
				st.set_uv(Vector2(v.x + v.z, v.y))
				st.add_vertex(v)
	st.generate_tangents()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Heap"
	mi.mesh = mesh
	mi.material_override = Mats.surface("rubble", {"tile_size": 1.3, "grime_amount": 0.3, "tint": Color(0.82, 0.74, 0.68)})
	r.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)

static func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y) if (a.x < b.x or (a.x == b.x and a.y < b.y)) else Vector4i(b.x, b.y, a.x, a.y)

## What came down with the floor, lying on the heap where it fell: a
## length of the upper flight, a steel joist, timber, lumps of bonded
## brickwork and loose bricks down to the landing. Everything rests on the
## heap or the steps (sat a little into the rubble), nothing hangs.
func _heap_wreck(r: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1891
	var stone := Mats.surface("undercroft_floor", {"tile_size": 1.0, "grime_amount": 0.9})
	var brick := Mats.surface("undercroft_brick", {"tile_size": 0.8, "grime_amount": 0.6})
	var timber := Mats.trim(Color(0.2, 0.14, 0.09), 0.85)
	var ground := func(px: float, pz: float) -> float:
		return maxf(_heap_y(px, pz), _stair_y(pz))
	# A length of the upper flight, five steps of it, fallen on the west side
	# of the heap with its treads turned up.
	var f := Node3D.new()
	f.name = "FallenFlight"
	var lo := Vector3(0.95, ground.call(0.95, 3.35) + 0.03, 3.35)
	var hi := Vector3(0.85, ground.call(0.85, 1.55) + 0.02, 1.55)
	var mid := (lo + hi) / 2.0
	# Rolled to lie along the heap's slope across it, west side up.
	var roll := atan((ground.call(mid.x - 0.5, mid.z) - ground.call(mid.x + 0.5, mid.z)) / 1.0)
	_lay(f, lo, hi, 0.0, roll)
	r.add_child(f)
	var len := lo.distance_to(hi)
	_block_vis(f, Vector3(0, 0.08, 0), Vector3(1.25, 0.16, len), stone, true)
	for s in 5:
		var sz := -len / 2.0 + len * (s + 0.5) / 5.0
		_block_vis(f, Vector3(0, 0.16 + 0.085, sz - len / 20.0), Vector3(1.25, 0.17, len / 10.0), stone)
	# A steel joist from the floor above: off the heap's east flank on to
	# the steps.
	var j := Node3D.new()
	j.name = "FallenJoist"
	var ja := Vector3(2.35, ground.call(2.35, 1.0) + 0.08, 1.0)
	var jb := Vector3(1.95, ground.call(1.95, 4.95) + 0.075, 4.95)
	_lay(j, ja, jb, 0.0, -0.12)
	r.add_child(j)
	var jl := ja.distance_to(jb)
	var steel := _steel(0.18, 0.6)
	_block_vis(j, Vector3(0, 0, 0), Vector3(0.012, 0.15, jl), steel)
	_wall_collider(j, Vector3.ZERO, Vector3(0.1, 0.15, jl))
	for y in [-0.07, 0.07]:
		_block_vis(j, Vector3(0, y, 0), Vector3(0.1, 0.012, jl), steel)
	# Floor timbers, snapped, across the heap.
	for t in [[Vector2(0.4, 0.9), Vector2(2.2, 2.4), 0.3], [Vector2(2.6, 2.9), Vector2(0.9, 3.9), -0.4], [Vector2(1.6, 0.4), Vector2(2.7, 1.6), 0.1]]:
		var tn := Node3D.new()
		var ta := Vector3(t[0].x, ground.call(t[0].x, t[0].y) + 0.03, t[0].y)
		var tb := Vector3(t[1].x, ground.call(t[1].x, t[1].y) + 0.03, t[1].y)
		_lay(tn, ta, tb, t[2], 0.0)
		r.add_child(tn)
		_block_vis(tn, Vector3.ZERO, Vector3(0.075, 0.19, ta.distance_to(tb)), timber, true)
	# Lumps of bonded brickwork (still showing their courses) and loose
	# bricks in three fired shades, each merged into one mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lumps := [[Vector2(1.9, 2.1), Vector3(0.62, 0.3, 0.33)], [Vector2(0.6, 3.6), Vector3(0.45, 0.24, 0.22)],
		[Vector2(2.4, 3.3), Vector3(0.5, 0.36, 0.22)], [Vector2(1.3, 1.0), Vector3(0.7, 0.33, 0.33)]]
	for l in lumps:
		_settle(st, l[0], l[1], ground, rng, 0.3)
	st.generate_normals()
	st.generate_tangents()
	var lmi := MeshInstance3D.new()
	lmi.name = "Brickwork"
	lmi.mesh = st.commit()
	lmi.material_override = brick
	r.add_child(lmi)
	var shades := [Color(0.4, 0.17, 0.11), Color(0.47, 0.22, 0.14), Color(0.32, 0.14, 0.1)]
	var sts: Array = []
	for c in shades:
		var s3 := SurfaceTool.new()
		s3.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(s3)
	for n in 70:
		var at := Vector2(rng.randf_range(0.3, 2.7), rng.randf_range(0.5, 5.2))
		if n >= 58:
			# Strays bounced down to the landing, clear of the doorway.
			at = Vector2(rng.randf_range(0.3, 0.9) if n % 2 == 0 else rng.randf_range(2.1, 2.7), rng.randf_range(5.7, 6.9))
		var size := Vector3(0.215, 0.065, 0.1025)
		if rng.randf() < 0.3:
			size = Vector3(0.215, 0.1025, 0.065)
		if rng.randf() < 0.25:
			size.x = rng.randf_range(0.08, 0.15)   # half bats
		_settle(sts[n % 3], at, size, ground, rng, 0.35)
	for i in 3:
		(sts[i] as SurfaceTool).generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Bricks%d" % i
		mi.mesh = (sts[i] as SurfaceTool).commit()
		mi.material_override = Mats.trim(shades[i], 0.9)
		r.add_child(mi)

## Sets n's transform so its local z runs from a to b, its local y as near
## straight up as that allows, rolled `roll` radians about its length; its
## middle sits `lift` above the line (half its thickness: it rests on it).
func _lay(n: Node3D, a: Vector3, b: Vector3, lift: float, roll: float) -> void:
	var fwd := (b - a).normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var up := fwd.cross(right).normalized()
	var basis := Basis(right, up, fwd).rotated(fwd, roll)
	n.transform = Transform3D(basis, (a + b) / 2.0 + up * lift)

## A box in n's own frame (solid if `collide`).
func _block_vis(n: Node3D, center: Vector3, ext: Vector3, mat: Material, collide := false) -> void:
	RoomBuilder._box(n, center, ext, mat, collide)

## A brick or a lump of brickwork, settled on the ground where it lies: its
## base on the slope there, turned at random, sunk `sink` of its height.
func _settle(st: SurfaceTool, at: Vector2, size: Vector3, ground: Callable, rng: RandomNumberGenerator, sink: float) -> void:
	var e := 0.06
	var y: float = ground.call(at.x, at.y)
	var n := Vector3(ground.call(at.x - e, at.y) - ground.call(at.x + e, at.y), 2.0 * e,
		ground.call(at.x, at.y - e) - ground.call(at.x, at.y + e)).normalized()
	if not n.is_finite() or n.y < 0.3:
		n = Vector3.UP
	var basis := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, rng.randf() * TAU)
	basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
	var bm := BoxMesh.new()
	bm.size = size
	st.append_from(bm, 0, Transform3D(basis, Vector3(at.x, y, at.y) + n * size.y * (0.5 - sink)))

## A round bar from a to b (a handrail, a bracket).
func _strut(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, sides := 8) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = a.distance_to(b)
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)
	parent.add_child(mi)

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
	# Civil defence green for the muster point; red for staff only.
	Signage.plate(r, Vector3(7.0, 2.95, 9.875), 180, {"size": Vector2(1.2, 0.4), "style": "painted", "lines": ["MUSTER POINT B"],
		"field": Color(0.07, 0.28, 0.15), "ink": Color(0.88, 0.86, 0.78), "border": 0.012, "wear": 0.5})
	_enamel(r, ["STAFF ONLY"], Vector3(13.875, 2.75, 7.4), -90, Vector2(0.6, 0.16),
		{"field": Color(0.55, 0.07, 0.05), "ink": Color(0.9, 0.88, 0.8), "border": 0.005})
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

# ------------------------------------------------------------------ the pump room (the sump)

## Off the service tunnel next to the engine hall: the river pump room, its
## flooded sump with the starting handle at the bottom (PumpRoom has the
## pit, the valves, the water and the puzzle). Dark but for the red battery
## lamps; the drowned man under the water is "Z_c2_sump".
func _pump_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "PumpRoomShell", "pos": PUMP_AT, "size": Vector3(6, 4.0, 7.5),
		"floor": "undercroft_floor", "wall": "undercroft_brick", "ceiling": "undercroft_floor", "trim": Color(0.16, 0.15, 0.14),
		"floor_look": {"tile_size": 1.8, "wetness": 0.9, "puddles": 0.9, "grime_amount": 0.9, "stain_amount": 0.6},
		"wall_look": {"tile_size": 2.2, "grime_amount": 1.0, "grime_height": 1.8, "stain_amount": 0.9, "wall_wet": 0.7},
		"ceiling_look": {"tint": Color(0.36, 0.35, 0.33)},
		"openings": {"n": [[1.0, 1.2, 2.3]]},
		# Back to back with the corridor (n), the muster room (w) and the
		# engine hall (e).
		"wall_inset": {"n": RoomBuilder.WALL_T, "w": RoomBuilder.WALL_T, "e": RoomBuilder.WALL_T},
		"floor_holes": [[PumpRoom.PIT.position.x, PumpRoom.PIT.position.y, PumpRoom.PIT.size.x, PumpRoom.PIT.size.y]],
		"decals": {"stain": 5, "blood": 1},
		"papers": 2,
		"probe": true,
	})
	place_door(Vector3(PUMP_AT.x + 1.6, 0, PUMP_AT.z + RoomBuilder.WALL_T / 2.0), 0, Door.Kind.MANUAL, "steel", 1.2, 2.3, "pump_door")
	var pr := PumpRoom.new()
	pr.name = "PumpRoom"
	pr.position = PUMP_AT
	# Its stencils go on the shell's brick.
	pr.set_meta("wall_mat", r.get_meta("wall_mat"))
	add_child(pr)
	_stencil(r, ["SUMP B"], Vector3(4.2, 3.32, 0.375), 0, Vector2(1.0, 0.36), Color(0.82, 0.78, 0.66))
	# The station's cast plate from the 1974 refit.
	Signage.plate(r, Vector3(4.2, 2.9, 0.375), 0, {"size": Vector2(1.0, 0.24), "style": "cast", "corner": 0.02, "border": 0.006,
		"lines": ["RIVER DISTRICT PUMPING STATION", ["1974", 0.7]], "field": Color(0.07, 0.12, 0.2), "ink": Color(0.85, 0.82, 0.7)})
	# The drill card on a rack by the door, the tool chest, the extinguisher,
	# a crate of stores at the end of the valve gallery.
	RoomBuilder.prop(r, "worn_metal_rack", Vector3(0.6, 0, 1.45), 90)
	RoomBuilder.prop(r, "vintage_flashlight", Vector3(0.6, 1.5, 1.2), 20, 1.0, false)
	RoomBuilder.prop(r, "old_gas_mask", Vector3(0.6, 1.5, 1.7), 90, 1.0, false)
	RoomBuilder.prop(r, "metal_tool_chest", Vector3(5.3, 0, 0.95), -90)
	RoomBuilder.prop(r, "pipe_wrench", Vector3(1.6, 0.02, 2.2), 35, 1.0, false)
	# On the north wall east of the pumps: behind them it pinched the way
	# round them to the sump gate.
	RoomBuilder.prop(r, "korean_fire_extinguisher_01", Vector3(4.75, 0, 0.5), 0)
	# Past the far end of the pit: at the head of the steps it squeezed the
	# way down to less than a body's width for the infected.
	RoomBuilder.prop(r, "WetFloorSign_01", Vector3(4.5, 0, 7.05), 160)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(0.85, 0, 6.95), 10)
	RoomBuilder.prop(r, "trashbag", Vector3(1.5, 0, 7.0), 60, 1.0, false)
	UndercroftPower.emergency_light(r, Vector3(1.6, 2.75, 0.39), 0.0, 0.4, 5.5)
	UndercroftPower.emergency_light(r, Vector3(5.61, 2.9, 4.2), -90.0, 0.45, 7.0)
	UndercroftPower.emergency_light(r, Vector3(0.39, 2.7, 6.6), 90.0, 0.35, 5.0)
	for at in [Vector3(1.6, 3.9, 2.4), Vector3(3.9, 3.9, 5.2)]:
		UndercroftPower.work_light(r, at, 0.0, 0.6, 7.0)
	# The drill card on a steel ledge beside the door, under its stencil.
	var steel := Mats.trim(Color(0.22, 0.23, 0.22), 0.5, 0.7)
	RoomBuilder._box(r, Vector3(0.55, 1.0, 0.495), Vector3(0.44, 0.025, 0.22), steel, true)
	for bx in [0.38, 0.72]:
		RoomBuilder._box(r, Vector3(bx, 0.93, 0.42), Vector3(0.02, 0.12, 0.07), steel, false)
	_stencil(r, ["DRILL - SUMP B"], Vector3(0.55, 1.2, RoomBuilder.WALL_T * 1.5), 0, Vector2(0.44, 0.075), Color(0.82, 0.78, 0.66))
	place_pickup("file:pump_drill", PUMP_AT + Vector3(0.55, 1.02, 0.5), "c2_pump_drill")
	place_pickup("ammo:shells", PUMP_AT + Vector3(0.85, 0.36, 6.95), "c2_pump_shells")
	place_zombie("Z_c2_sump", PUMP_AT + PumpRoom.BODY_AT, PumpRoom.BODY_YAW, "possum", false, "mechanic")

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
	# The hall's name stencilled big between the pilasters, the set's plate
	# beside it.
	_stencil(r, ["ENGINE HALL"], Vector3(4.8, 4.55, 0.125), 0, Vector2(2.6, 0.55), Color(0.86, 0.82, 0.7))
	Signage.plate(r, Vector3(8.0, 3.95, 0.125), 0, {"size": Vector2(1.5, 0.34), "style": "painted",
		"lines": ["No. 2 STANDBY SET", ["ROTHWELL & SONS LTD  -  1958", 0.5]], "field": Color(0.11, 0.19, 0.14),
		"ink": Color(0.86, 0.83, 0.72), "border": 0.01, "wear": 0.5})
	# The diesel day tank on the north wall, dry, piped down to the set.
	var tank := Mats.surface("flood_steel", {"tile_size": 1.2, "grime_amount": 0.7, "tint": Color(0.42, 0.44, 0.34)})
	var dark := _steel(0.12)
	UndercroftKit.bar(r, Vector3(9.0, 2.6, 0.95), 0.62, 2.8, tank, "x", 24)
	for x in [7.9, 10.1]:
		RoomBuilder._box(r, Vector3(x, 1.4, 0.95), Vector3(0.12, 2.0, 0.9), dark, true)
	# Stencilled round the tank, and the keeper's chalk under it.
	for t in [[12.0, ["DIESEL DAY TANK"], Vector2(1.4, 0.2), "stencil", Color(0.9, 0.85, 0.3), tank],
			[-10.0, ["EMPTY"], Vector2(0.62, 0.2), "chalk", Color(0.88, 0.88, 0.84), null]]:
		var a := deg_to_rad(t[0])
		Signage.paint(r, Vector3(9.0, 2.6 + sin(a) * 0.62, 0.95 + cos(a) * 0.62), Vector3(-t[0], 0, 0), {"size": t[2],
			"kind": t[3], "lines": t[1], "color": t[4], "surface": t[5], "bend": 0.62, "bend_axis": "x", "wear": 0.4})
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
	_stencil(chute, ["COAL DROP"], Vector3(0, 3.5, 0.76), 0, Vector2(0.95, 0.18), Color(0.85, 0.8, 0.6), {"surface": plate})
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
	# Beside the flood door, clear of the slab's travel up the guides.
	_enamel(r, ["DEEP STACKS", ["FLOOD DOOR No. 3", 0.55]], Vector3(3.7, 2.5, 17.875), 180, Vector2(0.9, 0.28))
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
	# The keeper's note in the generator's cabinet: where everything went.
	place_pickup("file:gen_note", GENERATOR_AT + GeneratorSet.NOTE_AT, GeneratorSet.NOTE_ID)

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
	# Its sign hangs under the front beam on two wires, facing the yard.
	Signage.plate(shed, Vector3(2.5, 2.47, 0.1), 180, {"size": Vector2(1.0, 0.26), "style": "painted", "back": true,
		"lines": ["FUEL STORE", ["NO NAKED LIGHTS", 0.6]], "field": Color(0.62, 0.08, 0.05), "ink": Color(0.9, 0.87, 0.78),
		"border": 0.008, "fix": "rivets", "fix_at": [Vector2(-0.43, 0.095), Vector2(0.43, 0.095)], "wear": 0.6, "rust": 0.8})
	for x in [-0.43, 0.43]:
		UndercroftKit.bar(shed, Vector3(2.5 + x, 2.625, 0.1), 0.0025, 0.12, _steel(0.25), "y", 4)
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
	_enamel(r, ["RECORDS ANNEX"], Vector3(0.125, 2.6, 5.6), 90, Vector2(1.0, 0.22))
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
	var chalk := _chalk(r, ["THE COUNT", "IS WRONG"], CHALK_AT - r.position + Vector3(0, 0.15, 0), -90, Vector2(1.3, 0.56))
	chalk.name = "Chalk"
	Signage.paint(r, CHALK_AT - r.position + Vector3(0, -0.5, 0), -90, {"size": Vector2(1.5, 0.18), "kind": "chalk",
		"color": Color(0.85, 0.85, 0.8), "wear": 0.35, "strokes": Signage.tally([42], Vector2(1.5, 0.18), 0.12, 9), "stroke_w": 0.008})
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
