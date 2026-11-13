class_name GeneratorSet
extends Node3D
## The old diesel generator in the Undercroft's engine hall (chapter 2): the
## way out is behind the flood door, and the flood door needs power.
##
## It needs three things, each a key item someone carries to it: diesel for
## the dry tank (the coal yard's fuel shed), a field fuse for its control
## cabinet (locked in the master clock) and the starting handle (on the
## Warden's belt). The cabinet's three lamps show what's still missing.
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
	UndercroftKit.reach(self, self, CABINET + Vector3(0, 1.1, 0.25), Vector3(0.8, 1.4, 0.6), 1)
	UndercroftKit.reach(self, self, Vector3(-2.0, 0.9, 0), Vector3(0.9, 1.6, 1.3), 2)

## The control cabinet on a stand: a steel case with its door hanging open,
## the empty fuse clips inside, and three lamps across the top (FUEL, FIELD,
## START) that turn from red to green as each part goes in.
func _build_cabinet() -> void:
	var c := Node3D.new()
	c.name = "Cabinet"
	c.position = CABINET
	add_child(c)
	var paint := Mats.trim(Color(0.17, 0.22, 0.19), 0.6, 0.45)
	var dark := Mats.trim(Color(0.06, 0.06, 0.06), 0.8, 0.3)
	var steel := Mats.trim(Color(0.36, 0.35, 0.33), 0.45, 0.8)
	var enamel := Mats.trim(Color(0.8, 0.76, 0.64), 0.55, 0.0)
	# Legs and case.
	for x in [-0.28, 0.28]:
		RoomBuilder._box(c, Vector3(x, 0.4, -0.05), Vector3(0.05, 0.8, 0.05), steel, false)
	RoomBuilder._box(c, Vector3(0, 1.15, -0.05), Vector3(0.66, 0.72, 0.28), paint, true)
	RoomBuilder._box(c, Vector3(0, 1.15, 0.092), Vector3(0.58, 0.62, 0.008), dark, false)
	# The door, swung open on its left hinge.
	var door := Node3D.new()
	door.position = Vector3(-0.33, 1.15, 0.1)
	door.rotation_degrees.y = -115
	c.add_child(door)
	RoomBuilder._box(door, Vector3(0.31, 0, 0), Vector3(0.62, 0.68, 0.02), paint, false)
	RoomBuilder._box(door, Vector3(0.31, 0.05, -0.012), Vector3(0.3, 0.2, 0.004), enamel, false)
	# Cable conduit from the case into the generator.
	UndercroftKit.bar(c, Vector3(0, 0.62, -0.16), 0.03, 0.25, steel)
	RoomBuilder._box(c, Vector3(0, 0.5, -0.65), Vector3(0.05, 0.05, 1.0), steel, false)
	# Plate and lettering.
	RoomBuilder._box(c, Vector3(0, 1.62, 0.1), Vector3(0.5, 0.1, 0.01), enamel, false)
	UndercroftKit.label(c, "ALTERNATOR  CONTROL", Vector3(0, 1.62, 0.107), 24, Color(0.25, 0.08, 0.05))
	# The fuse clips: two brass jaws, empty until the fuse goes in.
	var brass := Mats.trim(Color(0.62, 0.48, 0.24), 0.35, 0.9)
	for x in [-0.09, 0.09]:
		RoomBuilder._box(c, Vector3(x, 1.12, 0.07), Vector3(0.03, 0.06, 0.04), brass, false)
	UndercroftKit.label(c, "FIELD FUSE 60A", Vector3(0, 1.03, 0.097), 18, Color(0.75, 0.72, 0.6))
	_fuse_vis = Node3D.new()
	_fuse_vis.position = Vector3(0, 1.12, 0.085)
	c.add_child(_fuse_vis)
	var fz := UndercroftKit.meshy(_fuse_vis, "fuse", Vector3.ZERO, 0.0, 0.2, false)
	fz.rotation_degrees = Vector3(0, 0, 0)
	fz.position.y = -0.03
	_fuse_vis.visible = false
	# The three lamps.
	var names := {"fuel": "FUEL", "fuse": "FIELD", "crank": "START"}
	var i := 0
	for part in PARTS:
		var x := -0.2 + i * 0.2
		RoomBuilder._box(c, Vector3(x, 1.4, 0.095), Vector3(0.07, 0.07, 0.015), steel, false)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.024
		sm.height = 0.03
		bulb.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		bulb.material_override = mat
		bulb.position = Vector3(x, 1.4, 0.108)
		c.add_child(bulb)
		UndercroftKit.label(c, names[part], Vector3(x, 1.33, 0.104), 16, Color(0.75, 0.72, 0.6))
		var glow := OmniLight3D.new()
		glow.omni_range = 0.9
		glow.light_energy = 0.35
		glow.position = Vector3(x, 1.42, 0.25)
		c.add_child(glow)
		_lamps[part] = [mat, glow]
		i += 1

func _show_parts() -> void:
	_crank.visible = fitted("crank") and not running()
	_fuse_vis.visible = fitted("fuse")
	for part in PARTS:
		var on := fitted(part)
		var mat: StandardMaterial3D = _lamps[part][0]
		var glow: OmniLight3D = _lamps[part][1]
		var col := Color(0.25, 1.0, 0.35) if on else Color(1.0, 0.12, 0.06)
		mat.albedo_color = col * 0.3
		mat.emission = col
		mat.emission_energy_multiplier = 2.5
		glow.light_color = col
	if fitted("fuel") and _can == null:
		# The empty can left on the plinth.
		_can = RoomBuilder.prop(self, "metal_jerrycan_green", Vector3(0.95, 0.02, 0.85), 25.0, 1.0, false)

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
				hud.toast("The field fuse has been pulled. The clips are empty.")
		2:
			if not fitted("crank"):
				if _has(player, "crank"):
					_rpc_fit.rpc_id(1, "crank", player.peer_id)
				elif hud:
					hud.toast("No starting handle. The crank stub is bare.")
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
	# The whole set judders on its mounts.
	_shake_t = maxf(_shake_t - delta, 0.0)
	var amp := 0.004 + _shake_t * 0.006
	_model.position = Vector3(randf_range(-amp, amp), randf_range(0.0, amp), randf_range(-amp, amp))
	_sent += delta
	if _sent > 0.7:
		_sent = 0.0
		Effects.exhaust(_exhaust.global_position, 0.25)   # the manifold leaks
