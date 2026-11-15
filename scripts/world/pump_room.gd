class_name PumpRoom
extends Node3D
## The pump room's flooded sump (chapter 2): the puzzle that gives up the
## generator's starting handle.
##
## Sump B is a concrete pit in the floor, a man and a half deep. Orrin Vell,
## the night keeper, threw the generator's starting handle into it and opened
## the river inlet over it, so nobody could start the engine and raise the
## flood door to the deep stacks (his note in the generator's cabinet says
## so). The sump pumps are electric and dead with everything else.
##
## The way down is the 1974 drill (the board on the wall, the card by the
## door): stop what is coming in, then let it out by gravity into the storm
## sewer. Three gate valves on the west wall, each with a brass tag:
##   V1 RIVER INLET   starts open: the river keeps pouring in (the water
##                    boils over the inlet while it runs)
##   V2 SUMP SUCTION  starts shut: opens the sump's drain to the sewer
##   V3 SEWER BYPASS  starts open: on a high river the sewer runs backwards,
##                    so with it open the drain belches water back up
## Only V1 shut, V2 open and V3 shut empties it. Every other setting fills it,
## holds it or backs it up, and the water, the sounds, the level gauge on the
## wall and the survivors say which. Turning a wheel takes a moment: the
## survivor puts the gun away and pulls it round hand over hand.
##
## When it's dry the safety gate can be unhooked and the steps go down: the
## handle lies in the silt by the drain, next to the man who went in after it
## (an infected lying in the water, Undercroft "Z_c2_sump", who gets up when
## someone comes close).
##
## Local frame: the pump room's own floor corner (the room node's position),
## x east, z south. The host decides, every phone shows it; the flags come
## back with a save (a part-drained sump comes back full).

const FLAG_DRAINED := "c2_sump_drained"
const FLAG_GATE := "c2_sump_gate"
const VALVE_FLAG := "c2_valve_%d"
const HANDLE_ID := "c2_crank"

## The pit in the floor (x, z, width, depth) and its floor.
const PIT := Rect2(2.15, 2.6, 3.1, 4.0)
const FLOOR_Y := -1.5
const FULL_Y := -0.16
const EMPTY_Y := -1.47
## The steps down the pit's east side, top (north) to bottom: wide enough
## for the navmesh to run down them (agent radius 0.45).
const STAIR := Rect2(3.95, 2.6, 1.3, 2.6)
const STEPS := 10

## The three valves: tag, what the tag says, open at the start.
const VALVES := [["V1", "RIVER INLET", true], ["V2", "SUMP SUCTION", false], ["V3", "SEWER BYPASS", true]]
const VALVE_Z := [2.9, 3.9, 4.9]
const PIPE_X := 0.55
const WHEEL_X := 0.92
const WHEEL_Y := 1.05
const WHEEL_R := 0.2
const STEM_TRAVEL := 0.13

## Where things are in the pit.
const INLET_AT := Vector3(3.55, -0.6, 6.6)
const DRAIN_AT := Vector3(2.8, FLOOR_Y, 5.95)
const HANDLE_AT := Vector3(2.55, FLOOR_Y + 0.03, 6.25)
## The drowned man lies face down reaching for the handle. His feet are
## far enough (3D, from the floor up there) from anywhere they can stand
## while it's flooded that he can't wake under the water (Zombie possum,
## 2.2 m); he gets up as they come down the steps.
const BODY_AT := Vector3(3.5, FLOOR_Y, 4.5)
const BODY_YAW := 145.0
const GAUGE_AT := Vector3(0.39, 1.45, 5.85)

## Level change per second (1 = full).
const INFLOW := 0.07
const DRAIN := 0.07
const BACKFLOW := 0.05
const TURN_PULLS := 3
const PULL_T := 0.42
const SLIDE_T := 0.14

var level := 1.0          # as the host has it (every phone, synced)
var _shown := 1.0         # what this phone draws, easing toward level
var _open: Array = []
var _busy := [false, false, false]
var _wheels: Array = []
var _pulls: Array = []
var _stems: Array = []
var _grips: Array = []    # [left, right] per valve
var _water: MeshInstance3D
var _water_mat: ShaderMaterial
var _gate: Node3D
var _gate_body: StaticBody3D
var _pointer: Node3D
var _inlet_snd: AudioStreamPlayer3D
var _drain_snd: AudioStreamPlayer3D
var _sent := 0.0
var _belch_t := 0.0
## Host: how long the sump has been in its current way, for the survivors'
## lines (said once per way, not every frame).
var _mode := ""
var _mode_t := 0.0
var _said := {}

static func drained() -> bool:
	return GameState.has_flag(FLAG_DRAINED)

static func valve_open(i: int) -> bool:
	var v = GameState.world_flags.get(VALVE_FLAG % (i + 1), "")
	if v is String and v != "":
		return v == "open"
	return VALVES[i][2]

func _ready() -> void:
	add_to_group("pump_room")
	for i in VALVES.size():
		_open.append(valve_open(i))
	level = 0.0 if drained() else 1.0
	_shown = level
	_build()
	_show_valves(false)
	_refresh_fx(0.0)
	if drained():
		_place_handle.call_deferred()
	if GameState.has_flag(FLAG_GATE):
		_set_gate(true, false)

