class_name GeneratorSet
extends Node3D
## The old diesel generator in the Undercroft's engine hall (chapter 2): the
## way out is behind the flood door, and the flood door needs power.
##
## It needs three things, each a key item someone carries to it: diesel for
## the dry tank (the coal yard's fuel shed), a field fuse for its control
## cabinet (locked in the master clock) and the starting handle (in the
## flooded sump in the pump room, PumpRoom). The cabinet's FUEL, FIELD and
## HANDLE lamps show what's still missing, and the keeper's note left in it
## says where each went.
##
## Then it has to be cranked: one survivor heaves the handle round
## (Player.working "crank", HandsOnGrip keeps both hands on the turning grip)
## while the other keeps the infected off. Every heave builds compression
## (the GENERATOR meter on both phones); the noise brings infected in at
## 15, 40, 65 and 85 percent, from out of sight (the yard, the coal chute, the
## corridor). Let go and the flywheel slows, but never below the last wave
## you held off. At 100 percent it catches: the handle flies off, the engine
## roars, and the Undercroft's lights come on room by room (UndercroftPower).
##
## Local frame: the engine block runs along x with its crank end at -x (the
## cranker stands there facing +x) and the alternator at +x; the origin is on
## the floor under its middle; the cabinet stands on the +z side.
## The host decides everything; every phone shows it.

const LENGTH := 3.04                       # the set on its rails, end to end
const AXLE := Vector3(-1.52, 0.79, 0.0)    # the crankshaft stub on the engine end
const ARM := 0.3                           # crank radius
const SPOT := Vector3(-2.06, 0.0, 0.0)     # where the cranker stands
const FILLER := Vector3(0.24, 1.6, 0.0)    # tank filler cap
const CABINET := Vector3(0.7, 0.0, 1.3)
## The keeper's note in the cabinet's fuse compartment (Undercroft places
## the pickup at NOTE_AT).
const NOTE_ID := "c2_gen_note"
const NOTE_AT := CABINET + Vector3(0.1, 0.13, 0.12)

const PULL := 0.034              # compression one heave adds
const DECAY := 0.006             # lost per second with nobody on the handle
const WAVES := [0.15, 0.4, 0.65, 0.85]
## What comes for them at each wave, and how many.
const WAVE_MIX := [
	["shambler", "shambler", "shambler"],
	["shambler", "runner", "shambler", "crawler"],
	["brute", "shambler", "runner", "shambler", "shambler"],
	["runner", "runner", "shambler", "riot", "shambler"],
]

const PARTS := ["fuel", "fuse", "crank"]
const KEYS := {"fuel": "diesel_can", "fuse": "fuse", "crank": "crank_handle"}
const FLAGS := {"fuel": "c2_fuel_in", "fuse": "c2_fuse_in", "crank": "c2_crank_in"}

## Where infected come in from, set by the level: [{pos, mode}] (mode "drop"
## for down the coal chute, inside it, out of sight).
var entries: Array = []

var progress := 0.0
var _floor := 0.0
var _waves_done := 0
var _sent := 0.0
var _model: Node3D
var _crank: Node3D
var _grip_l: Node3D
var _grip_r: Node3D
var _lamps := {}
var _fuse_vis: Node3D
var _can: Node3D
var _run_snd: AudioStreamPlayer3D
var _exhaust: Node3D
var _cranker: Node = null
var _angle := 0.0
var _last_t := -1.0
var _shake_t := 0.0
var _spawned := 0

## Hand height over the cranking clip (combat/crank, 0.1 s steps), from the
## rig: low in the squat, highest at 1.1 s at the top of the heave.
const HEAVE := [0.42, 0.44, 0.47, 0.51, 0.58, 0.68, 0.82, 1.02, 1.24, 1.45, 1.61, 1.68, 1.67,
	1.62, 1.54, 1.39, 1.18, 0.98, 0.81, 0.68, 0.62, 0.58, 0.55, 0.52, 0.49, 0.46, 0.43]
const HEAVE_TOP := 1.1

static func running() -> bool:
	return GameState.has_flag(UndercroftPower.FLAG)

static func fitted(part: String) -> bool:
	return GameState.has_flag(FLAGS[part])

static func ready_to_crank() -> bool:
	return fitted("fuel") and fitted("fuse") and fitted("crank")

func _ready() -> void:
	add_to_group("generator")
	_build()
	_show_parts()
	if running():
		_set_running(false)

# ------------------------------------------------------------------ the set

