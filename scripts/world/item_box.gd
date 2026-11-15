class_name ItemBox
extends Node3D
## The item box in a safe room: an old wooden military supply crate the
## wardens left behind, with draw latches and a hinged lid. Every box opens
## onto the same store (GameState.item_box): put the shotgun in at the office
## and it's waiting in the keeper's lodge. In co-op both survivors share it,
## and either can have it open while the other does.
##
## The lid swings up for everyone while anyone has the box open, with the
## latches and the creak, so the partner sees and hears it.
##
## Placed on the floor: local +z is the front, where the survivor stands.

const LID_OPEN := -1.92   # radians about the hinge: up and a little past upright
const MODEL := "wooden_military_crate"

var _lid: Node3D
var _users := {}          # peer id -> true while that phone has it open
var _lid_open := false
var _lid_tween: Tween

func _ready() -> void:
	add_to_group("item_boxes")
	var m := RoomBuilder.prop(self, MODEL, Vector3.ZERO, 0.0, 1.0, true)
	m.name = "Crate"
	_lid = m.find_child(MODEL + "_lid", true, false) as Node3D
	# What the survivor's reach ray finds (layer 16, like doors). The ray is
	# chest high, so the area stands well above the low crate.
	var a := Area3D.new()
	a.name = "Reach"
	a.collision_layer = 16
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.5, 1.6, 1.1)
	cs.shape = b
	a.add_child(cs)
	a.position = Vector3(0, 0.8, 0.2)
	a.set_script(preload("res://scripts/world/interact_proxy.gd"))
	a.target = self
	add_child(a)
	multiplayer.peer_disconnected.connect(func(id: int):
		if _users.erase(id):
			_set_lid(not _users.is_empty()))

func interact_text(player: Node, _handle := -1) -> String:
	if player == null or player.get("downed") or player.get("dead"):
		return ""
	return "Open the item box"

func interact(player: Node, _handle := -1) -> void:
	if interact_text(player) == "" or not player.is_multiplayer_authority():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_item_box"):
		hud.open_item_box(self)

## This phone opened or closed the box screen.
func set_in_use(on: bool) -> void:
	if is_inside_tree():
		_rpc_use.rpc(multiplayer.get_unique_id(), on)

@rpc("any_peer", "reliable", "call_local")
func _rpc_use(peer: int, on: bool) -> void:
	if on:
		_users[peer] = true
	else:
		_users.erase(peer)
	_set_lid(not _users.is_empty())

func is_open() -> bool:
	return _lid_open

func _set_lid(open: bool) -> void:
	if open == _lid_open:
		return
	_lid_open = open
	var at := global_position + Vector3.UP * 0.45
	Sfx.play_at("box_open" if open else "box_close", at, "", -2.0, 6.0)
	if _lid == null:
		return
	if _lid_tween:
		_lid_tween.kill()
	_lid_tween = create_tween()
	if open:
		# The latches go first, then the lid comes up heavy and slows at the top.
		_lid_tween.tween_interval(0.18)
		_lid_tween.tween_property(_lid, "rotation:x", LID_OPEN, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		# Lowered most of the way, then let drop the last bit.
		_lid_tween.tween_property(_lid, "rotation:x", LID_OPEN * 0.25, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_lid_tween.tween_property(_lid, "rotation:x", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
