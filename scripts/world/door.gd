class_name Door
extends Node3D
## Door types:
##  MANUAL    - press to open (swings away from the player), the default.
##  AUTOMATIC - sliding glass/security doors that open on approach. Only use
##              where a powered door makes sense (lab, lobby entrance, garage).
##  LOCKED    - needs a key item (by key_id), then behaves like MANUAL.
##  COOP      - two handles/wheels; both players must hold at the same time.
##              The waiting player gets a "Call partner" prompt for call-outs.

enum Kind { MANUAL, AUTOMATIC, LOCKED, COOP }
## Physics layer 6: things bodies can't pass but bullets fly through (an iron
## gate's bars). Survivors, the infected and the Tallyman collide with it;
## Combat's rays (world + hitboxes) don't, so you can shoot the infected
## pressed against the gate, and they can't claw you through it either
## (Zombie._clear_line checks it).
const BARS_LAYER := 32

@export var kind: Kind = Kind.MANUAL
@export var key_id := ""
@export var door_id := ""
@export var width := 1.1
@export var height := 2.2
@export var style := "wood_panel"   # wood_panel, steel, glass, shutter, iron_gate
@export var coop_window := 1.5

@export var is_open := false
var _leaf: Node3D
var _blocker: StaticBody3D
var _sensor: Area3D
var _handles: Array[Area3D] = []
var _holding: Dictionary = {}  # handle index -> peer_id
var _hold_time: Dictionary = {}
var _block_layer := 1
var _wheels: Array[Node3D] = []

func _ready() -> void:
	add_to_group("doors")
	_leaf = DoorVisual.build(style, width, height)
	add_child(_leaf)
	_blocker = StaticBody3D.new()
	_block_layer = BARS_LAYER if style == "iron_gate" else 1
	_blocker.collision_layer = _block_layer
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(width, height, 0.12)
	cs.shape = b
	cs.position = Vector3(0, height / 2, 0)
	_blocker.add_child(cs)
	add_child(_blocker)
	if kind == Kind.COOP:
		for i in 2:
			var x := (i * 2 - 1) * (width * 0.5 + 0.35)
			var a := _make_interact_area(Vector3(x, 1.1, 0.35))
			a.set_meta("handle", i)
			_handles.append(a)
			# A wheel valve on each face of the wall, so it's plain where the
			# two of them have to stand.
			for face in [-1.0, 1.0]:
				var w := _wheel()
				w.position = Vector3(x, 1.15, face * 0.24)
				w.rotation.y = 0.0 if face > 0 else PI
				add_child(w)
				_wheels.append(w)
		# Walking straight up to the door works too: the middle takes
		# whichever wheel is free (handle -2, see _rpc_request).
		_make_interact_area(Vector3(0, 1.1, 0), Vector3(width, 1.4, 1.6)).set_meta("handle", -2)
	elif kind == Kind.AUTOMATIC:
		_sensor = Area3D.new()
		_sensor.collision_mask = 2
		var s := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(width + 1.0, height, 4.0)
		s.shape = sb
		s.position.y = height / 2
		_sensor.add_child(s)
		add_child(_sensor)
	else:
		_make_interact_area(Vector3(0, 1.1, 0))
	if door_id != "" and GameState.has_flag("door_open:" + door_id):
		_set_open(true, Vector3.ZERO, false)

## A steel wheel valve (rim, hub, four spokes) facing +z.
func _wheel() -> Node3D:
	var n := Node3D.new()
	var steel := Mats.trim(Color(0.32, 0.3, 0.27), 0.45, 0.85)
	var rim := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.17
	t.outer_radius = 0.21
	t.rings = 24
	t.ring_segments = 8
	rim.mesh = t
	rim.rotation.x = PI / 2
	rim.material_override = steel
	n.add_child(rim)
	var hub := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.045
	c.bottom_radius = 0.05
	c.height = 0.12
	hub.mesh = c
	hub.rotation.x = PI / 2
	hub.position.z = -0.03
	hub.material_override = steel
	n.add_child(hub)
	for k in 2:
		var spoke := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.38, 0.025, 0.025)
		spoke.mesh = b
		spoke.rotation.z = k * PI / 2
		spoke.material_override = steel
		n.add_child(spoke)
	# Stem back into the wall.
	var stem := MeshInstance3D.new()
	var s := CylinderMesh.new()
	s.top_radius = 0.025
	s.bottom_radius = 0.025
	s.height = 0.12
	stem.mesh = s
	stem.rotation.x = PI / 2
	stem.position.z = -0.08
	stem.material_override = steel
	n.add_child(stem)
	return n

