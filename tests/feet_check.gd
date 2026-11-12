extends SceneTree
## Where each outfit's soles end up: the lowest skinned vertex (in metres,
## relative to the character's origin, so 0 = standing on the floor) in the
## idle pose, at Legs 0, 0.5 and 1.
##   godot --headless --script tests/feet_check.gd -- [character:outfit ...]
var jobs := []
var cur: CharacterModel
var frames := 0
var bad := 0

func _initialize() -> void:
	var wanted := OS.get_cmdline_user_args()
	if wanted.is_empty():
		for c in ["zegan", "obcera"]:
			for o in CharacterModel.outfits(c):
				wanted.append("%s:%s" % [c, o])
	for w in wanted:
		for legs in [0.0, 0.5, 1.0]:
			jobs.append([w.get_slice(":", 0), w.get_slice(":", 1), legs])

static func lowest(model: CharacterModel) -> float:
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var skel: Skeleton3D = mi.get_node(mi.skeleton)
	var skin: Skin = mi.skin
	var xf := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		xf.append(skel.global_transform * skel.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var low := INF
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	for i in verts.size():
		var p := Vector3.ZERO
		for k in per:
			var wt := weights[i * per + k]
			if wt > 0.0:
				p += (xf[bones[i * per + k]] * verts[i]) * wt
		var y := model.to_local(p).y * model.scale.y
		if y < low:
			low = y
	return low

func _process(_d: float) -> bool:
	frames += 1
	if cur == null:
		if jobs.is_empty():
			print("FEET CHECK ", "OK" if bad == 0 else "FAILED (%d)" % bad)
			quit(1 if bad else 0)
			return false
		var j = jobs[0]
		cur = CharacterModel.new()
		cur.character = j[0]
		cur.customization = {"outfit": j[1], "legs": j[2]}
		root.add_child(cur)
		frames = 0
		return false
	cur.play("idle", false)
	if frames == 20:
		var j = jobs.pop_front()
		var low := lowest(cur)
		var ok := absf(low) < 0.025
		if not ok:
			bad += 1
		print("%-8s %-14s legs %.1f  lowest %+.3f m %s" % [j[0], j[1], j[2], low, "" if ok else "  <-- off the floor" if low > 0 else "  <-- sinks"])
		cur.free()
		cur = null
	return false
