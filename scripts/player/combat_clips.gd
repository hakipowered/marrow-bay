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

## Source files merged into the "combat" library, each from its own Meshy
## rig: the melee and throw clips, and the dodge roll
## (tools/import_move_clips.gd, <id>_roll.res).
const SOURCES := ["combat", "roll"]

## lib names both the library ("combat", "moves") and the file it comes
## from: res://assets/characters/<character>/<character>_<lib>.res. The
## "combat" library also takes in the other SOURCES.
static func attach(anim: AnimationPlayer, skel: Skeleton3D, character: String, lib := LIB) -> void:
	if anim == null or skel == null or anim.has_animation_library(lib):
		return
	var model_root: Node = anim.get_node_or_null(anim.root_node)
	if model_root == null:
		return
	var skel_path := str(model_root.get_path_to(skel))
	var key := "%s|%s|%s|%d|%s" % [lib, character, skel_path, skel.get_bone_count(), _rest_signature(skel)]
	if not _cache.has(key):
		var out := AnimationLibrary.new()
		for src in (SOURCES if lib == LIB else [lib]):
			var path := "res://assets/characters/%s/%s_%s.res" % [character, character, src]
			if not ResourceLoader.exists(path):
				continue
			var part := _retarget(load(path), skel, skel_path, src != "combat")
			for clip in part.get_animation_list():
				out.add_animation(clip, part.get_animation(clip))
			for m in part.get_meta_list():
				out.set_meta(m, part.get_meta(m))
		_cache[key] = out
	if not (_cache[key] as AnimationLibrary).get_animation_list().is_empty():
		anim.add_animation_library(lib, _cache[key])

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

static func _retarget(src: AnimationLibrary, skel: Skeleton3D, skel_path: String, grounded := false) -> AnimationLibrary:
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
		if grounded:
			_ground_on(a, skel)
		out.add_animation(clip, a)
		var tr: PackedVector2Array = src.get_meta("travel_" + clip, PackedVector2Array())
		if not tr.is_empty():
			var scaled := PackedVector2Array()
			for v in tr:
				scaled.append(Vector2(v.x, v.y * ratio))
			out.set_meta("travel_" + clip, scaled)
	return out

## Stands a whole-body clip (the roll, a survivor's own idle) on the floor
## of the skeleton that plays it, after retargeting: shifts the hips so the
## lowest point of either foot (ankle or ball of the foot), at its lowest over
## the clip, is as high as in this body's rest pose. Meshy's idle and roll
## rigs carry the hips ~6 cm up and their legs aren't quite this body's,
## which left Obcera's own idle hovering 8-9 cm over the floor.
static func _ground_on(a: Animation, skel: Skeleton3D) -> void:
	var rot := {}
	var pos := {}
	for t in a.get_track_count():
		var bone := a.track_get_path(t).get_concatenated_subnames()
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot[bone] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos[bone] = t
	var hips := skel.find_bone("Hips")
	if hips < 0 or not pos.has("Hips"):
		return
	var lift := INF
	for tip in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var bi := skel.find_bone(tip)
		if bi < 0:
			continue
		var chain: Array[int] = []
		var b := bi
		while b >= 0:
			chain.push_front(b)
			b = skel.get_bone_parent(b)
		var rest_y := skel.get_bone_global_rest(bi).origin.y
		const N := 60
		for i in N + 1:
			var tm := a.length * i / N
			var g := Transform3D()
			for c in chain:
				var n := skel.get_bone_name(c)
				var r := skel.get_bone_rest(c)
				var q: Quaternion = a.rotation_track_interpolate(rot[n], tm) if rot.has(n) else r.basis.get_rotation_quaternion()
				var o: Vector3 = a.position_track_interpolate(pos[n], tm) if pos.has(n) else r.origin
				g = g * Transform3D(Basis(q), o)
			lift = minf(lift, g.origin.y - rest_y)
	if lift == INF or absf(lift) < 0.0001:
		return
	# Straight down in skeleton space, whatever the hips' parent is.
	var hp := skel.get_bone_parent(hips)
	var down := Vector3(0, -lift, 0)
	if hp >= 0:
		down = skel.get_bone_global_rest(hp).basis.inverse() * down
	var ht: int = pos["Hips"]
	for k in a.track_get_key_count(ht):
		a.track_set_key_value(ht, k, (a.track_get_key_value(ht, k) as Vector3) + down)
