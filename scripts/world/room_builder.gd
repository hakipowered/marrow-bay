class_name RoomBuilder
## Builds rooms from compact data so the whole level stays readable as code.
##
## room = {
##   id, pos: Vector3 (floor corner), size: Vector3 (w, h, d),
##   floor, wall, ceiling: texture slots, wainscot: slot or "",
##   look: {tint, grime_amount, stain_amount, wetness, ...} (surface shader params),
##   openings: {"n": [[offset, width, height]], "s": [...], "e": [...], "w": [...]},
##   outdoor: bool (no ceiling), trim: Color
## }

const WALL_T := 0.25

static func build(parent: Node3D, r: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = r["id"]
	parent.add_child(root)
	var pos: Vector3 = r["pos"]
	var size: Vector3 = r["size"]
	root.position = pos
	var look: Dictionary = r.get("look", {})
	var base := look.duplicate()
	base["floor_y"] = pos.y
	base["ceiling_y"] = pos.y + size.y

	_box(root, Vector3(size.x / 2, -0.1, size.z / 2), Vector3(size.x, 0.2, size.z),
		Mats.surface(r["floor"], _merge(base, r.get("floor_look", {"tile_size": 2.0}))), true)
	if not r.get("outdoor", false):
		var ceil_look := _merge(base, {"grime_amount": 0.0, "stain_amount": 0.0, "tile_size": 3.0})
		_box(root, Vector3(size.x / 2, size.y + 0.1, size.z / 2), Vector3(size.x, 0.2, size.z),
			Mats.surface(r.get("ceiling", "ceiling"), ceil_look), true)

	var openings: Dictionary = r.get("openings", {})
	var wall_mat := Mats.surface(r["wall"], _merge(base, r.get("wall_look", {"tile_size": 2.5})))
	var sides := {
		"n": [Vector3(0, 0, 0), Vector3(1, 0, 0), size.x],
		"s": [Vector3(0, 0, size.z), Vector3(1, 0, 0), size.x],
		"w": [Vector3(0, 0, 0), Vector3(0, 0, 1), size.z],
		"e": [Vector3(size.x, 0, 0), Vector3(0, 0, 1), size.z],
	}
	for side in sides:
		if r.get("skip_walls", []).has(side):
			continue
		var origin: Vector3 = sides[side][0]
		var axis: Vector3 = sides[side][1]
		var length: float = sides[side][2]
		var ops: Array = openings.get(side, [])
		ops.sort_custom(func(a, b): return a[0] < b[0])
		var cursor := 0.0
		for op in ops:
			_wall_run(root, r, origin, axis, cursor, op[0], 0.0, size.y, wall_mat, base, side)
			var oh: float = op[2] if op.size() > 2 else 2.3
			_wall_run(root, r, origin, axis, op[0], op[0] + op[1], oh, size.y, wall_mat, base, side)  # lintel
			_door_frame(root, r, origin, axis, op[0], op[1], oh, side)
			cursor = op[0] + op[1]
		_wall_run(root, r, origin, axis, cursor, length, 0.0, size.y, wall_mat, base, side)
	return root

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var c := a.duplicate()
	c.merge(b, true)
	return c

static func _wall_run(root: Node3D, r: Dictionary, origin: Vector3, axis: Vector3, from: float, to: float, y0: float, y1: float, mat: Material, base: Dictionary, side: String) -> void:
	var len := to - from
	if len <= 0.01 or y1 - y0 <= 0.01:
		return
	var center := origin + axis * (from + len / 2) + Vector3(0, (y0 + y1) / 2, 0)
	var ext := Vector3(len if axis.x != 0 else WALL_T, y1 - y0, len if axis.z != 0 else WALL_T)
	_box(root, center, ext, mat, true)
	if y0 > 0.0 or r.get("outdoor", false):
		return
	var inward: Vector3 = {"n": Vector3(0, 0, 1), "s": Vector3(0, 0, -1), "w": Vector3(1, 0, 0), "e": Vector3(-1, 0, 0)}[side]
	var trim_col: Color = r.get("trim", Color(0.12, 0.08, 0.06))
	var thin := func(h: float, depth: float) -> Vector3:
		return Vector3(len if axis.x != 0 else depth, h, len if axis.z != 0 else depth)
	# Wainscot panel + chair rail, or a plain baseboard.
	var wains: String = r.get("wainscot", "")
	if wains != "":
		var wh: float = r.get("wainscot_height", 1.1)
		_box(root, center + inward * (WALL_T / 2 + 0.02) + Vector3(0, wh / 2 - center.y, 0), thin.call(wh, 0.04),
			Mats.surface(wains, _merge(base, {"tile_size": 1.2, "grime_amount": 0.35})), false)
		_box(root, center + inward * (WALL_T / 2 + 0.05) + Vector3(0, wh - center.y, 0), thin.call(0.07, 0.07), Mats.trim(trim_col, 0.35), false)
	_box(root, center + inward * (WALL_T / 2 + 0.03) + Vector3(0, 0.07 - center.y, 0), thin.call(0.14, 0.05), Mats.trim(trim_col, 0.5), false)
	# Crown moulding under the ceiling.
	_box(root, center + inward * (WALL_T / 2 + 0.04) + Vector3(0, (y1 - 0.08) - center.y, 0), thin.call(0.16, 0.08), Mats.trim(trim_col.lightened(0.6), 0.6), false)

static func _door_frame(root: Node3D, r: Dictionary, origin: Vector3, axis: Vector3, at: float, width: float, h: float, _side: String) -> void:
	if r.get("outdoor", false):
		return
	var col: Color = r.get("trim", Color(0.12, 0.08, 0.06))
	var depth := WALL_T + 0.08
	for edge in [at, at + width]:
		var c: Vector3 = origin + axis * edge + Vector3(0, h / 2, 0)
		_box(root, c, Vector3(0.1 if axis.x != 0 else depth, h, 0.1 if axis.z != 0 else depth), Mats.trim(col, 0.4), false)
	var top := origin + axis * (at + width / 2) + Vector3(0, h + 0.05, 0)
	_box(root, top, Vector3(width + 0.2 if axis.x != 0 else depth, 0.12, width + 0.2 if axis.z != 0 else depth), Mats.trim(col, 0.4), false)

static func _box(root: Node3D, center: Vector3, ext: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = ext
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	root.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = ext
		cs.shape = bs
		sb.add_child(cs)
		sb.position = center
		root.add_child(sb)

## Places a Poly Haven model with an automatic box collider fitted to its mesh.
static func prop(parent: Node3D, name: String, pos: Vector3, rot_deg := 0.0, scale := 1.0, collide := true) -> Node3D:
	var path := "res://assets/polyhaven/models/%s/%s.gltf" % [name, name]
	var node: Node3D
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate()
	else:
		node = Node3D.new()
	node.position = pos
	node.rotation_degrees.y = rot_deg
	node.scale = Vector3.ONE * scale
	parent.add_child(node)
	if collide:
		var aabb := _aabb(node, Transform3D.IDENTITY)
		if aabb.size.length() > 0.05:
			var sb := StaticBody3D.new()
			sb.collision_layer = 1
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = aabb.size
			cs.shape = bs
			cs.position = aabb.get_center()
			sb.add_child(cs)
			node.add_child(sb)
	return node

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		if c is Node3D:
			var cx: Transform3D = xf * c.transform
			var a := AABB()
			var has := false
			if c is MeshInstance3D and c.mesh:
				a = cx * c.mesh.get_aabb()
				has = true
			var sub := _aabb(c, cx)
			if sub.size != Vector3.ZERO:
				a = sub if not has else a.merge(sub)
				has = true
			if has:
				out = a if first else out.merge(a)
				first = false
	return out

## Room light helper: warm/cold key light with optional flicker.
static func light(parent: Node3D, pos: Vector3, color: Color, energy := 1.5, range_m := 8.0, shadows := false, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	parent.add_child(l)
	if flicker:
		l.set_script(preload("res://scripts/world/flicker.gd"))
	return l