func _build() -> void:
	_model = UndercroftKit.meshy(self, "generator", Vector3.ZERO, 0.0, LENGTH, true)
	var iron := Mats.trim(Color(0.13, 0.13, 0.12), 0.55, 0.75)
	var oily := Mats.trim(Color(0.07, 0.07, 0.065), 0.35, 0.6)
	var conc := Mats.trim(Color(0.32, 0.31, 0.29), 0.9, 0.0)
	# A raised concrete plinth with an oil-black drip tray under the engine.
	RoomBuilder._box(self, Vector3(0, -0.04, 0), Vector3(LENGTH + 0.6, 0.12, 1.5), conc, false)
	RoomBuilder._box(self, Vector3(-0.7, 0.025, 0), Vector3(1.2, 0.01, 0.8), oily, false)
	# The exhaust: a lagged pipe from the engine up into the vault.
	UndercroftKit.bar(self, Vector3(-0.55, 1.75, -0.32), 0.07, 0.35, iron)
	var up := UndercroftKit.bar(self, Vector3(-0.55, 4.1, -0.32), 0.09, 4.4, Mats.trim(Color(0.42, 0.4, 0.36), 0.85, 0.0))
	up.name = "Exhaust"
	_exhaust = Node3D.new()
	_exhaust.position = Vector3(-0.55, 1.95, -0.32)
	add_child(_exhaust)
	# The starting handle on its stub (shown once fitted). It turns about x.
	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = AXLE
	add_child(_crank)
	var steel := Mats.trim(Color(0.2, 0.19, 0.18), 0.4, 0.85)
	var wood := Mats.trim(Color(0.55, 0.43, 0.3), 0.7, 0.0)
	UndercroftKit.bar(_crank, Vector3(-0.05, 0, 0), 0.045, 0.1, steel, "x")
	RoomBuilder._box(_crank, Vector3(-0.1, -ARM / 2, 0), Vector3(0.035, ARM + 0.07, 0.055), steel, false)
	UndercroftKit.bar(_crank, Vector3(-0.115, -ARM, 0), 0.02, 0.04, steel, "x")
	UndercroftKit.bar(_crank, Vector3(-0.25, -ARM, 0), 0.03, 0.24, wood, "x")
	UndercroftKit.bar(_crank, Vector3(-0.375, -ARM, 0), 0.034, 0.02, steel, "x")
	# Where the wrists go: right hand by the arm, left further out.
	_grip_r = Node3D.new()
	_grip_r.position = Vector3(-0.18, -ARM, 0.0)
	_crank.add_child(_grip_r)
	_grip_l = Node3D.new()
	_grip_l.position = Vector3(-0.31, -ARM, 0.0)
	_crank.add_child(_grip_l)
	_build_cabinet()
	# Reach areas: the filler, the cabinet, the crank end.
	UndercroftKit.reach(self, self, Vector3(0.2, 1.0, 0.8), Vector3(1.2, 1.6, 0.7), 0)
	UndercroftKit.reach(self, self, CABINET + Vector3(0, 1.0, CAB_D / 2 + 0.25), Vector3(0.9, 1.6, 0.5), 1)
	UndercroftKit.reach(self, self, Vector3(-2.0, 0.9, 0), Vector3(0.9, 1.6, 1.3), 2)

## The alternator control cubicle: a floor-standing steel cabinet in
## chipped green paint (Poly Haven green_metal_rust), Rothwell's 1958 fit-out.
## Up top the instrument panel: three moving-iron meters (volts, amperes,
## frequency; dead until it runs, then on 415 V and 50 Hz with the current
## swinging), four indicator lamps (FUEL, FIELD, HANDLE red until each part is
## in, RUNNING), the excitation and governor switches and the hours counter.
## Below, the fuse compartment, its louvred door hanging open: a galvanised
## mounting plate with the porcelain field fuse base (empty clips until the
## fuse goes in), copper busbars on their insulators, the field contactor,
## a terminal rail and the cable looms. The main breaker's lever on its side.
const CAB_W := 0.8
const CAB_D := 0.45
const CAB_H := 1.85
## The meters: pivot height, value range, value when running, and where they
## sit (x) on the panel. The faces are tools/undercroft/make_gen_dials.py.
const DIALS := [[-0.25, 0.0, 500.0, 415.0], [0.0, 0.0, 300.0, 160.0], [0.25, 45.0, 55.0, 50.0]]
const DIAL_Y := 1.56
const DIAL_SIZE := 0.17
var _needles: Array = []
var _breaker: Node3D

