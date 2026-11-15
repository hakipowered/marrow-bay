extends RefCounted
## Static batching for the browser version. The levels are built from a few
## thousand small meshes (trim, frames, books, papers, props): the street
## alone has over 2,000 on screen. The app's Vulkan renderer copes, but in a
## phone browser every one of them is a separate WebGL draw call, and the
## draw calls alone took most of the frame.
##
## Once a level is built, this batches the small pieces that never move or
## change, per few metres of floor: a prop placed many times (books, crates)
## becomes one instanced draw (keeping its distance detail levels), and the
## one-off pieces the rooms are built from (boxes, frames, trim, papers) are
## merged into one mesh per material. The originals are hidden from the
## camera (their layers go to 0; they stay in the tree, so collisions,
## children and any code that looks them up still work). The batches keep
## the same meshes, materials and world positions, so the picture is the same.
##
## Never merged: anything under a scripted node or a node in a group (doors,
## pickups, breakables, the elevator, the infected, vent grilles...), the
## glass and lamp fixtures a Breakable swaps or darkens, skinned or animated
## meshes, see-through materials (they're sorted per object), shaders that
## look at the object's own position, mirrored transforms, and anything bigger
## than MAX_PART (big walls and floors are one draw call already).
##
## Lights: the Compatibility renderer lights each object with at most 8 omni
## and 8 spot lights, and past 8 it keeps whichever it paired first, not the
## nearest. A merged chunk is split smaller until it isn't touched by more
## lights than LIGHT_BUDGET (or than its busiest piece already was), and never
## more than 8, so no piece loses a light it had. Lights switched off for now
## (tunnel lights waiting for the generator) count too. A piece already
## touched by more than 8 is left as it was.

const CELL := 6.0          # metres: chunk size on the ground
## CELL, changeable for measuring (tests/perf_probe.gd cell=<m>).
static var cell := CELL
const MIN_CELL := 1.5      # stop splitting here
const MAX_PART := 4.0      # metres: pieces bigger than this on any side stay
## Leaves room under the renderer's 8 for the torches, muzzle flashes and fires.
const LIGHT_BUDGET := 6
## The Compatibility renderer's limit per object (omni and spot each): past
## it, which lights an object gets is down to pairing order, not distance.
const MAX_LIGHTS := 8
const KEEP_FORMAT := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT \
		| Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_INDEX
const BAD_FORMAT := Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 \
		| Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3
## Shaders known to work in world space only (safe to merge).
const SAFE_SHADERS := ["res://shaders/surface.gdshader"]