# ------------------------------------------------------------------ building

func _build() -> void:
	var conc := Mats.surface("sump_wall", {"tile_size": 1.6, "floor_y": FLOOR_Y + position.y, "grime_height": 1.38, "grime_amount": 1.0, "stain_amount": 0.9, "wetness": 0.8, "tint": Color(0.46, 0.46, 0.42)})
	var silt := Mats.surface("undercroft_floor", {"tile_size": 1.4, "floor_y": FLOOR_Y + position.y, "wetness": 1.0, "puddles": 1.0, "grime_amount": 1.0, "tint": Color(0.42, 0.4, 0.34)})
	var x0 := PIT.position.x
	var z0 := PIT.position.y
	var x1 := PIT.end.x
	var z1 := PIT.end.y
	# The pit: four walls under the room's floor slab (which ends at -0.2;
	# the steel nosing covers its cut edge) and a silted floor.
	var cy := (FLOOR_Y - 0.02 - 0.2) / 2.0
	var hgt := -0.2 - (FLOOR_Y - 0.02)
	RoomBuilder._box(self, Vector3(x0 - 0.1, cy, (z0 + z1) / 2), Vector3(0.2, hgt, PIT.size.y + 0.4), conc, true)
	RoomBuilder._box(self, Vector3(x1 + 0.1, cy, (z0 + z1) / 2), Vector3(0.2, hgt, PIT.size.y + 0.4), conc, true)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, cy, z0 - 0.1), Vector3(PIT.size.x, hgt, 0.2), conc, true)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, cy, z1 + 0.1), Vector3(PIT.size.x, hgt, 0.2), conc, true)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, FLOOR_Y - 0.1, (z0 + z1) / 2), Vector3(PIT.size.x, 0.2, PIT.size.y), silt, true)
	# Steel nosing round the lip (it also covers the slab's cut edge).
	var nosing := Mats.trim(Color(0.16, 0.15, 0.14), 0.5, 0.75)
	RoomBuilder._box(self, Vector3(x0 + 0.02, -0.11, (z0 + z1) / 2), Vector3(0.07, 0.24, PIT.size.y + 0.07), nosing, false)
	RoomBuilder._box(self, Vector3(x1 - 0.02, -0.11, (z0 + z1) / 2), Vector3(0.07, 0.24, PIT.size.y + 0.07), nosing, false)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, -0.11, z0 + 0.02), Vector3(PIT.size.x + 0.07, 0.24, 0.07), nosing, false)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, -0.11, z1 - 0.02), Vector3(PIT.size.x + 0.07, 0.24, 0.07), nosing, false)
	_build_stairs(conc)
	_build_railing()
	_build_pit_details()
	_build_water()
	_build_valves()
	_build_board()
	_build_gauge()
	_build_pumps()

## Concrete steps down the east side; a ramp under them is what you walk on
## (smooth on the legs, the navmesh and the bot), set half a step down so the
## feet meet the treads.
func _build_stairs(conc: Material) -> void:
	var run := STAIR.size.y / STEPS
	var rise := -FLOOR_Y / STEPS
	var cx := STAIR.position.x + STAIR.size.x / 2
	var tread := Mats.trim(Color(0.2, 0.19, 0.18), 0.55, 0.6)
	for k in STEPS:
		var top := -rise * (k + 1)
		var zc := STAIR.position.y + run * (k + 0.5)
		RoomBuilder._box(self, Vector3(cx, (FLOOR_Y + top) / 2.0, zc), Vector3(STAIR.size.x, top - FLOOR_Y, run), conc, false)
		RoomBuilder._box(self, Vector3(cx, top + 0.005, STAIR.position.y + run * k + 0.03), Vector3(STAIR.size.x, 0.012, 0.05), tread, false)
	var a := Vector3(cx, -rise / 2.0, STAIR.position.y)
	var b := Vector3(cx, FLOOR_Y - rise / 2.0, STAIR.end.y)
	var along := b - a
	var ang := atan2(-along.y, along.z)
	var sb := StaticBody3D.new()
	sb.name = "SumpSteps"
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(STAIR.size.x, 0.1, along.length() + 0.3)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = (a + b) / 2.0 - Vector3(0, cos(ang), sin(ang)) * 0.05
	sb.rotation.x = ang
	add_child(sb)
	# A pipe handrail down the open (west) side of the steps.
	var rail := Mats.trim(Color(0.62, 0.48, 0.08), 0.5, 0.5)
	var hx := STAIR.position.x + 0.03
	var top_p := Vector3(hx, 0.95, STAIR.position.y + 0.15)
	var bot_p := Vector3(hx, FLOOR_Y + 0.95, STAIR.end.y - 0.1)
	var r := UndercroftKit.bar(self, (top_p + bot_p) / 2.0, 0.022, top_p.distance_to(bot_p), rail, "z", 8)
	r.rotation.x = PI / 2 + atan2(top_p.y - bot_p.y, bot_p.z - top_p.z)
	for f in [0.25, 0.65, 0.95]:
		var p: Vector3 = top_p.lerp(bot_p, f)
		UndercroftKit.bar(self, p - Vector3(0, 0.47, 0), 0.02, 0.94, rail, "y", 8)

