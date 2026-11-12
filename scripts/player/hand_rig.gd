class_name HandRig
extends RefCounted
## Fingers for the survivors' hands.
##
## The Meshy bodies are rigged only down to the wrist, so a hand could never
## close: a knife or a gun sat against a flat, open palm. This adds three
## finger joints to each hand (knuckles, middle, tips; the four fingers bend
## together and the thumb stays with the hand) by re-weighting the hand's
## vertices when the body loads, then curls them around whatever the hand
## holds and relaxes them when it's empty.
##
## Everything is worked out from the mesh itself, in the hand bone's own frame
## (Y runs from the wrist to the fingertips on these rigs), so it fits every
## outfit of both survivors without hand-tuned numbers.

const SIDES := ["Right", "Left"]
## The joints, as a share of the hand's length from the wrist.
const JOINTS := [0.67, 0.8, 0.9]
## How far each joint bends (radians) for a fist, a relaxed hand and a cupped
## palm (a grenade resting on it).
const POSES := {
	"fist": [1.25, 1.45, 0.9],
	"support": [0.95, 1.1, 0.7],
	"cup": [0.55, 0.6, 0.4],
	"relaxed": [0.22, 0.3, 0.2],
}

## Source mesh -> {"mesh", "skin", "info"}. Built once per body model.
static var _cache := {}

var skel: Skeleton3D
## side -> {"bones": [i1, i2, i3], "axis": Vector3, "grip": Vector3,
## "length": float, "thumb": +-1 (the side of X the thumb is on)}, in the
## hand bone's own units
var hands := {}
var _amount := {"Right": [0.0, 0.0, 0.0], "Left": [0.0, 0.0, 0.0]}
var pose := {"Right": "relaxed", "Left": "relaxed"}

## Gives the body on `mi` finger joints on `sk`. Null when the mesh has no
## hand bones (a stand-in, or a model already rigged to the fingers).
static func build(sk: Skeleton3D, mi: MeshInstance3D) -> HandRig:
	if sk == null or mi == null or not (mi.mesh is ArrayMesh) or mi.skin == null:
		return null
	for side in SIDES:
		if sk.find_bone(side + "Hand") < 0 or sk.find_bone(side + "Finger1") >= 0:
			return null
	var key: Variant = mi.mesh
	if not _cache.has(key):
		_cache[key] = _rig_mesh(mi.mesh as ArrayMesh, mi.skin, sk)
	var c: Dictionary = _cache[key]
	if c.is_empty():
		return null
	var r := HandRig.new()
	r.skel = sk
	for side in SIDES:
		var info: Dictionary = c["info"][side]
		var hb := sk.find_bone(side + "Hand")
		var prev := hb
		var prev_at := Vector3.ZERO
		var bones: Array[int] = []
		for k in JOINTS.size():
			var b := sk.get_bone_count()
			sk.add_bone(side + "Finger%d" % (k + 1))
			sk.set_bone_parent(b, prev)
			sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, info["joints"][k] - prev_at))
			sk.reset_bone_pose(b)
			bones.append(b)
			prev = b
			prev_at = info["joints"][k]
		r.hands[side] = {"bones": bones, "axis": info["axis"], "grip": info["grip"],
			"length": info["length"], "thumb": info["thumb"]}
	mi.mesh = c["mesh"]
	mi.skin = c["skin"]
	r.update(0.0)
	return r

## Moves the fingers toward the pose each hand should be in.
func update(delta: float) -> void:
	if not is_instance_valid(skel):
		return
	var k := 1.0 if delta <= 0.0 else 1.0 - exp(-14.0 * delta)
	for side in hands:
		var h: Dictionary = hands[side]
		var want: Array = POSES.get(pose[side], POSES["relaxed"])
		var cur: Array = _amount[side]
		for j in 3:
			cur[j] = lerpf(cur[j], want[j], k)
			skel.set_bone_pose_rotation(h["bones"][j], Quaternion(h["axis"], cur[j]))

