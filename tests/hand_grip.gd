extends SceneTree
## The survivors' hands close: every outfit of both survivors gets finger
## joints, and a fist pulls the fingertips round to the palm side of the
## hand while the thumb and the back of the hand stay put.
## godot --headless --path . --script tests/hand_grip.gd   (prints HAND GRIP OK)
var frames := 0
var queue := []
var cm: CharacterModel
var fails := 0

func _initialize() -> void:
	for who in ["zegan", "obcera"]:
		for id in CharacterModel.outfits(who):
			queue.append([who, id])

func _process(_d: float) -> bool:
	frames += 1
	if cm == null:
		if queue.is_empty():
			print("HAND GRIP OK" if fails == 0 else "HAND GRIP FAILED (%d)" % fails)
			quit(0 if fails == 0 else 1)
			return false
		var job: Array = queue.pop_front()
		cm = CharacterModel.new()
		cm.character = job[0]
		cm.customization = {"outfit": job[1]}
		root.add_child(cm)
		frames = 0
		return false
	if frames == 2:
		_check()
		cm.queue_free()
		cm = null
	return false

func _check() -> void:
	var tag := "%s/%s" % [cm.character, cm.outfit]
	var rig: HandRig = cm.hand_rig
	if rig == null:
		_fail(tag, "no finger joints")
		return
	var sk: Skeleton3D = cm._skel
	var mi: MeshInstance3D = cm._body_mesh
	for side in HandRig.SIDES:
		var h: Dictionary = rig.hands[side]
		var palm: float = h["axis"].x
		var hand := sk.find_bone(side + "Hand")
		var tips := _verts_on(mi, side + "Finger3")
		var knuckle := sk.get_bone_rest(h["bones"][0]).origin
		var thumb := _verts_on(mi, side + "Hand")
		if tips.size() < 20:
			_fail(tag, "%s: only %d fingertip vertices" % [side, tips.size()])
			continue
		rig.pose[side] = "relaxed"
		rig.update(0.0)
		var open_tips := _in_hand(sk, mi, hand, tips)
		var open_rest := _in_hand(sk, mi, hand, thumb)
		rig.pose[side] = "fist"
		rig.update(0.0)
		var fist_tips := _in_hand(sk, mi, hand, tips)
		var fist_rest := _in_hand(sk, mi, hand, thumb)
		var length: float = h["length"]
		# The fingertips come back toward the wrist and end up in front of
		# the palm (a hand bent the wrong way would put them behind it).
		var toward_palm := (fist_tips.z - knuckle.z) * palm
		var back := open_tips.y - fist_tips.y
		var still := open_rest.distance_to(fist_rest)
		print("%s %s: tips %.2f in front of the knuckles and %.2f back toward the wrist; rest of the hand moved %.3f (hand %.1f)" % [tag, side, toward_palm, back, still, length])
		if toward_palm < length * 0.04:
			_fail(tag, side + ": fingers didn't curl toward the palm")
		if back < length * 0.25:
			_fail(tag, side + ": fingertips didn't come back toward the wrist")
		if still > length * 0.01:
			_fail(tag, side + ": the back of the hand or the thumb moved")
		rig.pose[side] = "relaxed"
		rig.update(0.0)

## Vertices mostly weighted to a bind (by name).
func _verts_on(mi: MeshInstance3D, bone: String) -> Array:
	var bind := -1
	for i in mi.skin.get_bind_count():
		if String(mi.skin.get_bind_name(i)) == bone:
			bind = i
	var out := []
	if bind < 0:
		return out
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var n := bo.size() / v.size()
	for i in v.size():
		for s in n:
			if bo[i * n + s] == bind and we[i * n + s] > 0.6:
				out.append([v[i], bo.slice(i * n, i * n + n), we.slice(i * n, i * n + n)])
	return out

## Mean skinned position of the vertices, in the hand bone's own frame.
func _in_hand(sk: Skeleton3D, mi: MeshInstance3D, hand: int, verts: Array) -> Vector3:
	var to_hand := sk.get_bone_global_pose(hand).affine_inverse()
	var sum := Vector3.ZERO
	for e in verts:
		var p := Vector3.ZERO
		var bo: PackedInt32Array = e[1]
		var we: PackedFloat32Array = e[2]
		for s in bo.size():
			if we[s] <= 0.0:
				continue
			var b := sk.find_bone(String(mi.skin.get_bind_name(bo[s])))
			p += (sk.get_bone_global_pose(b) * mi.skin.get_bind_pose(bo[s]) * e[0]) * we[s]
		sum += to_hand * p
	return sum / maxf(verts.size(), 1)

func _fail(tag: String, why: String) -> void:
	fails += 1
	print("FAIL ", tag, ": ", why)
