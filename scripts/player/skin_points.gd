class_name SkinPoints
## Skinned vertex positions worked out on the CPU, for tools and tests that
## need the real surface (sole height, chest shape) rather than bone joints.

## Every vertex of the mesh's first surface, posed by its skeleton's current
## bone poses, in skeleton space.
static func posed(mi: MeshInstance3D) -> PackedVector3Array:
	var skel: Skeleton3D = mi.get_node(mi.skeleton)
	var skin: Skin = mi.skin
	var xf := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		xf.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var p := Vector3.ZERO
		for k in per:
			var wt := weights[i * per + k]
			if wt > 0.0:
				p += (xf[bones[i * per + k]] * verts[i]) * wt
		out[i] = p
	return out

## The most forward point of each breast (or pectoral) near the given
## centres, in skeleton space, made symmetric: [left, right]. Forward is +Z.
static func chest_apex(points: PackedVector3Array, centre_l: Vector3, centre_r: Vector3) -> Array:
	var best: Array[Vector3] = [Vector3(0, 0, -INF), Vector3(0, 0, -INF)]
	for p in points:
		for s in 2:
			var c: Vector3 = centre_l if s == 0 else centre_r
			if signf(p.x) != signf(c.x) or absf(p.x) < 2.5 or absf(p.x) > absf(c.x) + 9.0:
				continue
			if p.y < c.y - 10.0 or p.y > c.y + 14.0:
				continue
			if p.z > best[s].z:
				best[s] = p
	var x := (absf(best[0].x) + absf(best[1].x)) * 0.5
	var y := (best[0].y + best[1].y) * 0.5
	var z := (best[0].z + best[1].z) * 0.5
	return [Vector3(x * signf(centre_l.x), y, z), Vector3(x * signf(centre_r.x), y, z)]