## The middle of the closed fist of a hand, from its wrist bone, in metres in
## the bone's frame (scale taken out). Zero when unknown.
func grip_point(side := "Right") -> Vector3:
	if not hands.has(side) or not is_instance_valid(skel):
		return Vector3.ZERO
	var hb := skel.find_bone(side + "Hand")
	var s := (skel.global_basis * skel.get_bone_global_pose(hb).basis).get_scale()
	var g: Vector3 = hands[side]["grip"]
	return Vector3(g.x * s.x, g.y * s.y, g.z * s.z)

# ---------- Building the rig ----------

## The skin's bind for a bone, by name, or by bone index for a skin that
## binds that way.
static func _bind_index(skin: Skin, bone: String, bone_idx: int) -> int:
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == bone or (bn == "" and skin.get_bind_bone(i) == bone_idx):
			return i
	return -1

## Re-weights the hands of a body mesh onto new finger bones. Returns
## {"mesh", "skin", "info": {side: {"joints", "axis", "grip"}}}, or {} if the
## hands can't be found.
static func _rig_mesh(src: ArrayMesh, skin: Skin, sk: Skeleton3D) -> Dictionary:
	var info := {}
	var new_skin: Skin = skin.duplicate()
	var bind_of := {}   # side -> [hand bind, f1, f2, f3]
	var surfaces := []
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null:
			return {}
		surfaces.append(arr)
	for side in SIDES:
		var hbind := _bind_index(skin, side + "Hand", sk.find_bone(side + "Hand"))
		if hbind < 0:
			return {}
		var ib: Transform3D = skin.get_bind_pose(hbind)
		var a := _analyse(surfaces, hbind, ib, side)
		if a.is_empty():
			return {}
		info[side] = a
		var binds := [hbind]
		for k in JOINTS.size():
			var at: Vector3 = a["joints"][k]
			binds.append(new_skin.get_bind_count())
			new_skin.add_named_bind(side + "Finger%d" % (k + 1), Transform3D(Basis.IDENTITY, -at) * ib)
		bind_of[side] = binds
	var out := ArrayMesh.new()
	for b in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(b))
	out.blend_shape_mode = src.blend_shape_mode
	for s in src.get_surface_count():
		var arr: Array = surfaces[s]
		for side in SIDES:
			_reweight(arr, bind_of[side], skin.get_bind_pose(bind_of[side][0]), info[side])
		var fmt := src.surface_get_format(s)
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 0
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, src.surface_get_blend_shape_arrays(s), {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	out.custom_aabb = src.custom_aabb
	return {"mesh": out, "skin": new_skin, "info": info}

## Finds the hand's length, its thumb side and palm side, and where the
## finger joints go, from the vertices weighted to the hand bone.
static func _analyse(surfaces: Array, hbind: int, ib: Transform3D, side: String) -> Dictionary:
	var pts := PackedVector3Array()
	for arr in surfaces:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var n := bo.size() / maxi(v.size(), 1)
		for i in v.size():
			var w := 0.0
			for j in n:
				if bo[i * n + j] == hbind:
					w += we[i * n + j]
			if w > 0.5:
				pts.append(ib * v[i])
	if pts.size() < 50:
		return {}
	var ys := PackedFloat32Array()
	for p in pts:
		ys.append(p.y)
	ys.sort()
	var length := ys[int(ys.size() * 0.98)]
	if length <= 0.0:
		return {}
	# Finger band and palm band, across the hand (X) and through it (Z).
	var fx := PackedFloat32Array()
	var px := PackedFloat32Array()
	for p in pts:
		var t := p.y / length
		if t > 0.78 and t < 0.97:
			fx.append(p.x)
		if t > 0.4 and t < 0.68:
			px.append(p.x)
	if fx.size() < 10 or px.size() < 10:
		return {}
	fx.sort()
	px.sort()
	var f0 := fx[int(fx.size() * 0.03)]
	var f1 := fx[int(fx.size() * 0.97)]
	var p0 := px[0]
	var p1 := px[px.size() - 1]
	# The thumb sticks out past the fingers on one side.
	var thumb := -1.0 if (f0 - p0) > (p1 - f1) else 1.0
	var thumb_cut := (f0 if thumb < 0.0 else f1) + thumb * length * 0.02
	# With the fingers along +Y, the palm of a right hand faces thumb x
	# fingers, and a left hand's the other way.
	var palm := thumb if side == "Right" else -thumb
	# Joints in the middle of the fingers' thickness.
	var joints: Array[Vector3] = []
	var mid_x := (f0 + f1) * 0.5
	for k in JOINTS.size():
		var y: float = JOINTS[k] * length
		var zs := PackedFloat32Array()
		for p in pts:
			if absf(p.y - y) < length * 0.04 and (p.x - thumb_cut) * thumb < 0.0:
				zs.append(p.z)
		var z := 0.0
		if zs.size() > 0:
			zs.sort()
			z = (zs[0] + zs[zs.size() - 1]) * 0.5
		joints.append(Vector3(mid_x, y, z))
	# Bending about +X turns Y toward +Z: point the axis so a positive angle
	# closes the hand toward the palm.
	var axis := Vector3(palm, 0, 0)
	# Middle of the fist: level with the knuckles, the fingers' length over pi
	# out from them on the palm side.
	var finger := length - joints[0].y
	var grip := joints[0] + Vector3(0, -finger * 0.15, palm * finger * 0.55)
	return {"joints": joints, "axis": axis, "grip": grip, "length": length,
		"thumb": thumb, "thumb_cut": thumb_cut, "palm": palm}

## Moves the hand's weight on finger vertices onto the finger joints, blended
## across each joint so the skin bends instead of creasing.
static func _reweight(arr: Array, binds: Array, ib: Transform3D, a: Dictionary) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var n := bo.size() / maxi(v.size(), 1)
	var hb: int = binds[0]
	var length: float = a["length"]
	var blend := length * 0.035
	var thumb: float = a["thumb"]
	var cut: float = a["thumb_cut"]
	var j: Array = a["joints"]
	for i in v.size():
		var slot := -1
		for s in n:
			if bo[i * n + s] == hb and we[i * n + s] > 0.0:
				slot = s
				break
		if slot < 0:
			continue
		var p := ib * v[i]
		if p.y < j[0].y - blend or (p.x - cut) * thumb > 0.0:
			continue
		var wh := we[i * n + slot]
		var f1 := smoothstep(j[0].y - blend, j[0].y + blend, p.y)
		var f2 := smoothstep(j[1].y - blend, j[1].y + blend, p.y)
		var f3 := smoothstep(j[2].y - blend, j[2].y + blend, p.y)
		var parts := {hb: wh * (1.0 - f1), binds[1]: wh * (f1 - f2), binds[2]: wh * (f2 - f3), binds[3]: wh * f3}
		# Keep the vertex's other influences, then the strongest n in all.
		for s in n:
			if s != slot and we[i * n + s] > 0.0:
				var b := bo[i * n + s]
				parts[b] = parts.get(b, 0.0) + we[i * n + s]
		var order := parts.keys()
		order.sort_custom(func(x, y): return parts[x] > parts[y])
		var total := 0.0
		for s in mini(n, order.size()):
			total += parts[order[s]]
		for s in n:
			if s < order.size() and total > 0.0:
				bo[i * n + s] = order[s]
				we[i * n + s] = parts[order[s]] / total
			else:
				bo[i * n + s] = 0
				we[i * n + s] = 0.0
	arr[Mesh.ARRAY_BONES] = bo
	arr[Mesh.ARRAY_WEIGHTS] = we