func _make_interact_area(pos: Vector3, size := Vector3.ZERO) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	a.position = pos
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size if size != Vector3.ZERO else Vector3(0.7 if kind == Kind.COOP else width, 1.4, 1.2)
	cs.shape = b
	a.add_child(cs)
	a.set_script(preload("res://scripts/world/interact_proxy.gd"))
	a.target = self
	add_child(a)
	return a

func _physics_process(delta: float) -> void:
	if kind == Kind.AUTOMATIC and multiplayer.is_server():
		var someone := not _sensor.get_overlapping_bodies().is_empty()
		if someone != is_open:
			_rpc_set_open.rpc(someone, Vector3.ZERO)
	if kind == Kind.COOP and not is_open and multiplayer.is_server():
		for h in _hold_time.keys():
			_hold_time[h] -= delta
			if _hold_time[h] <= 0:
				_hold_time.erase(h)
				_holding.erase(h)

func interact_text(player: Node, handle := -1) -> String:
	if is_open and kind != Kind.MANUAL:
		return ""
	match kind:
		Kind.LOCKED:
			if Cheats.on("unlock_doors") or player.inventory.key_items.has(key_id) or GameState.has_flag("unlocked:" + door_id):
				return "Open"
			return "Locked (%s)" % key_id.capitalize().replace("_", " ")
		Kind.COOP:
			return "Turn the wheel with your partner" if Net.is_coop() and not Cheats.on("solo_coop_doors") else "Open"
		Kind.MANUAL:
			return "Close" if is_open else "Open"
	return ""

func interact(player: Node, handle := -1) -> void:
	var away: Vector3 = (global_position - player.global_position).normalized()
	match kind:
		Kind.MANUAL:
			_rpc_request.rpc_id(1, not is_open, away, -1)
		Kind.LOCKED:
			if Cheats.on("unlock_doors") or player.inventory.key_items.has(key_id) or GameState.has_flag("unlocked:" + door_id):
				GameState.set_flag("unlocked:" + door_id)
				_rpc_request.rpc_id(1, true, away, -1)
			else:
				Sfx.play_at("door_locked", global_position + Vector3.UP)
		Kind.COOP:
			_rpc_request.rpc_id(1, true, away, handle)

@rpc("any_peer", "reliable", "call_local")
func _rpc_request(open: bool, away: Vector3, handle: int) -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	if kind == Kind.COOP:
		var solo := not Net.is_coop() or Cheats.on("solo_coop_doors")
		if handle < 0:
			# From the middle of the door: the wheel this player already
			# holds, else a free one.
			for h in 2:
				if _holding.get(h, -1) == who:
					handle = h
			if handle < 0:
				handle = 1 if _holding.has(0) else 0
		_holding[handle] = who
		_hold_time[handle] = coop_window
		var peers := {}
		for h in _holding:
			peers[_holding[h]] = true
		if solo or (_holding.size() >= 2 and peers.size() >= 2):
			_rpc_set_open.rpc(true, away)
		else:
			_rpc_waiting.rpc(who)
		return
	_rpc_set_open.rpc(open, away)

@rpc("authority", "reliable", "call_local")
func _rpc_waiting(waiting_peer: int) -> void:
	if multiplayer.get_unique_id() == waiting_peer:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_coop_wait()

@rpc("authority", "reliable", "call_local")
func _rpc_set_open(open: bool, away: Vector3) -> void:
	_set_open(open, away, true)

func _set_open(open: bool, away: Vector3, animate: bool) -> void:
	is_open = open
	if door_id != "" and kind != Kind.AUTOMATIC:
		GameState.set_flag("door_open:" + door_id, open)
	_blocker.collision_layer = 0 if open else _block_layer
	var side := 1.0
	if away != Vector3.ZERO:
		side = sign(global_transform.basis.z.dot(away))
		if side == 0:
			side = 1.0
	var t := create_tween() if animate else null
	if open and animate:
		for w in _wheels:
			var spin := create_tween()
			spin.tween_property(w, "rotation:z", w.rotation.z + TAU * 1.5, 1.1).set_trans(Tween.TRANS_SINE)
	var sound := {"glass": "door_auto", "shutter": "shutter", "iron_gate": "gate", "steel": "door_heavy"}.get(style, "door_open")
	if animate:
		Sfx.play_at(sound if open else sound + "_close", global_position + Vector3.UP, "door_open")
	if style in ["glass", "shutter"]:
		var target := Vector3(width if open else 0.0, 0, 0) if style == "glass" else Vector3(0, height if open else 0.0, 0)
		if t: t.tween_property(_leaf, "position", target, 0.6).set_trans(Tween.TRANS_SINE)
		else: _leaf.position = target
	else:
		var rot := -side * deg_to_rad(100) if open else 0.0
		if t: t.tween_property(_leaf, "rotation:y", rot, 0.75 if style != "steel" else 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else: _leaf.rotation.y = rot