## A yellow pipe railing round the lip with a chained gate at the head of the
## steps. It stops people (bars layer: players and infected collide with it,
## the navmesh and bullets don't).
func _build_railing() -> void:
	var paint := Mats.trim(Color(0.66, 0.5, 0.08), 0.55, 0.45)
	var x0 := PIT.position.x - 0.05
	var z0 := PIT.position.y - 0.05
	var x1 := PIT.end.x + 0.05
	var z1 := PIT.end.y + 0.05
	var runs := [
		[Vector3(x0, 0, z0), Vector3(STAIR.position.x, 0, z0)],   # north, up to the gate
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1)],                 # west
		[Vector3(x0, 0, z1), Vector3(x1, 0, z1)],                 # south
		[Vector3(x1, 0, z0), Vector3(x1, 0, z1)],                 # east
	]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var axis := "x" if absf(b.x - a.x) > 0.01 else "z"
		var length := a.distance_to(b)
		var mid := (a + b) / 2.0
		for y in [1.02, 0.55]:
			UndercroftKit.bar(self, mid + Vector3(0, y, 0), 0.025, length, paint, axis, 8)
		var n := maxi(1, int(ceil(length / 1.1)))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			UndercroftKit.bar(self, p + Vector3(0, 0.51, 0), 0.024, 1.02, paint, "y", 8)
			RoomBuilder._box(self, p + Vector3(0, 0.008, 0), Vector3(0.1, 0.016, 0.1), paint, false)
		_bars(mid + Vector3(0, 0.6, 0), Vector3(length if axis == "x" else 0.08, 1.2, length if axis == "z" else 0.08))
	# The gate, hinged on the east post, swinging out (north) to open.
	_gate = Node3D.new()
	_gate.name = "SumpGate"
	_gate.position = Vector3(x1, 0, z0)
	add_child(_gate)
	var w := x1 - STAIR.position.x
	for y in [1.0, 0.55, 0.12]:
		UndercroftKit.bar(_gate, Vector3(-w / 2, y, 0), 0.02, w - 0.04, paint, "x", 8)
	UndercroftKit.bar(_gate, Vector3(-w + 0.03, 0.56, 0), 0.02, 0.9, paint, "y", 8)
	UndercroftKit.bar(_gate, Vector3(-0.03, 0.56, 0), 0.02, 0.9, paint, "y", 8)
	# The chain looped round the north post, and its sign.
	var chain := Mats.trim(Color(0.18, 0.17, 0.16), 0.4, 0.85)
	for i in 6:
		var link := UndercroftKit.bar(_gate, Vector3(-w + 0.02 + (i % 2) * 0.02, 0.98 - i * 0.045, 0.02), 0.012, 0.05, chain, "y", 6)
		link.rotation.z = 0.5 if i % 2 == 0 else -0.5
	var sign := Node3D.new()
	sign.position = Vector3(-w / 2, 0.78, -0.03)
	sign.rotation_degrees.y = 180.0
	_gate.add_child(sign)
	RoomBuilder._box(sign, Vector3(0, 0, 0.005), Vector3(0.42, 0.2, 0.01), Mats.trim(Color(0.82, 0.78, 0.66), 0.6), false)
	UndercroftKit.label(sign, "DANGER\nDEEP WATER  -  NO ENTRY", Vector3(0, 0, 0.012), 26, Color(0.62, 0.1, 0.06), 0.0, 0.0011)
	_gate_body = StaticBody3D.new()
	_gate_body.collision_layer = Door.BARS_LAYER
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 1.2, 0.1)
	cs.shape = bs
	cs.position = Vector3(-w / 2, 0.6, 0)
	_gate_body.add_child(cs)
	_gate.add_child(_gate_body)
	UndercroftKit.reach(self, self, Vector3(x1 - w / 2, 1.0, z0 - 0.3), Vector3(w + 0.2, 1.4, 0.5), 3)