func _build_cabinet() -> void:
	var c := Node3D.new()
	c.name = "Cabinet"
	c.position = CABINET
	add_child(c)
	var paint := Mats.surface("cabinet_paint", {"tile_size": 0.9, "grime_amount": 0.75, "grime_height": 0.5, "stain_amount": 0.4, "variation": 0.25})
	var paint_door := Mats.surface("cabinet_paint", {"tile_size": 0.7, "grime_amount": 0.5, "variation": 0.3, "tint": Color(0.92, 0.95, 0.92)})
	var dark := Mats.trim(Color(0.035, 0.035, 0.035), 0.75, 0.2)
	var zinc := Mats.surface("flood_steel", {"tile_size": 0.5, "grime_amount": 0.4, "tint": Color(0.62, 0.62, 0.6)})
	var chrome := Mats.trim(Color(0.6, 0.6, 0.58), 0.25, 1.0)
	var brass := Mats.trim(Color(0.62, 0.48, 0.24), 0.35, 0.9)
	var copper := Mats.trim(Color(0.72, 0.38, 0.22), 0.3, 0.95)
	var porcelain := Mats.trim(Color(0.86, 0.84, 0.78), 0.2, 0.0)
	var bakelite := Mats.trim(Color(0.05, 0.035, 0.03), 0.3, 0.0)
	var ink := Color(0.86, 0.82, 0.7)
	var w := CAB_W
	var d := CAB_D
	var h := CAB_H
	var fz := d / 2.0   # the front face
	# One collider for the lot; the shell is panels so the open compartment
	# has an inside.
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, d)
	cs.shape = bs
	cs.position = Vector3(0, h / 2, 0)
	sb.add_child(cs)
	c.add_child(sb)
	RoomBuilder._box(c, Vector3(0, 0.04, -0.01), Vector3(w - 0.04, 0.08, d - 0.04), dark, false)
	RoomBuilder._box(c, Vector3(0, (h + 0.08) / 2, -fz + 0.01), Vector3(w, h - 0.08, 0.02), paint, false)
	for sx in [-1.0, 1.0]:
		RoomBuilder._box(c, Vector3(sx * (w / 2 - 0.01), (h + 0.08) / 2, 0), Vector3(0.02, h - 0.08, d), paint, false)
	RoomBuilder._box(c, Vector3(0, h + 0.015, 0.005), Vector3(w + 0.03, 0.03, d + 0.03), paint, false)
	RoomBuilder._box(c, Vector3(0, 1.16, 0), Vector3(w - 0.04, 0.025, d - 0.04), paint, false)
	RoomBuilder._box(c, Vector3(0, 0.09, 0), Vector3(w - 0.04, 0.02, d - 0.04), paint, false)
	# ---- the instrument panel
	RoomBuilder._box(c, Vector3(0, 1.51, fz - 0.01), Vector3(w - 0.04, 0.69, 0.02), paint, false)
	for corner in [Vector2(-0.36, 1.82), Vector2(0.36, 1.82), Vector2(-0.36, 1.2), Vector2(0.36, 1.2)]:
		UndercroftKit.bar(c, Vector3(corner.x, corner.y, fz + 0.002), 0.009, 0.008, chrome, "z", 8)
	_plate(c, "ROTHWELL  &  SONS   -   ALTERNATOR  CONTROL", Vector3(0, 1.78, fz + 0.003), Vector2(0.56, 0.045), 18)
	var dial_mat := StandardMaterial3D.new()
	dial_mat.albedo_texture = load("res://assets/textures/undercroft/gen_dials.png")
	dial_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	dial_mat.alpha_scissor_threshold = 0.5
	dial_mat.roughness = 0.55
	dial_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for i in DIALS.size():
		var x: float = DIALS[i][0]
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(DIAL_SIZE, DIAL_SIZE)
		face.mesh = q
		var m: StandardMaterial3D = dial_mat.duplicate()
		m.uv1_scale = Vector3(1.0 / 3.0, 1, 1)
		m.uv1_offset = Vector3(i / 3.0, 0, 0)
		face.material_override = m
		face.position = Vector3(x, DIAL_Y, fz + 0.0065)
		c.add_child(face)
		# A black square case behind the round chrome bezel, the way panel
		# meters were mounted.
		RoomBuilder._box(c, Vector3(x, DIAL_Y, fz + 0.002), Vector3(DIAL_SIZE + 0.03, DIAL_SIZE + 0.03, 0.006), bakelite, false)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = DIAL_SIZE / 2 - 0.006
		tm.outer_radius = DIAL_SIZE / 2 + 0.008
		tm.rings = 32
		ring.mesh = tm
		ring.material_override = chrome
		ring.rotation.x = PI / 2
		ring.position = Vector3(x, DIAL_Y, fz + 0.009)
		c.add_child(ring)
		# The needle turns about the pivot low on the face (256, 400 of 512).
		var pivot := Node3D.new()
		pivot.position = Vector3(x, DIAL_Y - DIAL_SIZE * (400.0 - 256.0) / 512.0, fz + 0.0105)
		c.add_child(pivot)
		var needle := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.0022, DIAL_SIZE * 0.56, 0.001)
		needle.mesh = nm
		needle.material_override = Mats.trim(Color(0.04, 0.03, 0.03), 0.5, 0.2)
		needle.position = Vector3(0, DIAL_SIZE * 0.28, 0)
		pivot.add_child(needle)
		_needles.append(pivot)
	_point_needles(0.0, false)
	# The indicator lamps.
	var names := {"fuel": "FUEL", "fuse": "FIELD", "crank": "HANDLE", "run": "RUNNING"}
	var i := 0
	for part in ["fuel", "fuse", "crank", "run"]:
		var x := -0.27 + i * 0.18
		var bezel := MeshInstance3D.new()
		var bt := TorusMesh.new()
		bt.inner_radius = 0.016
		bt.outer_radius = 0.026
		bezel.mesh = bt
		bezel.material_override = chrome
		bezel.rotation.x = PI / 2
		bezel.position = Vector3(x, 1.37, fz + 0.004)
		c.add_child(bezel)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.019
		sm.height = 0.022
		bulb.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.roughness = 0.15
		bulb.material_override = mat
		bulb.position = Vector3(x, 1.37, fz + 0.006)
		c.add_child(bulb)
		_plate(c, names[part], Vector3(x, 1.325, fz + 0.003), Vector2(0.11, 0.026), 13)
		var glow := OmniLight3D.new()
		glow.omni_range = 0.9
		glow.light_energy = 0.3
		glow.position = Vector3(x, 1.38, fz + 0.15)
		c.add_child(glow)
		_lamps[part] = [mat, glow]
		i += 1
	# Excitation and governor switches either side of the hours counter.
	for sw in [[-0.22, "EXCITATION"], [0.22, "GOVERNOR"]]:
		UndercroftKit.bar(c, Vector3(sw[0], 1.25, fz + 0.008), 0.026, 0.016, bakelite, "z", 16)
		_piece(c, Vector3(sw[0], 1.25, fz + 0.022), Vector3(0.012, 0.05, 0.016), bakelite, Vector3(0, 0, -0.6))
		_plate(c, sw[1], Vector3(sw[0], 1.21, fz + 0.003), Vector2(0.12, 0.022), 12)
	RoomBuilder._box(c, Vector3(0, 1.25, fz + 0.006), Vector3(0.12, 0.045, 0.012), bakelite, false)
	RoomBuilder._box(c, Vector3(0, 1.25, fz + 0.0125), Vector3(0.1, 0.026, 0.002), Mats.trim(Color(0.06, 0.06, 0.06), 0.1, 0.0), false)
	UndercroftKit.label(c, "0 4 1 7 2", Vector3(0, 1.25, fz + 0.0145), 18, Color(0.86, 0.84, 0.78), 0.0, 0.00085)
	_plate(c, "HOURS RUN", Vector3(0, 1.21, fz + 0.003), Vector2(0.09, 0.022), 12)
	# ---- the fuse compartment, its door hanging open
	var plate_mat := Mats.trim(Color(0.4, 0.41, 0.4), 0.55, 0.75)
	RoomBuilder._box(c, Vector3(0, 0.63, -fz + 0.035), Vector3(w - 0.1, 0.98, 0.01), plate_mat, false)
	# The porcelain field fuse base: brass clips either side, the fuse sits
	# across them (shown once fitted).
	var fb := Vector3(-0.15, 0.9, -fz + 0.065)
	RoomBuilder._box(c, fb, Vector3(0.3, 0.09, 0.05), porcelain, false)
	for sx in [-1.0, 1.0]:
		RoomBuilder._box(c, fb + Vector3(sx * 0.09, 0.0, 0.03), Vector3(0.03, 0.065, 0.025), brass, false)
		UndercroftKit.bar(c, fb + Vector3(sx * 0.13, 0.0, 0.03), 0.009, 0.02, brass, "z", 8)
	_plate(c, "FIELD  FUSE   60 A", Vector3(-0.15, 0.99, -fz + 0.042), Vector2(0.2, 0.03), 14)
	_fuse_vis = Node3D.new()
	_fuse_vis.position = fb + Vector3(0, -0.03, 0.045)
	c.add_child(_fuse_vis)
	UndercroftKit.meshy(_fuse_vis, "fuse", Vector3.ZERO, 0.0, 0.2, false)
	_fuse_vis.visible = false
	# Copper busbars on porcelain standoffs, right of the fuse.
	for k in 3:
		var bx := 0.1 + k * 0.08
		RoomBuilder._box(c, Vector3(bx, 0.68, -fz + 0.075), Vector3(0.025, 0.72, 0.006), copper, false)
		for by in [0.4, 0.96]:
			UndercroftKit.bar(c, Vector3(bx, by, -fz + 0.055), 0.012, 0.035, porcelain, "z", 10)
	# The field contactor, a terminal rail and the looms down to the gland.
	RoomBuilder._box(c, Vector3(-0.15, 0.62, -fz + 0.08), Vector3(0.16, 0.2, 0.09), bakelite, false)
	RoomBuilder._box(c, Vector3(-0.15, 0.62, -fz + 0.126), Vector3(0.1, 0.06, 0.004), Mats.trim(Color(0.7, 0.66, 0.56), 0.5), false)
	RoomBuilder._box(c, Vector3(0, 0.3, -fz + 0.05), Vector3(w - 0.16, 0.035, 0.02), zinc, false)
	for k in 12:
		RoomBuilder._box(c, Vector3(-0.3 + k * 0.05, 0.3, -fz + 0.07), Vector3(0.04, 0.05, 0.03), bakelite if k % 4 else Mats.trim(Color(0.6, 0.06, 0.04), 0.4), false)
	for k in 5:
		var cx := -0.28 + k * 0.035
		UndercroftKit.bar(c, Vector3(cx, 0.2, -fz + 0.07 + (k % 2) * 0.02), 0.01, 0.2, dark, "y", 6)
	# The door, swung open on its left hinge: louvres and the danger plate on
	# the outside, the wiring diagram on the inside.
	var door := Node3D.new()
	door.position = Vector3(-w / 2 + 0.01, 0.63, fz)
	door.rotation_degrees.y = -118.0
	c.add_child(door)
	RoomBuilder._box(door, Vector3(w / 2 - 0.02, 0, 0.0), Vector3(w - 0.04, 1.0, 0.02), paint_door, false)
	for k in 6:
		_piece(door, Vector3(w / 2 - 0.02, -0.4 + k * 0.025, 0.012), Vector3(0.36, 0.008, 0.012), paint_door, Vector3(-0.6, 0, 0))
	var danger := Node3D.new()
	danger.position = Vector3(w / 2 - 0.02, 0.22, 0.012)
	door.add_child(danger)
	RoomBuilder._box(danger, Vector3.ZERO, Vector3(0.22, 0.1, 0.003), Mats.trim(Color(0.85, 0.66, 0.08), 0.5), false)
	UndercroftKit.label(danger, "DANGER\n415  VOLTS", Vector3(0, 0, 0.002), 22, Color(0.06, 0.05, 0.04), 0.0, 0.00085)
	UndercroftKit.bar(door, Vector3(w - 0.07, 0.0, 0.02), 0.01, 0.1, chrome, "y", 8)
	var diagram := Node3D.new()
	diagram.position = Vector3(w / 2 - 0.02, 0.1, -0.012)
	diagram.rotation_degrees.y = 180.0
	door.add_child(diagram)
	RoomBuilder._box(diagram, Vector3.ZERO, Vector3(0.4, 0.3, 0.003), Mats.trim(Color(0.78, 0.74, 0.62), 0.6), false)
	UndercroftKit.label(diagram, "No. 2 STANDBY SET\nFIELD CIRCUIT\n\nEXCITER - FUSE F1 60A - FIELD\nCONTACTOR K1 - AVR\n\nISOLATE BEFORE OPENING", Vector3(0, 0, 0.002), 16, Color(0.12, 0.1, 0.08), 0.0, 0.00085)
	# The main breaker on the right side: a cast case and its red lever,
	# down (OFF) until the set runs.
	var brk := Node3D.new()
	brk.position = Vector3(w / 2 + 0.05, 1.05, 0.05)
	c.add_child(brk)
	RoomBuilder._box(brk, Vector3.ZERO, Vector3(0.1, 0.26, 0.22), Mats.surface("flood_steel", {"tile_size": 0.4, "grime_amount": 0.6, "tint": Color(0.3, 0.3, 0.28)}), false)
	_breaker = Node3D.new()
	_breaker.position = Vector3(0.06, 0.0, 0.0)
	brk.add_child(_breaker)
	UndercroftKit.bar(_breaker, Vector3(0.03, 0, 0), 0.03, 0.06, chrome, "x", 12)
	var lever := UndercroftKit.bar(_breaker, Vector3(0.05, -0.1, 0), 0.012, 0.2, chrome, "y", 8)
	lever.name = "Lever"
	UndercroftKit.bar(_breaker, Vector3(0.05, -0.21, 0), 0.022, 0.08, Mats.trim(Color(0.6, 0.06, 0.04), 0.35, 0.1), "y", 12)
	_plate(brk, "MAIN", Vector3(0.0, 0.16, 0.112), Vector2(0.07, 0.022), 12)
	_breaker.rotation.x = 0.0
	# Cable conduit from the cabinet's back into the floor trench and on to
	# the generator.
	UndercroftKit.bar(c, Vector3(0, 0.5, -fz - 0.05), 0.035, 1.0, Mats.trim(Color(0.3, 0.3, 0.28), 0.45, 0.8), "y", 10)
	RoomBuilder._box(c, Vector3(0, 0.02, -0.65), Vector3(0.12, 0.04, 0.85), Mats.trim(Color(0.2, 0.2, 0.19), 0.6, 0.7), false)

