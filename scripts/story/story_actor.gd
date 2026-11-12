class_name StoryActor
extends Node3D
## A rigged story character driven by cutscenes and story scripts: the
## Tallyman, Warden Hardass. Loads res://assets/characters/<id>/<id>.glb and
## its clip library <id>_anims.res (built by tools/import_character.gd).
## The Tallyman also gets his hooked iron archive pole, held in the right
## hand and dragged along the floor behind him.

var character := ""
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _model: Node3D
var _hand := -1
var _pole: Node3D
var _walk_tween: Tween

func _init(id := "") -> void:
	character = id

func _ready() -> void:
	var path := "res://assets/characters/%s/%s.glb" % [character, character]
	if not ResourceLoader.exists(path):
		push_warning("story actor model missing: " + path)
		return
	_model = load(path).instantiate()
	_model.rotation.y = PI   # Meshy models face +Z; Godot's forward is -Z
	add_child(_model)
	_skel = _model.find_child("Skeleton3D", true, false)
	var old := _model.find_child("AnimationPlayer", true, false)
	if old:
		old.queue_free()
	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	var lib := "res://assets/characters/%s/%s_anims.res" % [character, character]
	if ResourceLoader.exists(lib):
		_anim.add_animation_library("", load(lib))
	if character == "tallyman":
		_build_pole()
	play("idle")

func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)

## Loop or one-shot clip by name, blended from whatever is playing.
func play(clip: String, blend := 0.25, speed := 1.0) -> void:
	if has_clip(clip):
		_anim.play(clip, blend, speed)

## A one-shot clip, then back to `then` (a loop) when it ends.
func play_once(clip: String, then := "idle", blend := 0.2, speed := 1.0) -> void:
	if not has_clip(clip):
		return
	_anim.play(clip, blend, speed)
	var dur := _anim.get_animation(clip).length / maxf(speed, 0.01)
	get_tree().create_timer(max(dur - 0.25, 0.1)).timeout.connect(func():
		if is_instance_valid(self) and _anim.current_animation == clip:
			play(then, 0.3))

## Walks to `to` (world space) playing `clip`, turning to face the way.
## Returns the tween's finished signal so a cutscene can wait on it.
func walk_to(to: Vector3, speed := 1.2, clip := "walk", then := "idle") -> Signal:
	if _walk_tween:
		_walk_tween.kill()
	var from := global_position
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	if flat.length() > 0.01:
		rotation.y = atan2(-flat.x, -flat.z)
	play(clip, 0.3)
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "global_position", to, from.distance_to(to) / max(speed, 0.05))
	_walk_tween.tween_callback(func(): play(then, 0.35))
	return _walk_tween.finished

## Stops a walk_to where it is (a skipped scene puts the actor on its mark).
func stop_walk() -> void:
	if _walk_tween:
		_walk_tween.kill()
		_walk_tween = null

## Turns to face a world point over `t` seconds.
func face(point: Vector3, t := 0.6) -> void:
	var d := point - global_position
	var target := atan2(-d.x, -d.z)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + wrapf(target - rotation.y, -PI, PI), t).set_trans(Tween.TRANS_SINE)

# ---------------------------------------------------------------- the pole

func _build_pole() -> void:
	if _skel == null:
		return
	for n in ["RightHand", "mixamorig:RightHand", "RightForeArm"]:
		_hand = _skel.find_bone(n)
		if _hand >= 0:
			break
	if _hand < 0:
		for i in _skel.get_bone_count():
			if _skel.get_bone_name(i).to_lower().contains("righthand"):
				_hand = i
				break
	_pole = Node3D.new()
	_pole.top_level = true
	add_child(_pole)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.11)
	iron.metallic = 0.85
	iron.roughness = 0.55
	# Shaft: runs along the pole node's -Z from the hand to the floor.
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.026
	cm.height = 1.0
	cm.radial_segments = 8
	shaft.mesh = cm
	shaft.material_override = iron
	shaft.rotation.x = PI / 2
	shaft.position.z = -0.5
	shaft.name = "Shaft"
	_pole.add_child(shaft)
	# The hook end: a bent iron claw past the hand, the end that drags.
	var hook := Node3D.new()
	hook.name = "Hook"
	_pole.add_child(hook)
	var bits := [[Vector3(0, 0, -0.06), Vector3(0.03, 0.03, 0.16), Vector3.ZERO],
		[Vector3(0, 0.07, -0.12), Vector3(0.026, 0.16, 0.026), Vector3(0.5, 0, 0)],
		[Vector3(0, 0.15, -0.07), Vector3(0.024, 0.024, 0.12), Vector3(-0.3, 0, 0)]]
	for b in bits:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.material_override = iron
		mi.position = b[0]
		mi.rotation = b[2]
		hook.add_child(mi)
	# Brass ferrule where he grips it.
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.032
	gm.bottom_radius = 0.032
	gm.height = 0.14
	grip.mesh = gm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.45, 0.33, 0.15)
	brass.metallic = 0.9
	brass.roughness = 0.35
	grip.material_override = brass
	grip.rotation.x = PI / 2
	_pole.add_child(grip)

func _process(_delta: float) -> void:
	if _pole == null or _hand < 0 or not is_instance_valid(_skel):
		return
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand).origin
	# The far end drags on the floor behind and to his right.
	var b := global_transform.basis
	var floor_pt := global_position + b.z.normalized() * 0.9 + b.x.normalized() * 0.55
	floor_pt.y = global_position.y + 0.03
	var dir := floor_pt - hand
	var plen := dir.length()
	if plen < 0.05:
		return
	_pole.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), hand)
	var shaft := _pole.get_node("Shaft") as MeshInstance3D
	shaft.scale = Vector3(1, plen, 1)
	shaft.position.z = -plen / 2
	(_pole.get_node("Hook") as Node3D).position = Vector3(0, 0, -plen)