func _bars(center: Vector3, ext: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Door.BARS_LAYER
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = ext
	cs.shape = bs
	sb.add_child(cs)
	sb.position = center
	add_child(sb)

## The inlet's mouth in the south wall, the drain grating in the floor, the
## silt and rubbish the river brought in, and a battery lamp on the pit wall.
func _build_pit_details() -> void:
	var iron := Mats.trim(Color(0.12, 0.1, 0.09), 0.6, 0.7)
	var inlet := UndercroftKit.bar(self, INLET_AT + Vector3(0, 0, -0.08), 0.13, 0.16, iron, "z", 16)
	inlet.name = "InletPipe"
	UndercroftKit.bar(self, INLET_AT + Vector3(0, 0, -0.17), 0.17, 0.03, iron, "z", 16)
	UndercroftKit.bar(self, INLET_AT + Vector3(0, 0, -0.165), 0.11, 0.035, Mats.trim(Color(0.01, 0.01, 0.01), 0.9), "z", 16)
	# Drain: a dark sump-hole under a square grating.
	RoomBuilder._box(self, DRAIN_AT + Vector3(0, 0.005, 0), Vector3(0.56, 0.01, 0.56), Mats.trim(Color(0.01, 0.01, 0.01), 0.95), false)
	RoomBuilder._box(self, DRAIN_AT + Vector3(0, 0.02, 0), Vector3(0.52, 0.025, 0.52), Mats.surface("grate", {"tile_size": 0.5, "grime_amount": 0.8}), false)
	UndercroftKit.label(self, "SEWER", DRAIN_AT + Vector3(0, 0.035, 0.32), 22, Color(0.5, 0.48, 0.42), 0.0, 0.0012).rotation_degrees.x = -90.0
	# The scum line where the water has stood for weeks, round all four walls.
	var scum := Mats.trim(Color(0.07, 0.065, 0.05), 0.3)
	var x0 := PIT.position.x
	var z0 := PIT.position.y
	var x1 := PIT.end.x
	var z1 := PIT.end.y
	var ty := FULL_Y - 0.05
	RoomBuilder._box(self, Vector3(x0 + 0.004, ty, (z0 + z1) / 2), Vector3(0.006, 0.09, PIT.size.y - 0.01), scum, false)
	RoomBuilder._box(self, Vector3(x1 - 0.004, ty, (z0 + z1) / 2), Vector3(0.006, 0.09, PIT.size.y - 0.01), scum, false)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, ty, z0 + 0.004), Vector3(PIT.size.x - 0.01, 0.09, 0.006), scum, false)
	RoomBuilder._box(self, Vector3((x0 + x1) / 2, ty, z1 - 0.004), Vector3(PIT.size.x - 0.01, 0.09, 0.006), scum, false)
	# What the river left: a drowned crate, a tyre, a boot, a bucket of silt.
	RoomBuilder.prop(self, "wooden_crate_01", Vector3(4.8, FLOOR_Y, 6.15), 30.0, 0.85, true).rotation_degrees.z = 8.0
	RoomBuilder.prop(self, "old_tyre", Vector3(2.7, FLOOR_Y + 0.08, 3.25), 0.0, 1.0, false)
	RoomBuilder.prop(self, "metal_trash_can/metal_trash_can_rust", Vector3(2.45, FLOOR_Y, 4.0), 0.0, 0.9, false).rotation_degrees.x = 80.0
	# A battery lamp under the lip: it glows red through the water, then
	# lights the empty pit.
	var lamp := UndercroftPower.emergency_light(self, Vector3(2.95, -0.55, PIT.position.y + 0.02), 0.0, 0.35, 4.0)
	lamp.name = "SumpLamp"

func _build_water() -> void:
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = PIT.size
	pm.subdivide_width = 8
	pm.subdivide_depth = 10
	_water.mesh = pm
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = preload("res://shaders/sump_water.gdshader")
	_water.material_override = _water_mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.position = Vector3(PIT.get_center().x, FULL_Y, PIT.get_center().y)
	add_child(_water)
	_inlet_snd = Sfx.loop_on("sump_inlet", self, -60.0, 7.0)
	if _inlet_snd:
		_inlet_snd.position = Vector3(INLET_AT.x, 0.0, INLET_AT.z - 0.4)
	_drain_snd = Sfx.loop_on("sump_drain", self, -60.0, 8.0)
	if _drain_snd:
		_drain_snd.position = DRAIN_AT + Vector3(0, 1.0, 0)