## A box turned to an angle (RoomBuilder._box only lays them square).
func _piece(parent: Node3D, at: Vector3, ext: Vector3, mat: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = ext
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi

## An engraved black plate with cream letters.
func _plate(parent: Node3D, text: String, at: Vector3, size: Vector2, px: int) -> void:
	RoomBuilder._box(parent, at, Vector3(size.x, size.y, 0.003), Mats.trim(Color(0.04, 0.04, 0.04), 0.35, 0.2), false)
	UndercroftKit.label(parent, text, at + Vector3(0, 0, 0.002), px, Color(0.86, 0.82, 0.7), 0.0, 0.00085)

## The meters: dead at the pin, or on their running values with a little
## life in them.
func _point_needles(t: float, live: bool) -> void:
	for i in _needles.size():
		var spec: Array = DIALS[i]
		var v: float = spec[1]
		if live:
			v = spec[3]
			match i:
				0: v += sin(t * 1.3) * 4.0 + randf_range(-1.5, 1.5)
				1: v += sin(t * 0.7) * 25.0 + sin(t * 2.9) * 8.0
				2: v += sin(t * 0.9) * 0.15
		var a := deg_to_rad(-50.0 + 100.0 * (v - spec[1]) / (spec[2] - spec[1]))
		(_needles[i] as Node3D).rotation.z = -a

func _show_parts() -> void:
	_crank.visible = fitted("crank") and not running()
	_fuse_vis.visible = fitted("fuse")
	for part in PARTS:
		var on := fitted(part)
		var col := Color(0.25, 1.0, 0.35) if on else Color(1.0, 0.12, 0.06)
		_set_lamp(part, col, 2.5)
	_set_lamp("run", Color(0.25, 1.0, 0.35), 3.0 if running() else 0.0)
	_breaker.rotation.x = -1.1 if running() else 0.0
	if not running():
		_point_needles(0.0, false)
	if fitted("fuel") and _can == null:
		# The empty can left on the plinth.
		_can = RoomBuilder.prop(self, "metal_jerrycan_green", Vector3(0.95, 0.02, 0.85), 25.0, 1.0, false)

func _set_lamp(part: String, col: Color, energy: float) -> void:
	var mat: StandardMaterial3D = _lamps[part][0]
	var glow: OmniLight3D = _lamps[part][1]
	mat.albedo_color = col * (0.3 if energy > 0.0 else 0.12)
	mat.emission = col
	mat.emission_energy_multiplier = energy
	glow.light_color = col
	glow.light_energy = 0.3 if energy > 0.0 else 0.0

# ------------------------------------------------------------------ using it

func interact_text(player: Node, handle := -1) -> String:
	if running():
		return ""
	match handle:
		0:
			if fitted("fuel"):
				return ""
			return "Pour in the diesel" if _has(player, "fuel") else "Check the fuel tank"
		1:
			if fitted("fuse"):
				return ""
			return "Fit the fuse" if _has(player, "fuse") else "Check the control box"
		2:
			if not fitted("crank"):
				return "Fit the starting handle" if _has(player, "crank") else "Check the crank"
			if _cranker != null:
				return ""
			return "Crank the engine" if ready_to_crank() else "Check the engine"
	return ""

func interact(player: Node, handle := -1) -> void:
	if running():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	match handle:
		0:
			if _has(player, "fuel"):
				_rpc_fit.rpc_id(1, "fuel", player.peer_id)
			elif hud:
				hud.toast("The tank is bone dry. It needs diesel.")
		1:
			if _has(player, "fuse"):
				_rpc_fit.rpc_id(1, "fuse", player.peer_id)
			elif hud:
				hud.toast("The field fuse has been pulled. The clips are empty." + _note_hint())
		2:
			if not fitted("crank"):
				if _has(player, "crank"):
					_rpc_fit.rpc_id(1, "crank", player.peer_id)
				elif hud:
					hud.toast("No starting handle. The crank stub is bare." + _note_hint())
			elif not ready_to_crank():
				if hud:
					var need: Array = []
					if not fitted("fuel"):
						need.append("diesel")
					if not fitted("fuse"):
						need.append("a fuse")
					hud.toast("It won't start without %s." % " and ".join(need))
			elif _cranker == null:
				_start_cranking(player)

## Points at the keeper's note in the cabinet until somebody has read it.
func _note_hint() -> String:
	return "" if GameState.has_flag("taken:" + NOTE_ID) else " There's a note tucked in the control cabinet."

func _has(player: Node, part: String) -> bool:
	return Cheats.on("unlock_doors") or player.inventory.key_items.has(KEYS[part])

@rpc("any_peer", "reliable", "call_local")
func _rpc_fit(part: String, by_peer: int) -> void:
	if not multiplayer.is_server() or fitted(part):
		return
	_rpc_fitted.rpc(part, by_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_fitted(part: String, by_peer: int) -> void:
	GameState.set_flag(FLAGS[part])
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == by_peer and p.is_multiplayer_authority():
			p.inventory.remove_key(KEYS[part])
	match part:
		"fuel":
			Sfx.play_at("fuel_pour", global_transform * FILLER, "", 0.0, 6.0)
			_pour_can()
		"fuse":
			Sfx.play_at("fuse_clip", global_transform * (CABINET + Vector3(0, 1.1, 0.1)), "breaker_throw", -2.0, 5.0)
		"crank":
			Sfx.play_at("crank_fit", global_transform * AXLE, "breaker_throw", -2.0, 5.0)
	_show_parts()
	get_tree().call_group("story", "generator_changed", part)

## The can tipped over the filler for a few seconds, then left on the plinth.
func _pour_can() -> void:
	var can := RoomBuilder.prop(self, "metal_jerrycan_green", FILLER + Vector3(0.1, 0.12, 0.25), 90.0, 1.0, false)
	can.rotation_degrees.x = -10
	var t := create_tween()
	t.tween_property(can, "rotation_degrees:x", -120.0, 0.6)
	t.tween_interval(2.0)
	t.tween_property(can, "rotation_degrees:x", -10.0, 0.5)
	t.tween_callback(can.queue_free)
	t.tween_callback(_show_parts)

# ------------------------------------------------------------------ cranking

func _start_cranking(player: Node) -> void:
	var dir := global_basis.x
	player.global_position = global_transform * SPOT
	player.start_work("crank", atan2(-dir.x, -dir.z))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Heave! Move to let go.")

## Who has the handle, as this phone sees it.
func _find_cranker() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		var w: String = p.working if p.is_multiplayer_authority() else p.sync_anim
		if w == "crank" and p.global_position.distance_to(global_transform * SPOT) < 1.2:
			return p
	return null

func _process(delta: float) -> void:
	if running():
		_tick_running(delta)
		return
	var c := _find_cranker()
	if c != _cranker:
		if _cranker != null and is_instance_valid(_cranker):
			_cranker.model.hands_off()
		_cranker = c
		_last_t = -1.0
		if c != null:
			c.model.hands_on(_grip_l, _grip_r)
	if _cranker != null:
		var t: float = _cranker.model.clip_time() if _cranker.model.current_clip() == "combat/crank" else 0.0
		_angle = _heave_angle(t)
		# Each full heave on the cranker's own phone counts once, on the host.
		if _cranker.is_multiplayer_authority():
			if _last_t >= 0.0 and t + 1.0 < _last_t:
				_rpc_pull.rpc_id(1)
			_last_t = t
	else:
		# Let go: the handle swings back down under its own weight.
		_angle = lerp_angle(_angle, 0.0, 1.0 - exp(-3.0 * delta))
	_crank.rotation.x = -_angle
	if multiplayer.is_server():
		_tick_host(delta)

## Where the handle is for a moment of the heave: following the hands up one
## side, carried on round the other by the flywheel as they come back down.
func _heave_angle(t: float) -> float:
	var f := clampf(t / 0.1, 0.0, HEAVE.size() - 1.001)
	var i := int(f)
	var h: float = lerpf(HEAVE[i], HEAVE[i + 1], f - i)
	var u := clampf((h - 0.42) / (1.68 - 0.42), 0.0, 1.0)
	var a := acos(1.0 - 2.0 * u)
	return a if t <= HEAVE_TOP else TAU - a

@rpc("any_peer", "reliable", "call_local")
func _rpc_pull() -> void:
	if not multiplayer.is_server() or running():
		return
	progress = minf(progress + PULL, 1.0)
	_rpc_heave.rpc(progress)
	while _waves_done < WAVES.size() and progress >= WAVES[_waves_done]:
		_floor = WAVES[_waves_done]
		_send_wave(_waves_done)
		_waves_done += 1
	if progress >= 1.0:
		_rpc_started.rpc()

## Every phone: the engine coughs a little harder with each heave.
@rpc("authority", "reliable", "call_local")
func _rpc_heave(p: float) -> void:
	progress = p
	var at := global_transform * AXLE
	Sfx.play_at("engine_cough", at, "metal_bang", lerpf(-8.0, 2.0, p), 10.0)
	_shake_t = 0.25 + p * 0.3
	Effects.exhaust(_exhaust.global_position, 0.4 + p * 1.2)
	_meter(p)

func _meter(p: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_meter"):
		if p >= 1.0:
			hud.hide_meter("generator")
		else:
			hud.show_meter("generator", "GENERATOR", p, Color(0.85, 0.55, 0.12))

func _tick_host(delta: float) -> void:
	if _cranker == null and progress > _floor:
		progress = maxf(progress - DECAY * delta, _floor)
		_sent += delta
		if _sent > 0.5:
			_sent = 0.0
			_rpc_meter.rpc(progress)

@rpc("authority", "unreliable", "call_local")
func _rpc_meter(p: float) -> void:
	progress = p
	_meter(p)

## Infected drawn by the noise, from wherever no one is looking.
func _send_wave(i: int) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level == null or entries.is_empty():
		return
	Music.force_action(45.0)
	get_tree().call_group("story", "generator_wave", i)
	var mix: Array = WAVE_MIX[i]
	for k in mix.size():
		_spawned += 1
		_spawn_later(level, "Z_crank_%d" % _spawned, mix[k], 0.6 + k * 1.4)

## An entry nobody can see right now (the chute's inside counts: it is
## boxed in), a different one each time where there's a choice.
func _hidden_entry() -> Dictionary:
	var spots := entries.duplicate()
	spots.shuffle()
	for e in spots:
		if UndercroftKit.out_of_sight(get_tree(), e["pos"]):
			return e
	for e in spots:
		if e.get("mode", "") == "drop":
			return e
	return {}

## Each one is placed when its turn comes, from wherever is out of sight
## then (the survivors move about while a wave comes in).
func _spawn_later(level: Node, id: String, variant: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var e := _hidden_entry()
	if e.is_empty():
		await get_tree().create_timer(1.0).timeout
		e = _hidden_entry()
		if e.is_empty():
			return
	var mode: String = e.get("mode", "")
	var pos: Vector3 = e["pos"]
	if mode != "drop":
		var j: Vector3 = pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		if UndercroftKit.out_of_sight(get_tree(), j):
			pos = j
	if mode == "drop":
		# Anywhere in the shaft, so they don't all land on one spot.
		pos += Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		_rpc_chute.rpc(pos)
		await get_tree().create_timer(0.5).timeout
	level.spawn_zombie_synced.rpc(id, pos, variant, mode)

## Coal and dust spill from the chute just before something comes down it.
@rpc("authority", "reliable", "call_local")
func _rpc_chute(pos: Vector3) -> void:
	Sfx.play_at("chute_rumble", pos, "ceiling_break", 2.0, 14.0)
	Effects.plaster_fall(pos + Vector3.DOWN * 0.8, 0.8)

# ------------------------------------------------------------------ running

@rpc("authority", "reliable", "call_local")
func _rpc_started() -> void:
	if running():
		return
	GameState.set_flag(UndercroftPower.FLAG)
	progress = 1.0
	_meter(1.0)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority() and p.working == "crank":
			p.stop_work()
	if _cranker != null and is_instance_valid(_cranker):
		_cranker.model.hands_off()
	_cranker = null
	_set_running(true)
	# The lights down the tunnels and the flood door's motor.
	get_tree().call_group("undercroft_power", "set_powered", true, true)
	get_tree().call_group("story", "generator_changed", "running")

func _set_running(animate: bool) -> void:
	_show_parts()
	if animate:
		# It catches: the handle spins with the shaft, is thrown off its stub
		# and clatters on the plinth; the engine roars, then settles.
		_crank.visible = true
		Sfx.play_at("engine_start", global_transform * AXLE, "explosion", 4.0, 18.0)
		var t := create_tween()
		t.tween_property(_crank, "rotation:x", _crank.rotation.x - TAU * 3.0, 0.7).set_ease(Tween.EASE_IN)
		t.tween_property(_crank, "position", AXLE + Vector3(-0.6, -0.68, 0.45), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(_crank, "rotation", Vector3(-PI * 0.5, 0.7, 0.3), 0.35)
		t.tween_callback(func(): Sfx.play_at("crank_clatter", _crank.global_position, "metal_bang", 0.0, 6.0))
		_shake_t = 2.5
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 14.0 and p.has_method("shake"):
				p.shake(0.5)
	else:
		_crank.visible = true
		_crank.position = AXLE + Vector3(-0.6, -0.68, 0.45)
		_crank.rotation = Vector3(-PI * 0.5, 0.7, 0.3)
	if _run_snd == null:
		_run_snd = Sfx.loop_on("engine_run", self, -4.0, 9.0)
		if _run_snd:
			_run_snd.position = Vector3(0, 1.0, 0)

func _tick_running(delta: float) -> void:
	_point_needles(Time.get_ticks_msec() / 1000.0, true)
	# The whole set judders on its mounts.
	_shake_t = maxf(_shake_t - delta, 0.0)
	var amp := 0.004 + _shake_t * 0.006
	_model.position = Vector3(randf_range(-amp, amp), randf_range(0.0, amp), randf_range(-amp, amp))
	_sent += delta
	if _sent > 0.7:
		_sent = 0.0
		Effects.exhaust(_exhaust.global_position, 0.25)   # the manifold leaks
