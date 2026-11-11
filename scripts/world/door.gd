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

func _ready() -> void:
	add_to_group("doors")
	_leaf = DoorVisual.build(style, width, height)
	add_child(_leaf)
	_blocker = StaticBody3D.new()
	_blocker.collision_layer = 1
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(width, height, 0.12)
	cs.shape = b
	cs.position = Vector3(0, height / 2, 0)
	_blocker.add_child(cs)
	add_child(_blocker)
	if kind == Kind.COOP:
		for i in 2:
			var a := _make_interact_area(Vector3((i * 2 - 1) * (width * 0.5 + 0.35), 1.1, 0.35))
			a.set_meta("handle", i)
			_handles.append(a)
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

func _make_interact_area(pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	a.position = pos
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.7 if kind == Kind.COOP else width, 1.4, 1.2)
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
			return "Hold with partner"
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
	_blocker.collision_layer = 0 if open else 1
	var side := 1.0
	if away != Vector3.ZERO:
		side = sign(global_transform.basis.z.dot(away))
		if side == 0:
			side = 1.0
	var t := create_tween() if animate else null
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