## The manifold on the west wall: three cast-iron gate valves on pipes that
## rise out of the floor and turn back into the wall, each with a rising
## stem (out when open), a red handwheel and its brass tag.
func _build_valves() -> void:
	var iron := Mats.surface("flood_steel", {"tile_size": 0.6, "grime_amount": 0.8, "tint": Color(0.36, 0.36, 0.34)})
	var pipe_paint := Mats.surface("flood_steel", {"tile_size": 0.8, "grime_amount": 0.7, "tint": Color(0.42, 0.44, 0.4)})
	var red := Mats.surface("flood_steel", {"tile_size": 0.4, "grime_amount": 0.5, "tint": Color(0.75, 0.16, 0.1)})
	var steel := Mats.trim(Color(0.3, 0.29, 0.27), 0.35, 0.85)
	var brass := Mats.trim(Color(0.62, 0.47, 0.22), 0.35, 0.85)
	for i in VALVES.size():
		var z: float = VALVE_Z[i]
		var v := Node3D.new()
		v.name = "Valve%d" % (i + 1)
		v.position = Vector3(PIPE_X, 0, z)
		add_child(v)
		# Pipe up out of the floor, the valve body, the pipe on up and back
		# into the wall above.
		UndercroftKit.bar(v, Vector3(0, 0.38, 0), 0.075, 0.76, pipe_paint, "y", 14)
		UndercroftKit.bar(v, Vector3(0, 0.03, 0), 0.12, 0.06, iron, "y", 14)
		UndercroftKit.bar(v, Vector3(0, 1.58, 0), 0.075, 0.64, pipe_paint, "y", 14)
		UndercroftKit.bar(v, Vector3(-0.12, 1.92, 0), 0.075, 0.24, pipe_paint, "x", 14)
		UndercroftKit.bar(v, Vector3(-0.02, 1.92, 0), 0.09, 0.07, iron, "y", 14).rotation.z = PI / 2
		for y in [0.78, 1.24]:
			UndercroftKit.bar(v, Vector3(0, y, 0), 0.12, 0.035, iron, "y", 16)
		var body := UndercroftKit.bar(v, Vector3(0, WHEEL_Y, 0), 0.13, 0.44, iron, "y", 16)
		body.name = "Body"
		# The bonnet and yoke out toward the room, the gland, the wheel.
		UndercroftKit.bar(v, Vector3(0.14, WHEEL_Y, 0), 0.075, 0.16, iron, "x", 14)
		UndercroftKit.bar(v, Vector3(0.23, WHEEL_Y, 0), 0.1, 0.03, iron, "x", 14)
		for s in [-1.0, 1.0]:
			RoomBuilder._box(v, Vector3(0.29, WHEEL_Y + s * 0.055, 0), Vector3(0.1, 0.022, 0.03), iron, false)
		var stem := Node3D.new()
		stem.name = "Stem"
		stem.position = Vector3(0, WHEEL_Y, 0)
		v.add_child(stem)
		UndercroftKit.bar(stem, Vector3(0.38, 0, 0), 0.016, 0.42, steel, "x", 8)
		_stems.append(stem)
		var wheel := Node3D.new()
		wheel.name = "Wheel"
		wheel.position = Vector3(WHEEL_X - PIPE_X, WHEEL_Y, 0)
		v.add_child(wheel)
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = WHEEL_R - 0.018
		tm.outer_radius = WHEEL_R + 0.018
		tm.rings = 28
		tm.ring_segments = 10
		rim.mesh = tm
		rim.material_override = red
		rim.rotation.z = PI / 2
		wheel.add_child(rim)
		for k in 4:
			var spoke := UndercroftKit.bar(wheel, Vector3.ZERO, 0.014, WHEEL_R * 2.0, red, "z", 8)
			spoke.rotation = Vector3(PI / 2 + k * PI / 4.0, 0, 0)
		UndercroftKit.bar(wheel, Vector3.ZERO, 0.04, 0.06, red, "x", 12)
		UndercroftKit.bar(wheel, Vector3(0.035, 0, 0), 0.02, 0.02, steel, "x", 8)
		_wheels.append(wheel)
		# Where the hands go, on the near rim, upper left and upper right as
		# she faces it; they ride a node that turns with each pull.
		var pull := Node3D.new()
		pull.position = wheel.position
		v.add_child(pull)
		var gl := Node3D.new()
		gl.position = Vector3(0.03, WHEEL_R * 0.55, WHEEL_R * 0.84)
		pull.add_child(gl)
		var gr := Node3D.new()
		gr.position = Vector3(0.03, WHEEL_R * 0.55, -WHEEL_R * 0.84)
		pull.add_child(gr)
		_pulls.append(pull)
		_grips.append([gl, gr])
		# The brass tag on a short chain from the yoke.
		var tag := Node3D.new()
		tag.position = Vector3(0.27, WHEEL_Y - 0.17, 0.12)
		tag.rotation_degrees.y = 90.0
		v.add_child(tag)
		RoomBuilder._box(tag, Vector3.ZERO, Vector3(0.17, 0.065, 0.006), brass, false)
		UndercroftKit.label(tag, "%s\n%s" % [VALVES[i][0], VALVES[i][1]], Vector3(0, 0, 0.0045), 20, Color(0.16, 0.1, 0.04), 0.0, 0.00085)
		UndercroftKit.bar(tag, Vector3(0, 0.06, 0), 0.004, 0.06, steel, "y", 4)
		# Stencilled big on the wall behind it too.
		UndercroftKit.label(self, VALVES[i][0], Vector3(RoomBuilder.WALL_T * 1.5 + 0.005, 1.68, z + 0.26), 90, Color(0.86, 0.82, 0.68), PI / 2, 0.0016)
		UndercroftKit.reach(self, self, Vector3(WHEEL_X + 0.22, WHEEL_Y, z), Vector3(0.6, 1.0, 0.62), i)

## The enamel pipework board over the valves.
func _build_board() -> void:
	var n := Node3D.new()
	n.name = "SumpBoard"
	n.position = Vector3(RoomBuilder.WALL_T * 1.5 + 0.01, 2.62, 3.9)
	n.rotation_degrees.y = 90.0
	add_child(n)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/undercroft/sump_board.jpg")
	m.roughness = 0.35
	m.metallic_specular = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.1, 1.18)
	q.mesh = qm
	q.material_override = m
	q.position.z = 0.012
	n.add_child(q)
	RoomBuilder._box(n, Vector3(0, 0, 0.004), Vector3(2.16, 1.24, 0.008), Mats.trim(Color(0.1, 0.1, 0.1), 0.5, 0.6), false)

