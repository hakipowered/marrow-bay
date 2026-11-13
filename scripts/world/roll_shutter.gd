class_name RollShutter
extends Node3D
## A shop's roller shutter over a real doorway. Shut, it's solid: survivors,
## the infected and bullets all stop at it. burst() is the infected forcing
## it from inside: pounding that bulges it, a jerk up a hand's width, more
## pounding, then it flies up into the roll and they come out. That way an
## infected that "breaks in" always has a door you saw it come through.
##
## The level's navmesh is baked with the doorway open (the shutter's collider
## only joins after the bake), so the ones inside can path out once it's up.
## Placed at the bottom centre of the shutter, facing +Z (the street side).

@export var width := 4.0
@export var height := 2.8
var is_open := false
var _curtain: Node3D
var _body: StaticBody3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("shutters")
	_rng.seed = hash(str(name))
	var mat := Mats.surface("shutter", {"tile_size": 1.6, "grime_amount": 0.6})
	var metal := Mats.trim(Color(0.2, 0.2, 0.21), 0.55, 0.6)
	# The curtain hangs from its top edge (the roll), so scaling it shortens
	# it upward like a real shutter rolling up.
	_curtain = Node3D.new()
	_curtain.position = Vector3(0, height, 0)
	add_child(_curtain)
	var slats := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.1)
	slats.mesh = bm
	slats.material_override = mat
	slats.position = Vector3(0, -height / 2.0, 0)
	_curtain.add_child(slats)
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(width, 0.07, 0.14)
	bar.mesh = bb
	bar.material_override = metal
	bar.position = Vector3(0, -height + 0.035, 0)
	_curtain.add_child(bar)
	# Guide rails either side; they stay when it's up.
	for s in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.07, height, 0.16)
		rail.mesh = rb
		rail.material_override = metal
		rail.position = Vector3(s * (width / 2.0 + 0.035), height / 2.0, 0)
		add_child(rail)
	_body = StaticBody3D.new()
	_body.collision_layer = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.16)
	cs.shape = box
	cs.position = Vector3(0, height / 2.0, 0)
	_body.add_child(cs)
	add_child(_body)
	_shut_after_bake.call_deferred()

func _shut_after_bake() -> void:
	if not is_open:
		_body.collision_layer = 1

## Already forced earlier in this run (a reload past the scare): up and open.
func open_now() -> void:
	is_open = true
	_body.collision_layer = 0
	_curtain.visible = false

## Pounding from inside, then it's forced up. Runs on every phone (the scare
## fires for both); finishes when it's open.
func burst() -> void:
	if is_open:
		return
	for i in 4:
		_pound(1.0 if i < 3 else 1.4)
		await get_tree().create_timer(_rng.randf_range(0.38, 0.62)).timeout
	# Hands under the bottom bar: it jerks up a little, drops, then goes.
	Sfx.play_at("shutter_rattle", global_position + Vector3(0, 0.6, 0.2), "metal_bang", 4.0, 14.0)
	var jerk := create_tween()
	jerk.tween_property(_curtain, "scale:y", 0.86, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jerk.tween_property(_curtain, "scale:y", 0.95, 0.25)
	await get_tree().create_timer(0.75).timeout
	_pound(1.3)
	await get_tree().create_timer(0.4).timeout
	is_open = true
	_body.collision_layer = 0
	Sfx.play_at("shutter_roll", global_position + Vector3(0, 1.6, 0.2), "metal_bang", 6.0, 16.0)
	var up := create_tween()
	up.tween_property(_curtain, "scale:y", 0.03, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await up.finished
	_curtain.visible = false

## One blow from inside: a metal boom and the curtain bulging out at a
## random spot, then springing back.
func _pound(strength: float) -> void:
	var at := Vector3(_rng.randf_range(-width * 0.35, width * 0.35), _rng.randf_range(0.8, 1.6), 0.2)
	Sfx.play_at("shutter_bang", global_position + global_transform.basis * at, "metal_bang", 4.0 + strength * 2.0, 14.0)
	var t := create_tween()
	t.tween_property(_curtain, "position", Vector3(at.x * 0.012, height, 0.05 * strength), 0.05)
	t.tween_property(_curtain, "position", Vector3(0, height, 0), 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