## Merges the level's static pieces. Returns counts for logs and tests.
static func run(level: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var skip := {}
	_breakable_refs(level, skip)
	var lights := _light_boxes(level)
	var lod_cache := {}
	var canon := {"by_mat": {}, "by_sig": {}, "frozen": _frozen_materials(level)}
	# 1. Pieces: every eligible mesh, with what has to match to share a draw
	# call: the same mesh (instancing) or the same material (merging).
	var pieces: Array = []
	var by_mesh := {}
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		if skip.has(mi) or not _eligible(mi, level):
			continue
		var xf: Transform3D = mi.global_transform
		var box: AABB = xf * mi.get_aabb()
		if box.size.x > MAX_PART or box.size.y > MAX_PART or box.size.z > MAX_PART:
			continue
		var mesh: Mesh = mi.mesh
		var mats: Array = []
		var fmts: Array = []
		var ok := true
		for s in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var fmt := _format(mesh, s)
			if not _material_ok(mat) or fmt < 0 or fmt & BAD_FORMAT:
				ok = false
				break
			mats.append(_canonical(mat, canon))
			fmts.append(fmt)
		if not ok or mats.is_empty():
			continue
		var lit := _light_count(box, mi.layers, lights)
		if lit.x > MAX_LIGHTS or lit.y > MAX_LIGHTS:
			# The renderer already picks which lights this piece gets (in no
			# particular order); a copy might pick differently. Left alone.
			continue
		var it := {"mi": mi, "xf": xf, "box": box, "mats": mats, "fmts": fmts, "lights": lit}
		var mkey := "%d|%s|%d|%d" % [mesh.get_instance_id(), ",".join(mats.map(func(m): return str(m.get_instance_id() if m else 0))), mi.cast_shadow, mi.layers]
		if not by_mesh.has(mkey):
			by_mesh[mkey] = []
		by_mesh[mkey].append(it)
		pieces.append(it)
	var holder := Node3D.new()
	holder.name = "StaticBatches"
	level.add_child(holder)
	var hidden := {}
	var instanced := 0
	var merged := 0
	var batches := 0
	# 2. The same prop placed many times (books, crates, chairs): one
	# MultiMesh per few metres. Each copy keeps the mesh and its distance
	# detail levels, so nothing gets heavier.
	var singles: Array = []
	for mkey in by_mesh:
		var items: Array = by_mesh[mkey]
		if items.size() < 2:
			singles.append_array(items)
			continue
		var mi0: MeshInstance3D = items[0]["mi"]
		for chunk in _chunks(items, cell, lights, mi0.layers):
			if chunk.size() < 2:
				singles.append_array(chunk)
				continue
			_build_multimesh(holder, chunk)
			batches += 1
			for c in chunk:
				hidden[c["mi"]] = true
				instanced += 1
	# 3. One-off pieces with no detail levels (the boxes, frames, trim,
	# planks and papers the rooms are built from): merged into one mesh per
	# material. One-off scanned props keep their own draw call and LODs.
	var groups := {}
	for it in singles:
		var mesh: Mesh = it["mi"].mesh
		if _has_lods(mesh, lod_cache):
			continue
		var mi: MeshInstance3D = it["mi"]
		for s in mesh.get_surface_count():
			var mat: Material = it["mats"][s]
			var key := "%d|%d|%d|%d" % [mat.get_instance_id() if mat else 0, it["fmts"][s] & KEEP_FORMAT, mi.cast_shadow, mi.layers]
			if not groups.has(key):
				groups[key] = {"mat": mat, "cast": mi.cast_shadow, "layers": mi.layers, "items": []}
			groups[key]["items"].append({"mi": mi, "s": s, "xf": it["xf"], "box": it["box"], "lights": it["lights"]})
		hidden[mi] = true
		merged += 1
	var sizes := {}
	for k in groups:
		var g: Dictionary = groups[k]
		for chunk in _chunks(g["items"], cell, lights, g["layers"]):
			_build(holder, chunk, g)
			batches += 1
			var b := mini(chunk.size(), 5)
			sizes[b] = sizes.get(b, 0) + 1
	if OS.is_debug_build() or OS.get_cmdline_user_args().has("batch_stats"):
		print("StaticBatch merge groups=%d instanced groups=%d chunk sizes (1..5+): %s" % [groups.size(), by_mesh.size(), sizes])
	# 4. The originals stop drawing (and casting shadows); they stay in place.
	for mi in hidden:
		(mi as MeshInstance3D).layers = 0
	var out := {"pieces": pieces.size(), "instanced": instanced, "merged": merged, "batches": batches, "ms": Time.get_ticks_msec() - t0}
	print("StaticBatch: %d meshes -> %d instanced + %d merged into %d batches (%d left as they were) in %d ms" % [
		pieces.size(), instanced, merged, batches, pieces.size() - instanced - merged, out["ms"]])
	return out

static func _build_multimesh(holder: Node3D, chunk: Array) -> void:
	var mi0: MeshInstance3D = chunk[0]["mi"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mi0.mesh
	mm.instance_count = chunk.size()
	for i in chunk.size():
		mm.set_instance_transform(i, chunk[i]["xf"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = mi0.cast_shadow
	mmi.layers = mi0.layers
	# The copies draw with exactly the materials the originals had.
	var mats: Array = chunk[0]["mats"]
	var own := true
	for s in mats.size():
		if mats[s] != mi0.mesh.surface_get_material(s):
			own = false
	if not own:
		if mats.size() == 1 or mats.all(func(m): return m == mats[0]):
			mmi.material_override = mats[0]
		else:
			# Per-surface overrides: a mesh copy carrying them.
			var m2: Mesh = mi0.mesh.duplicate()
			for s in mats.size():
				m2.surface_set_material(s, mats[s])
			mm.mesh = m2
	holder.add_child(mmi)

## Materials made in code with identical settings (every window frame and
## shelf trim gets its own copy) are drawn as one, so their pieces can share
## a batch. Only materials no code changes later: glowing ones and the ones a
## flickering light dims with it are left alone, and so are saved resources.
static func _canonical(mat: Material, canon: Dictionary) -> Material:
	if mat == null or not mat is BaseMaterial3D or mat.resource_path != "" or canon["frozen"].has(mat):
		return mat
	# Glowing materials are the ones code switches on and off (light tubes
	# coming on one by one when the power returns): each keeps its own.
	if (mat as BaseMaterial3D).emission_enabled:
		return mat
	if canon["by_mat"].has(mat):
		return canon["by_mat"][mat]
	var parts := PackedStringArray([mat.get_class()])
	for p in mat.get_property_list():
		if p["usage"] & PROPERTY_USAGE_STORAGE and p["name"] != "resource_name":
			parts.append("%s=%s" % [p["name"], str(mat.get(p["name"]))])
	var sig := "|".join(parts)
	var c: Material = canon["by_sig"].get(sig, mat)
	canon["by_sig"][sig] = c
	canon["by_mat"][mat] = c
	return c

static func _frozen_materials(level: Node) -> Dictionary:
	var out := {}
	for l in level.find_children("*", "Light3D", true, false):
		var linked = l.get("linked")
		if linked is Array:
			for m in linked:
				out[m] = true
	return out

## Imported scans come with distance detail levels; a merged copy would lose
## them (and draw thousands of extra triangles far away).
static func _has_lods(mesh: Mesh, cache: Dictionary) -> bool:
	if not mesh is ArrayMesh:
		return false
	if cache.has(mesh):
		return cache[mesh]
	var lods := false
	for s in mesh.get_surface_count():
		var d := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var l = d.get("lods", [])
		if l is Array and l.size() > 0:
			lods = true
			break
	cache[mesh] = lods
	return lods

## Splits items into chunks of `cell` metres (by the centre of each piece),
## halving the cell where a chunk would be touched by more lights than the
## budget allows.
static func _chunks(items: Array, cell: float, lights: Array, layers: int) -> Array:
	var cells := {}
	for it in items:
		var c: Vector3 = it["box"].get_center()
		var key := Vector3i(floori(c.x / cell), floori(c.y / (cell * 1.5)), floori(c.z / cell))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(it)
	var out: Array = []
	for key in cells:
		var chunk: Array = cells[key]
		if chunk.size() == 1:
			out.append(chunk)
			continue
		var box: AABB = chunk[0]["box"]
		var allowed := Vector2i(LIGHT_BUDGET, LIGHT_BUDGET)
		for it in chunk:
			box = box.merge(it["box"])
			allowed = allowed.max(it["lights"])
		# Never past the renderer's limit: it would drop lights at random.
		allowed = allowed.min(Vector2i(MAX_LIGHTS, MAX_LIGHTS))
		var have := _light_count(box, layers, lights)
		if have.x <= allowed.x and have.y <= allowed.y:
			out.append(chunk)
		elif cell * 0.5 >= MIN_CELL:
			out.append_array(_chunks(chunk, cell * 0.5, lights, layers))
		else:
			for it in chunk:
				out.append([it])
	return out

static func _build(holder: Node3D, chunk: Array, g: Dictionary) -> void:
	var st := SurfaceTool.new()
	for it in chunk:
		st.append_from(it["mi"].mesh, it["s"], it["xf"])
	var mat: Material = g["mat"]
	if mat:
		st.set_material(mat)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = g["cast"]
	mi.layers = g["layers"]
	holder.add_child(mi)

## Can this mesh be merged at all?
static func _eligible(mi: MeshInstance3D, level: Node) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.layers == 0:
		return false
	if mi.get_script() != null or not mi.get_groups().is_empty():
		return false
	if mi.skin != null or mi.transparency > 0.0 or mi.material_overlay != null:
		return false
	if mi.visibility_range_begin > 0.0 or mi.visibility_range_end > 0.0:
		return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return false
	if mi.global_transform.basis.determinant() <= 0.0:
		return false
	var n := mi.get_parent()
	while n != null and n != level:
		if n.get_script() != null or not n.get_groups().is_empty():
			return false
		if n is AnimationMixer or n is Skeleton3D or n is BoneAttachment3D or n is PhysicsBody3D and not n is StaticBody3D:
			return false
		n = n.get_parent()
	return n == level

## A surface's vertex format, or -1 when it isn't plain triangles.
static func _format(mesh: Mesh, s: int) -> int:
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return -1
		return am.surface_get_format(s)
	if not mesh is PrimitiveMesh or mesh is PointMesh:
		return -1
	# Box, quad, plane, cylinder...: always triangles; read the arrays.
	var arrs := mesh.surface_get_arrays(s)
	var fmt := 0
	for i in arrs.size():
		if arrs[i] != null:
			fmt |= 1 << i
	return fmt

static func _material_ok(mat: Material) -> bool:
	if mat == null:
		return true
	if mat is ShaderMaterial:
		var sh: Shader = (mat as ShaderMaterial).shader
		return sh != null and sh.resource_path in SAFE_SHADERS and mat.next_pass == null
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		if b.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
			return false
		if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			return false
		if (b.uv1_triplanar and not b.uv1_world_triplanar) or (b.uv2_triplanar and not b.uv2_world_triplanar):
			return false
		if b.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER:
			return false
		if b.next_pass != null and not _material_ok(b.next_pass):
			return false
		return true
	return false

## Meshes a Breakable will change later: the window pane it cracks, and the
## whole light fixture it's mounted on (it darkens the bulb's surface).
static func _breakable_refs(level: Node, skip: Dictionary) -> void:
	for n in level.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		if sc == null or not str(sc.resource_path).ends_with("breakable.gd"):
			continue
		var glass = n.get("glass")
		if glass is MeshInstance3D:
			skip[glass] = true
		if n.get("kind") == "lamp" and n.get_parent() != null:
			for mi in n.get_parent().find_children("*", "MeshInstance3D", true, false):
				skip[mi] = true
			if n.get_parent() is MeshInstance3D:
				skip[n.get_parent()] = true
		var model = n.get("model")
		if model is Node:
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				skip[mi] = true

## World boxes of the level's omni and spot lights (all of them, switched on
## or not: the vault's come on later), for the per-object light budget.
static func _light_boxes(level: Node) -> Array:
	var out: Array = []
	for l in level.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			continue
		var local: AABB
		var spot := l is SpotLight3D
		if l is OmniLight3D:
			var r: float = (l as OmniLight3D).omni_range
			local = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
		else:
			var sl := l as SpotLight3D
			var len := sl.spot_range
			var size := len if sl.spot_angle >= 89.0 else minf(len, tan(deg_to_rad(sl.spot_angle)) * len)
			local = AABB(Vector3(-size, -size, -len), Vector3(size * 2.0, size * 2.0, len))
		out.append([(l as Node3D).global_transform * local, spot, (l as Light3D).light_cull_mask])
	return out

## (omni, spot) lights whose reach touches this box.
static func _light_count(box: AABB, layers: int, lights: Array) -> Vector2i:
	var c := Vector2i.ZERO
	for lb in lights:
		if (lb[2] & layers) == 0:
			continue
		if (lb[0] as AABB).intersects(box):
			if lb[1]:
				c.y += 1
			else:
				c.x += 1
	return c