## A float gauge beside the valves: a pointer on a scale from EMPTY to FULL,
## worked by a cable from a float in the sump.
func _build_gauge() -> void:
	var g := Node3D.new()
	g.name = "LevelGauge"
	g.position = GAUGE_AT
	g.rotation_degrees.y = 90.0
	add_child(g)
	var enamel := Mats.trim(Color(0.84, 0.8, 0.68), 0.5)
	var ink := Color(0.1, 0.08, 0.06)
	RoomBuilder._box(g, Vector3(0, 0, 0.02), Vector3(0.26, 1.0, 0.04), Mats.trim(Color(0.14, 0.15, 0.14), 0.5, 0.6), false)
	RoomBuilder._box(g, Vector3(0, 0, 0.042), Vector3(0.2, 0.92, 0.004), enamel, false)
	UndercroftKit.label(g, "SUMP B\nLEVEL", Vector3(0, 0.56, 0.045), 24, Color(0.82, 0.8, 0.7), 0.0, 0.0011)
	for k in 9:
		var y := -0.4 + k * 0.1
		RoomBuilder._box(g, Vector3(-0.05, y, 0.045), Vector3(0.06 if k % 4 == 0 else 0.03, 0.006, 0.002), Mats.trim(ink, 0.6), false)
	UndercroftKit.label(g, "FULL", Vector3(0.04, 0.4, 0.046), 18, ink, 0.0, 0.0011)
	UndercroftKit.label(g, "EMPTY", Vector3(0.04, -0.4, 0.046), 18, ink, 0.0, 0.0011)
	UndercroftKit.label(g, "DANGER", Vector3(0.045, 0.2, 0.046), 16, Color(0.6, 0.1, 0.05), 0.0, 0.0011)
	_pointer = Node3D.new()
	_pointer.position = Vector3(-0.05, 0.4, 0.05)
	g.add_child(_pointer)
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.05, 0.035, 0.008)
	arrow.mesh = pm
	arrow.rotation.z = -PI / 2
	arrow.material_override = Mats.trim(Color(0.7, 0.08, 0.04), 0.4, 0.3)
	_pointer.add_child(arrow)
	UndercroftKit.bar(g, Vector3(-0.1, -0.75, 0.03), 0.012, 0.5, Mats.trim(Color(0.2, 0.2, 0.2), 0.5, 0.7), "y", 6)

## Sump pumps No.1 and No.2 on the north lip: vertical motors on their
## lantern housings, suction pipes down into the pit, discharge up and away
## east to the outfall. Electric, so dead.
func _build_pumps() -> void:
	var green := Mats.surface("cabinet_paint", {"tile_size": 0.7, "grime_amount": 0.8, "tint": Color(0.52, 0.6, 0.56)})
	var iron := Mats.surface("flood_steel", {"tile_size": 0.6, "grime_amount": 0.8, "tint": Color(0.34, 0.34, 0.32)})
	var dark := Mats.trim(Color(0.07, 0.07, 0.07), 0.6, 0.5)
	var pipe_paint := Mats.surface("flood_steel", {"tile_size": 0.8, "grime_amount": 0.7, "tint": Color(0.42, 0.44, 0.4)})
	for k in 2:
		var p := Node3D.new()
		p.name = "SumpPump%d" % (k + 1)
		p.position = Vector3(2.7 + k * 0.95, 0, 2.1)
		add_child(p)
		RoomBuilder._box(p, Vector3(0, 0.06, 0), Vector3(0.62, 0.12, 0.5), iron, true)
		UndercroftKit.bar(p, Vector3(0, 0.3, 0), 0.15, 0.36, iron, "y", 16)
		# Cast-iron frame with its cooling ribs running up it, end bells,
		# and the fan cowl on top with its grille.
		var motor := UndercroftKit.bar(p, Vector3(0, 0.78, 0), 0.21, 0.6, green, "y", 24)
		motor.name = "Motor"
		for f in 18:
			var a := TAU * f / 18.0
			var rib := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.028, 0.5, 0.05)
			rib.mesh = bm
			rib.material_override = green
			rib.position = Vector3(cos(a) * 0.225, 0.78, sin(a) * 0.225)
			rib.rotation.y = -a
			p.add_child(rib)
		UndercroftKit.bar(p, Vector3(0, 0.5, 0), 0.235, 0.05, green, "y", 24)
		UndercroftKit.bar(p, Vector3(0, 1.07, 0), 0.235, 0.04, green, "y", 24)
		UndercroftKit.bar(p, Vector3(0, 1.16, 0), 0.215, 0.14, green, "y", 24)
		UndercroftKit.bar(p, Vector3(0, 1.235, 0), 0.19, 0.012, dark, "y", 24)
		for g in 4:
			UndercroftKit.bar(p, Vector3(0, 1.243, 0), 0.05 + g * 0.045, 0.006, green, "y", 24)
		# The lifting eye.
		UndercroftKit.bar(p, Vector3(0, 1.28, 0), 0.035, 0.06, iron, "z", 10)
		RoomBuilder._box(p, Vector3(0.26, 0.82, 0), Vector3(0.1, 0.18, 0.16), green, false)
		UndercroftKit.bar(p, Vector3(0.3, 1.4, -0.0), 0.022, 1.0, dark, "y", 6)
		UndercroftKit.label(p, "No. %d" % (k + 1), Vector3(0, 0.82, 0.236), 40, Color(0.86, 0.84, 0.74), 0.0, 0.0012)
		# Suction: out over the lip and down into the water.
		UndercroftKit.bar(p, Vector3(0, 0.2, 0.36), 0.07, 0.42, pipe_paint, "z", 12)
		UndercroftKit.bar(p, Vector3(0, -0.6, 0.62), 0.07, 1.6, pipe_paint, "y", 12)
		UndercroftKit.bar(p, Vector3(0, -1.38, 0.62), 0.11, 0.1, iron, "y", 12)
		# Discharge: up the wall and away east under the ceiling.
		UndercroftKit.bar(p, Vector3(0, 0.3, -0.24), 0.07, 0.2, pipe_paint, "z", 12)
		UndercroftKit.bar(p, Vector3(0, 2.0, -0.34), 0.07, 3.4, pipe_paint, "y", 12)
	UndercroftKit.bar(self, Vector3(4.12, 3.7, 1.76), 0.08, 3.0, pipe_paint, "x", 12)
	UndercroftKit.label(self, "PUMPS ON MAINS ONLY", Vector3(3.17, 2.3, 0.39), 34, Color(0.8, 0.2, 0.1), 0.0, 0.0018)

