class_name CombatClips
extends RefCounted
## Melee and throw clips (knife slash and stab, axe chop, grenade throw,
## knife guard stance) for the survivors, added to a model's AnimationPlayer
## as the "combat" library: play them as "combat/slash" and so on.
##
## The clips come from a Meshy rig of the base model with its own bone rest
## (see tools/weapons/import_combat_clips.gd). Each rotation key is
## retargeted so the bone turns by the same amount in the world on the
## skeleton that plays it, which works for the base model and every outfit
## model (they share bone names but not the exact rest):
##   q = Gdst(parent)^-1 * Gsrc(parent) * q_src * Gsrc(bone)^-1 * Gdst(bone)
## Results are cached per skeleton layout, so it runs once per outfit.

const LIB := "combat"
static var _cache: Dictionary = {}

## Source libraries, each from its own Meshy rig: the melee and throw clips,
## and whole-body moves (the dodge roll, tools/import_move_clips.gd). Both
## end up in the one "combat" library.
const SOURCES := ["combat", "moves"]

static func attach(anim: AnimationPlayer, skel: Skeleton3D, character: String) -> void:
	if anim == null or skel == null or anim.has_animation_library(LIB):
		return
	var model_root: Node = anim.get_node_or_null(anim.root_node)
	if model_root == null:
		return
	var skel_path := str(model_root.get_path_to(skel))
	var key := "%s|%s|%d|%s" % [character, skel_path, skel.get_bone_count(), _rest_signature(skel)]
	if not _cache.has(key):
		var out := AnimationLibrary.new()
		for src in SOURCES:
			var path := "res://assets/characters/%s/%s_%s.res" % [character, character, src]
			if not ResourceLoader.exists(path):
				continue
			var lib := _retarget(load(path), skel, skel_path)
			for clip in lib.get_animation_list():
				out.add_animation(clip, lib.get_animation(clip))
			for m in lib.get_meta_list():
				out.set_meta(m, lib.get_meta(m))
		_cache[key] = out
	if not (_cache[key] as AnimationLibrary).get_animation_list().is_empty():
		anim.add_animation_library(LIB, _cache[key])

## How far a move carries the body forward by time t (metres), on the
## skeleton that plays it; 0 when the move has no travel recorded.
static func travel(anim: AnimationPlayer, clip: String, t: float) -> float:
	if anim == null or not anim.has_animation_library(LIB):
		return 0.0
	var c: PackedVector2Array = anim.get_animation_library(LIB).get_meta("travel_" + clip, PackedVector2Array())
	if c.is_empty():
		return 0.0
	if t <= c[0].x:
		return c[0].y
	for i in range(1, c.size()):
		if c[i].x >= t:
			var f := (t - c[i - 1].x) / maxf(c[i].x - c[i - 1].x, 0.0001)
			return lerpf(c[i - 1].y, c[i].y, f)
	return c[c.size() - 1].y

static func _rest_signature(skel: Skeleton3D) -> String:
	# Outfits differ in their arm rest; two bones are enough to tell them apart.
	var a := skel.find_bone("RightHand")
	var b := skel.find_bone("Hips")
	return "%s/%s" % [skel.get_bone_rest(a).origin if a >= 0 else Vector3.ZERO, skel.get_bone_rest(b).origin if b >= 0 else Vector3.ZERO]

static func _retarget(src: AnimationLibrary, skel: Skeleton3D, skel_path: String) -> AnimationLibrary:
	var rest_q: Dictionary = src.get_meta("rest_q", {})
	var rest_o: Dictionary = src.get_meta("rest_o", {})
	var parents: Dictionary = src.get_meta("parents", {})
	var hip_src: float = src.get_meta("hip_y", 0.0)
	var hips := skel.find_bone("Hips")
	var hip_dst := skel.get_bone_global_rest(hips).origin.y if hips >= 0 else hip_src
	var ratio := hip_dst / hip_src if hip_src > 0.0 else 1.0
	var out := AnimationLibrary.new()
	for clip in src.get_animation_list():
		var a: Animation = src.get_animation(clip).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var bone := a.track_get_path(t).get_concatenated_subnames()
			var bd := skel.find_bone(bone)
			if bd < 0 or not rest_q.has(bone):
				a.remove_track(t)
				continue
			a.track_set_path(t, NodePath("%s:%s" % [skel_path, bone]))
			var parent_name: String = parents.get(bone, "")
			var pd := skel.get_bone_parent(bd)
			var gs: Quaternion = rest_q[bone]
			var gd := skel.get_bone_global_rest(bd).basis.get_rotation_quaternion()
			var gps: Quaternion = rest_q.get(parent_name, Quaternion.IDENTITY)
			var gpd := skel.get_bone_global_rest(pd).basis.get_rotation_quaternion() if pd >= 0 else Quaternion.IDENTITY
			var pre := gpd.inverse() * gps
			var post := gs.inverse() * gd
			match a.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					for k in a.track_get_key_count(t):
						var q: Quaternion = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, (pre * q * post).normalized())
				Animation.TYPE_POSITION_3D:
					var rs: Vector3 = rest_o.get(bone, Vector3.ZERO)
					var rd := skel.get_bone_rest(bd).origin
					for k in a.track_get_key_count(t):
						var p: Vector3 = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, rd + pre * ((p - rs) * ratio))
		out.add_animation(clip, a)
		var tr: PackedVector2Array = src.get_meta("travel_" + clip, PackedVector2Array())
		if not tr.is_empty():
			var scaled := PackedVector2Array()
			for v in tr:
				scaled.append(Vector2(v.x, v.y * ratio))
			out.set_meta("travel_" + clip, scaled)
	return out