# ------------------------------------------------------------------ using it

func interact_text(_player: Node, handle := -1) -> String:
	if handle >= 0 and handle < VALVES.size():
		if drained() or _busy[handle]:
			return ""
		var v: Array = VALVES[handle]
		return "%s valve %s (%s)" % ["Shut" if _open[handle] else "Open", v[0], String(v[1]).to_lower()]
	if handle == 3:
		if GameState.has_flag(FLAG_GATE):
			return ""
		return "Unhook the sump gate" if drained() else "Check the sump gate"
	return ""

func interact(player: Node, handle := -1) -> void:
	if handle >= 0 and handle < VALVES.size():
		if not drained() and not _busy[handle]:
			_rpc_turn_request.rpc_id(1, handle, player.peer_id)
		return
	if handle == 3 and not GameState.has_flag(FLAG_GATE):
		if drained():
			_rpc_gate_request.rpc_id(1)
		else:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("Chained shut. Nobody goes down there while it holds water.")

@rpc("any_peer", "reliable", "call_local")
func _rpc_turn_request(i: int, by_peer: int) -> void:
	if not multiplayer.is_server() or drained() or _busy[i]:
		return
	_rpc_turn.rpc(i, by_peer, not _open[i])

## Every phone: she stands at the wheel, the gun goes away, and her hands
## pull it round three times; the stem winds out (or in). The host flips the
## valve when the wheel stops.
@rpc("authority", "reliable", "call_local")
func _rpc_turn(i: int, by_peer: int, to_open: bool) -> void:
	_busy[i] = true
	var who: Node = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == by_peer:
			who = p
	var wheel: Node3D = _wheels[i]
	if who:
		if who.is_multiplayer_authority():
			who.global_position = to_global(Vector3(WHEEL_X + 0.46, 0.0, VALVE_Z[i]))
			who.velocity = Vector3.ZERO
			who.model.play("idle", false)
			who.start_work("valve", atan2(-(-global_basis.x).x, -(-global_basis.x).z))
		who.model.hands_on(_grips[i][0], _grips[i][1])
	Sfx.play_at("valve_turn", wheel.global_position, "metal_bang", -2.0, 6.0)
	var sign := 1.0 if to_open else -1.0
	var stem: Node3D = _stems[i]
	var st := create_tween()
	st.tween_property(stem, "position:x", STEM_TRAVEL if to_open else 0.0, TURN_PULLS * (PULL_T + SLIDE_T)).set_trans(Tween.TRANS_SINE)
	for k in TURN_PULLS:
		var t := create_tween().set_parallel()
		t.tween_property(wheel, "rotation:x", wheel.rotation.x + sign * 1.75, PULL_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_pulls[i], "rotation:x", sign * 1.75, PULL_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		var b := create_tween()
		b.tween_property(_pulls[i], "rotation:x", 0.0, SLIDE_T)
		await b.finished
		if k == 1:
			Sfx.play_at("valve_turn", wheel.global_position, "metal_bang", -6.0, 6.0)
	if who and is_instance_valid(who):
		who.model.hands_off()
		if who.is_multiplayer_authority() and who.working == "valve":
			who.stop_work()
	_busy[i] = false
	if multiplayer.is_server() and not drained():
		_rpc_valve.rpc(i, to_open)

@rpc("authority", "reliable", "call_local")
func _rpc_valve(i: int, is_open: bool) -> void:
	_open[i] = is_open
	GameState.set_flag(VALVE_FLAG % (i + 1), "open" if is_open else "shut")
	_show_valves(false)
	Sfx.play_at("breaker_throw", (_wheels[i] as Node3D).global_position, "", -10.0, 4.0)

func _show_valves(_animate: bool) -> void:
	for i in _stems.size():
		if not _busy[i]:
			(_stems[i] as Node3D).position.x = STEM_TRAVEL if _open[i] else 0.0

## Which way the water is going with the valves as they are.
func _rate() -> float:
	if drained():
		return 0.0
	var r := 0.0
	if _open[0]:
		r += INFLOW
	if _open[1]:
		r += BACKFLOW if _open[2] else -DRAIN
	return r

func _way() -> String:
	if drained():
		return "dry"
	if _open[1] and _open[2]:
		return "backflow"
	if _open[1] and _open[0]:
		return "holding"
	if _open[1]:
		return "draining"
	return "still"

func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not drained():
		var before := level
		level = clampf(level + _rate() * delta, 0.0, 1.0)
		_sent += delta
		if _sent > 0.25 and before != level:
			_sent = 0.0
			_rpc_level.rpc(level)
		_tick_lines(delta)
		if level <= 0.0:
			_rpc_drained.rpc()
	_refresh_fx(delta)

## The survivors say what the water is doing, once each time it starts.
func _tick_lines(delta: float) -> void:
	var way := _way()
	if way != _mode:
		_mode = way
		_mode_t = 0.0
	_mode_t += delta
	var wait := {"backflow": 2.5, "holding": 3.5, "draining": 2.0}
	if wait.has(way) and _mode_t > wait[way] and not _said.get(way, false):
		_said[way] = true
		get_tree().call_group("story", "pump_line", way)
	if way == "still" or way == "dry":
		# Said again next time it happens.
		_said.erase("backflow")
		_said.erase("holding")

@rpc("authority", "unreliable_ordered", "call_local")
func _rpc_level(l: float) -> void:
	if not drained():
		level = l

func _refresh_fx(delta: float) -> void:
	_shown = move_toward(_shown, level, maxf(delta * 0.12, absf(level - _shown) * delta * 2.0)) if delta > 0.0 else level
	var y := lerpf(EMPTY_Y, FULL_Y, _shown)
	_water.position.y = y
	_water.visible = _shown > 0.003
	var way := _way()
	var churn := 1.0 if _open[0] and not drained() else 0.0
	var swirl := 1.0 if way == "draining" and _shown > 0.02 else 0.0
	var back := 1.0 if way == "backflow" else 0.0
	_set_param("churn", churn, delta)
	_set_param("swirl", swirl, delta)
	_set_param("backflow", back, delta)
	_water_mat.set_shader_parameter("churn_at", Vector2(global_position.x + INLET_AT.x, global_position.z + INLET_AT.z - 0.45))
	_water_mat.set_shader_parameter("swirl_at", Vector2(global_position.x + DRAIN_AT.x, global_position.z + DRAIN_AT.z))
	if _inlet_snd:
		_inlet_snd.volume_db = move_toward(_inlet_snd.volume_db, -4.0 if churn > 0.0 else -60.0, delta * 30.0)
	if _drain_snd:
		_drain_snd.volume_db = move_toward(_drain_snd.volume_db, -2.0 if swirl > 0.0 else -60.0, delta * 30.0)
	if back > 0.0:
		_belch_t -= delta
		if _belch_t <= 0.0:
			_belch_t = randf_range(1.6, 3.0)
			Sfx.play_at("sump_backflow", global_transform * (DRAIN_AT + Vector3(0, -FLOOR_Y, 0)), "", -4.0, 7.0)
	if _pointer:
		_pointer.position.y = lerpf(-0.4, 0.4, _shown)

var _fx := {}
func _set_param(n: String, target: float, delta: float) -> void:
	var v: float = _fx.get(n, target)
	v = move_toward(v, target, delta * 0.8) if delta > 0.0 else target
	_fx[n] = v
	_water_mat.set_shader_parameter(n, v)

## The last of it goes down the drain: the handle and what's lying with it
## are out of the water.
@rpc("authority", "reliable", "call_local")
func _rpc_drained() -> void:
	if drained():
		return
	GameState.set_flag(FLAG_DRAINED)
	level = 0.0
	Sfx.play_at("sump_empty", global_transform * (DRAIN_AT + Vector3(0, 0.5, 0)), "", 0.0, 10.0)
	_place_handle()
	get_tree().call_group("story", "pump_line", "dry")

func _place_handle() -> void:
	if GameState.has_flag("taken:" + HANDLE_ID) or GeneratorSet.fitted("crank"):
		return
	# A save from before the pump room (the Warden carried the handle then)
	# finds no second one down here.
	if GameState.has_flag(Chapter2Story.OLD_FLOW):
		return
	var level_node := get_tree().get_first_node_in_group("level")
	if level_node and not level_node.has_node("Pickup_" + HANDLE_ID):
		level_node.place_pickup("key:crank_handle", global_transform * HANDLE_AT, HANDLE_ID)

@rpc("any_peer", "reliable", "call_local")
func _rpc_gate_request() -> void:
	if multiplayer.is_server() and drained() and not GameState.has_flag(FLAG_GATE):
		_rpc_gate.rpc()

@rpc("authority", "reliable", "call_local")
func _rpc_gate() -> void:
	GameState.set_flag(FLAG_GATE)
	_set_gate(true, true)

func _set_gate(open: bool, animate: bool) -> void:
	_gate_body.collision_layer = 0 if open else Door.BARS_LAYER
	var to := -100.0 if open else 0.0
	if animate:
		Sfx.play_at("gate_chain", _gate.global_position + Vector3.UP, "metal_bang", 0.0, 6.0)
		create_tween().tween_property(_gate, "rotation_degrees:y", to, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_gate.rotation_degrees.y = to
