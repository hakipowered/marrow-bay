class_name RoomBuilder
## Builds rooms from compact data so the whole level stays readable as code.
##
## room = {
##   id, pos: Vector3 (floor corner), size: Vector3 (w, h, d),
##   floor, wall, ceiling: texture slots, wainscot: slot or "",
##   look: {tint, grime_amount, stain_amount, wetness, ...} (surface shader params),
##   openings: {"n": [[offset, width, height, {frame}]], "s": [...], "e": [...], "w": [...]},
##   outdoor: bool (no ceiling), trim: Color,
##   windows: {"n": [[offset, width, sill, top, {boards, moon, frame}]]} (moonlit, optional planks),
##   skip_walls: ["e"] (a neighbour's wall stands there), wall_range: {"e": [from, to]} (only that
##   stretch of the side gets a wall), wall_inset: {"s": 0.25} (see below),
##   pilasters: {sides, spacing, width, depth, slot}, beams: {axis "x"|"z"|"both", spacing, depth, width, slot},
##   decals: {"blood": n, "stain": n, "scorch": n, "wall_blood": n}, papers: n, probe: bool,
##   ceiling_holes: [[x, z, w, d]] (local; a broken-through hole with a dark crawlspace above)
## }
##
## Two rooms must never both build a wall in the same place: the renderer
## can't tell which is in front and the two textures flicker through each
## other in big triangles. Either one room skips that side, or one insets its
## wall (wall_inset = WALL_T) so it stands flush against the neighbour's,
## back to back. A doorway or window through such a double wall gets one
## frame from the inset room, deep enough to line both walls; the neighbour
## leaves its own out ({"frame": false}). tests/wall_overlap.gd checks this.

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

	# Floors and ceilings are split into chunks: the Mobile renderer caps how many
	# lights and decals touch one mesh, so one giant slab would drop lights.
	var floor_mat := Mats.surface(r["floor"], _merge(base, r.get("floor_look", {"tile_size": 2.0})))
	_chunked(root, size, -0.1, floor_mat)
	if not r.get("outdoor", false):
		var ceil_look := _merge(base, {"grime_amount": 0.0, "stain_amount": 0.0, "tile_size": 3.0})
		var holes: Array = r.get("ceiling_holes", [])
		_chunked(root, size, size.y + 0.1, Mats.surface(r.get("ceiling", "ceiling"), _merge(ceil_look, r.get("ceiling_look", {}))), holes)
		for h in holes:
			_crawlspace(root, size.y + 0.2, h)

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
		# wall_inset pulls a wall into the room so it can sit flush against a
		# neighbour's wall without the two fighting over the same pixels.
		var origin: Vector3 = sides[side][0] + _inward(side) * r.get("wall_inset", {}).get(side, 0.0)
		var axis: Vector3 = sides[side][1]
		var span: Array = r.get("wall_range", {}).get(side, [0.0, sides[side][2]])
		var length: float = span[1]
		var ops: Array = []
		for op in openings.get(side, []):
			var o: Dictionary = op[3] if op.size() > 3 else {}
			ops.append({"at": op[0], "w": op[1], "h": op[2] if op.size() > 2 else 2.3, "window": false, "frame": o.get("frame", true)})
		# Windows that overlap along the wall form one column (one pane per
		# storey, each with its own width): a narrow ground-floor window under
		# a wide upper one shares the gap in the wall instead of the wall
		# below one pane filling half of the other.
		var columns: Array = []
		for wn in r.get("windows", {}).get(side, []):
			var pane := [wn[2], wn[3], wn[4] if wn.size() > 4 else {}, wn[0], wn[1]]
			var col: Dictionary = {}
			for c in columns:
				if wn[0] < c["at"] + c["w"] - 0.01 and wn[0] + wn[1] > c["at"] + 0.01:
					col = c
					break
			if col.is_empty():
				col = {"at": wn[0], "w": wn[1], "panes": [], "window": true}
				columns.append(col)
			var end: float = maxf(col["at"] + col["w"], wn[0] + wn[1])
			col["at"] = minf(col["at"], wn[0])
			col["w"] = end - col["at"]
			col["panes"].append(pane)
		for c in columns:
			c["panes"].sort_custom(func(a, b): return a[0] < b[0])
			ops.append(c)
		ops.sort_custom(func(a, b): return a["at"] < b["at"])
		var cursor: float = span[0]
		for op in ops:
			var at: float = op["at"]
			var w: float = op["w"]
			_wall_run(root, r, origin, axis, cursor, at, 0.0, size.y, wall_mat, base, side)
			if op["window"]:
				var y := 0.0
				for pane in op["panes"]:
					var pa: float = pane[3]
					var pw: float = pane[4]
					_wall_run(root, r, origin, axis, at, at + w, y, pane[0], wall_mat, base, side)
					# Wall beside a pane narrower than its column.
					_wall_run(root, r, origin, axis, at, pa, pane[0], pane[1], wall_mat, base, side)
					_wall_run(root, r, origin, axis, pa + pw, at + w, pane[0], pane[1], wall_mat, base, side)
					_window(root, r, origin, axis, pa, pw, pane[0], pane[1], side, pane[2])
					y = pane[1]
				_wall_run(root, r, origin, axis, at, at + w, y, size.y, wall_mat, base, side)
			else:
				_wall_run(root, r, origin, axis, at, at + w, op["h"], size.y, wall_mat, base, side)  # lintel
				if op["frame"]:
					_door_frame(root, r, origin, axis, at, w, op["h"], side)
			cursor = at + w
		_wall_run(root, r, origin, axis, cursor, length, 0.0, size.y, wall_mat, base, side)
		if not r.get("outdoor", false):
			# One continuous crown moulding per wall, also over windows and doors.
			var inward := _inward(side)
			var trim_col: Color = r.get("trim", Color(0.12, 0.08, 0.06))
			var run: float = span[1] - span[0]
			var c: Vector3 = origin + axis * ((span[0] + span[1]) / 2) + inward * (WALL_T / 2 + 0.05) + Vector3(0, size.y - 0.1, 0)
			_box(root, c, Vector3(run if axis.x != 0 else 0.1, 0.2, run if axis.z != 0 else 0.1), Mats.trim(trim_col.lightened(0.6), 0.6), false)
	_dress(root, r, size, base)
	return root

static func _inward(side: String) -> Vector3:
	return {"n": Vector3(0, 0, 1), "s": Vector3(0, 0, -1), "w": Vector3(1, 0, 0), "e": Vector3(-1, 0, 0)}[side]

static func _chunked(root: Node3D, size: Vector3, y: float, mat: Material, holes: Array = []) -> void:
	const CHUNK := 6.0
	var nx := maxi(1, ceili(size.x / CHUNK))
	var nz := maxi(1, ceili(size.z / CHUNK))
	var cx := size.x / nx
	var cz := size.z / nz
	for i in nx:
		for j in nz:
			var rects: Array = [Rect2(cx * i, cz * j, cx, cz)]
			for h in holes:
				var cut := Rect2(h[0], h[1], h[2], h[3])
				var left: Array = []
				for rc in rects:
					left.append_array(_minus(rc, cut))
				rects = left
			for rc in rects:
				_box(root, Vector3(rc.get_center().x, y, rc.get_center().y), Vector3(rc.size.x, 0.2, rc.size.y), mat, true)

## The parts of `a` outside `cut`: up to four strips round the hole.
static func _minus(a: Rect2, cut: Rect2) -> Array:
	var c := a.intersection(cut)
	if c.size.x <= 0.001 or c.size.y <= 0.001:
		return [a]
	var out: Array = []
	if c.position.x > a.position.x:
		out.append(Rect2(a.position.x, a.position.y, c.position.x - a.position.x, a.size.y))
	if c.end.x < a.end.x:
		out.append(Rect2(c.end.x, a.position.y, a.end.x - c.end.x, a.size.y))
	if c.position.y > a.position.y:
		out.append(Rect2(c.position.x, a.position.y, c.size.x, c.position.y - a.position.y))
	if c.end.y < a.end.y:
		out.append(Rect2(c.position.x, c.end.y, c.size.x, a.end.y - c.end.y))
	return out

## Above a hole in the ceiling: a dark crawlspace (rough boards round it and
## a lid), broken joists and torn laths hanging into the hole, so looking up
## shows the inside of the building, never the sky or the void.
static func _crawlspace(root: Node3D, top: float, h: Array) -> void:
	var x0: float = h[0]
	var z0: float = h[1]
	var w: float = h[2]
	var d: float = h[3]
	var rise := 2.6
	var dark := Mats.trim(Color(0.07, 0.055, 0.045), 0.95)
	var wood := Mats.trim(Color(0.24, 0.17, 0.11), 0.85)
	var c := Vector3(x0 + w / 2, top + rise / 2, z0 + d / 2)
	for s in [-1.0, 1.0]:
		_box(root, c + Vector3(s * (w / 2 + 0.05), 0, 0), Vector3(0.1, rise, d + 0.2), dark, true)
		_box(root, c + Vector3(0, 0, s * (d / 2 + 0.05)), Vector3(w + 0.2, rise, 0.1), dark, true)
	_box(root, Vector3(c.x, top + rise + 0.05, c.z), Vector3(w + 0.2, 0.1, d + 0.2), dark, true)
	# A snapped joist across the hole, its ends hanging down, and a few laths.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(h))
	for s in [-1.0, 1.0]:
		var j := MeshInstance3D.new()
		var jb := BoxMesh.new()
		jb.size = Vector3(0.09, 0.16, d * 0.42)
		j.mesh = jb
		j.material_override = wood
		# Each half hangs from its edge of the hole, leaving the middle open.
		j.position = Vector3(x0 + w * 0.5 + rng.randf_range(-0.1, 0.1), top - 0.1, z0 + d * (0.5 + s * 0.38))
		j.rotation.x = -s * deg_to_rad(rng.randf_range(52.0, 64.0))
		root.add_child(j)
	for k in 5:
		var lath := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(rng.randf_range(0.25, 0.5), 0.015, 0.04)
		lath.mesh = lb
		lath.material_override = wood
		var edge := k % 4
		var px := x0 + (rng.randf_range(0.1, w - 0.1) if edge < 2 else (0.04 if edge == 2 else w - 0.04))
		var pz := z0 + (rng.randf_range(0.1, d - 0.1) if edge >= 2 else (0.04 if edge == 0 else d - 0.04))
		lath.position = Vector3(px, top - 0.24, pz)
		lath.rotation = Vector3(rng.randf_range(-0.9, 0.9), rng.randf() * TAU, rng.randf_range(-1.2, 1.2))
		root.add_child(lath)

## A real window: sill, frame, mullions, dirty moonlit glass, optional planks
## nailed across, and a cold spot light outside so the frame casts shadows inside.
static func _window(root: Node3D, r: Dictionary, origin: Vector3, axis: Vector3, at: float, w: float, sill: float, top: float, side: String, opts: Dictionary) -> void:
	var inward := _inward(side)
	var h := top - sill
	var center := origin + axis * (at + w / 2) + Vector3(0, sill + h / 2, 0)
	var along := func(l: float, hh: float, d: float) -> Vector3:
		return Vector3(l if axis.x != 0 else d, hh, l if axis.z != 0 else d)
	var frame_col: Color = opts.get("frame_color", Color(0.1, 0.07, 0.05))
	var fm := Mats.trim(frame_col, 0.5)
	# Through a double wall (this room's wall inset against a neighbour's)
	# the frame and sill line both walls; the neighbour builds none.
	var inset: float = r.get("wall_inset", {}).get(side, 0.0)
	var depth := WALL_T + 0.06 + inset
	var reveal := -inward * (inset / 2)
	if opts.get("frame", true):
		# Frame and stone sill.
		_box(root, center + reveal + Vector3(0, -h / 2 - 0.04, 0) + inward * 0.06, along.call(w + 0.3, 0.08, WALL_T + 0.18 + inset), Mats.trim(Color(0.42, 0.4, 0.37), 0.7), false)
		_box(root, center + reveal + Vector3(0, h / 2, 0), along.call(w + 0.1, 0.1, depth), fm, false)
		for e in [-1.0, 1.0]:
			_box(root, center + reveal + axis * (e * w / 2), along.call(0.1, h, depth), fm, false)
		# Mullions.
		_box(root, center, along.call(0.05, h, 0.06), fm, false)
		for k in [1, 2]:
			_box(root, center + Vector3(0, -h / 2 + h * k / 3.0, 0), along.call(w, 0.05, 0.06), fm, false)
	# Glass.
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	glass.mesh = q
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.3, 0.36, 0.45, 0.92 if opts.get("opaque", false) else 0.42)
	gm.emission_enabled = true
	gm.emission = Color(0.16, 0.22, 0.32)
	if opts.get("lit", false):
		# Someone's light is still on behind a curtain.
		gm.albedo_color = Color(0.55, 0.38, 0.2, 0.95)
		gm.emission = Color(1.0, 0.62, 0.3)
	elif opts.get("opaque", false):
		gm.albedo_color = Color(0.05, 0.06, 0.08, 0.95)
		gm.emission = Color(0.05, 0.07, 0.1)
	gm.emission_energy_multiplier = opts.get("glow", 0.7)
	gm.roughness = 0.15
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = center
	glass.rotation.y = 0.0 if axis.x != 0 else PI / 2
	root.add_child(glass)
	# Keep players and zombies inside.
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = along.call(w, h, WALL_T)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = center
	root.add_child(sb)
	# Planks nailed across from the inside.
	var boards: int = opts.get("boards", 0)
	if boards > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(r["id"]) + str(at) + side)
		var bm := Mats.surface("plank_painted", {"tile_size": 1.0, "grime_amount": 0.6})
		for b in boards:
			var plank := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = along.call(w + 0.4, 0.2, 0.04)
			plank.mesh = pb
			plank.material_override = bm
			plank.position = center + inward * (WALL_T / 2 + 0.04 + b * 0.01) + Vector3(0, -h / 2 + h * (b + 0.7) / (boards + 0.4), 0)
			root.add_child(plank)
			plank.rotate(inward, deg_to_rad(rng.randf_range(-24.0, 24.0)))
	# Moonlight through the window.
	if not opts.get("glass", true):
		glass.queue_free()
	else:
		# Shoot it (or blow it in) and it shatters.
		Breakable.make_glass(root, glass, sb, Vector2(w, h), "glass_%s_%s_%d_%d" % [r["id"], side, roundi(at * 10), roundi(sill * 10)])
	var moon: float = opts.get("moon", 3.0)
	if moon > 0.0:
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.55, 0.66, 0.95)
		sl.light_energy = moon
		sl.spot_range = opts.get("moon_range", 16.0)
		sl.spot_angle = 30.0
		sl.spot_attenuation = 0.8
		sl.shadow_enabled = true
		root.add_child(sl)
		var src := center - inward * 3.5 + Vector3(0, 3.0, 0)
		var dst: Vector3 = center + inward * float(opts.get("reach", 4.0)) + Vector3(0, -sill - h / 2, 0)
		sl.look_at_from_position(src, dst, axis)

## Pilasters, ceiling beams, decals, papers and a reflection probe.
static func _dress(root: Node3D, r: Dictionary, size: Vector3, base: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r["id"]))
	var pil: Dictionary = r.get("pilasters", {})
	if not pil.is_empty():
		var spacing: float = pil.get("spacing", 4.0)
		var pw: float = pil.get("width", 0.55)
		var pd: float = pil.get("depth", 0.16)
		var pmat := Mats.surface(pil.get("slot", "archive_marble"), _merge(base, {"tile_size": 1.2, "grime_amount": 0.35}))
		var cap := Mats.trim(pil.get("cap", Color(0.62, 0.58, 0.52)), 0.55)
		var top: float = pil.get("height", size.y)
		for side in pil.get("sides", ["n", "s", "e", "w"]):
			var length: float = size.x if side in ["n", "s"] else size.z
			var origin: Vector3 = {"n": Vector3.ZERO, "s": Vector3(0, 0, size.z), "w": Vector3.ZERO, "e": Vector3(size.x, 0, 0)}[side]
			var axis := Vector3(1, 0, 0) if side in ["n", "s"] else Vector3(0, 0, 1)
			var inward := _inward(side)
			origin += inward * r.get("wall_inset", {}).get(side, 0.0)
			var blocked: Array = []
			for op in r.get("openings", {}).get(side, []):
				blocked.append([op[0] - pw, op[0] + op[1] + pw])
			for wn in r.get("windows", {}).get(side, []):
				if wn[2] < top - 0.5:
					blocked.append([wn[0] - pw, wn[0] + wn[1] + pw])
			var n := int(floor(length / spacing))
			for i in range(1, n + 1):
				var t := length * i / (n + 1)
				var hit := false
				for bl in blocked:
					if t > bl[0] and t < bl[1]:
						hit = true
				if hit:
					continue
				var base_pos := origin + axis * t + inward * (WALL_T / 2 + pd / 2)
				var ext := func(wd: float, hh: float, dd: float) -> Vector3:
					return Vector3(wd if axis.x != 0 else dd, hh, wd if axis.z != 0 else dd)
				_box(root, base_pos + Vector3(0, top / 2, 0), ext.call(pw, top, pd), pmat, true)
				_box(root, base_pos + Vector3(0, 0.2, 0) + inward * 0.03, ext.call(pw + 0.14, 0.4, pd + 0.06), cap, false)
				_box(root, base_pos + Vector3(0, top - 0.32, 0) + inward * 0.04, ext.call(pw + 0.2, 0.26, pd + 0.08), cap, false)
	var beams: Dictionary = r.get("beams", {})
	if not beams.is_empty() and not r.get("outdoor", false):
		var bmat := Mats.surface(beams.get("slot", "archive_wainscot"), _merge(base, {"tile_size": 1.5, "grime_amount": 0.2}))
		var bd: float = beams.get("depth", 0.4)
		var bw: float = beams.get("width", 0.3)
		var sp: float = beams.get("spacing", 3.0)
		var ax: String = beams.get("axis", "x")
		if ax in ["x", "both"]:
			for i in range(1, int(size.z / sp) + 1):
				var z := size.z * i / (int(size.z / sp) + 1)
				_box(root, Vector3(size.x / 2, size.y - bd / 2, z), Vector3(size.x, bd, bw), bmat, false)
		if ax in ["z", "both"]:
			for i in range(1, int(size.x / sp) + 1):
				var x := size.x * i / (int(size.x / sp) + 1)
				_box(root, Vector3(x, size.y - bd / 2 - (0.02 if ax == "both" else 0.0), size.z / 2), Vector3(bw, bd, size.z), bmat, false)
	# Decals: blood, stains and scorch marks on the floor, blood smears on walls.
	var dec: Dictionary = r.get("decals", {})
	for kind in ["blood", "stain", "scorch"]:
		for i in dec.get(kind, 0):
			var d := Decal.new()
			d.texture_albedo = _decal_tex(kind, rng)
			var s := rng.randf_range(0.8, 2.2) if kind != "stain" else rng.randf_range(1.2, 3.0)
			d.size = Vector3(s, 0.6, s)
			d.modulate = Color(1, 1, 1, 0.85 if kind == "blood" else 0.55)
			d.position = Vector3(rng.randf_range(1.0, size.x - 1.0), 0.05, rng.randf_range(1.0, size.z - 1.0))
			d.rotation.y = rng.randf() * TAU
			root.add_child(d)
	for i in dec.get("wall_blood", 0):
		var side: String = ["n", "s", "e", "w"][rng.randi() % 4]
		var inward := _inward(side)
		var along := rng.randf_range(1.0, (size.x if side in ["n", "s"] else size.z) - 1.0)
		var p: Vector3 = {"n": Vector3(along, 0, WALL_T / 2), "s": Vector3(along, 0, size.z - WALL_T / 2), "w": Vector3(WALL_T / 2, 0, along), "e": Vector3(size.x - WALL_T / 2, 0, along)}[side]
		p += inward * r.get("wall_inset", {}).get(side, 0.0)
		var d := Decal.new()
		d.texture_albedo = _decal_tex("blood", rng)
		var s := rng.randf_range(0.7, 1.6)
		d.size = Vector3(s, 0.5, s)
		d.position = p + Vector3(0, rng.randf_range(0.6, 1.8), 0)
		root.add_child(d)
		var up := inward
		var right := Vector3.UP.cross(up).normalized()
		d.basis = Basis(right, up, right.cross(up)).rotated(up, rng.randf() * TAU)
	var papers: int = r.get("papers", 0)
	if papers > 0:
		# Printed, wet and trodden-on paper: a newspaper, an evacuation
		# flyer and an archive document, each with a cut-out torn outline.
		var wet: bool = r.get("outdoor", false)
		var pmats: Array = []
		var psizes := [Vector2(0.34, 0.45), Vector2(0.21, 0.28), Vector2(0.21, 0.28)]
		for k in range(1, 4):
			var m := StandardMaterial3D.new()
			m.albedo_texture = load("res://assets/textures/papers/paper_%d.png" % k)
			m.albedo_color = Color(0.42, 0.41, 0.4) if wet else Color(0.78, 0.76, 0.72)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.roughness = 0.45 if wet else 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			pmats.append(m)
		for i in papers:
			var mi := MeshInstance3D.new()
			var pq := PlaneMesh.new()
			var k := rng.randi() % 3
			pq.size = psizes[k] * rng.randf_range(0.85, 1.1)
			mi.mesh = pq
			mi.material_override = pmats[k]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(rng.randf_range(0.6, size.x - 0.6), 0.006 + i * 0.0004, rng.randf_range(0.6, size.z - 0.6))
			mi.rotation.y = rng.randf() * TAU
			root.add_child(mi)
	if r.get("probe", false):
		var rp := ReflectionProbe.new()
		rp.size = size + Vector3(0.5, 0.5, 0.5)
		rp.position = size / 2
		rp.box_projection = true
		rp.interior = not r.get("outdoor", false)
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		root.add_child(rp)

static var _decal_cache: Dictionary = {}
static func _decal_tex(kind: String, rng: RandomNumberGenerator) -> Texture2D:
	if not _decal_cache.has(kind):
		var arr: Array = []
		for i in range(1, 7):
			var path := "res://assets/textures/decals/%s_%d.png" % [kind, i]
			if ResourceLoader.exists(path):
				arr.append(load(path))
		_decal_cache[kind] = arr
	var a: Array = _decal_cache[kind]
	return null if a.is_empty() else a[rng.randi() % a.size()]

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
	var inward := _inward(side)
	var trim_col: Color = r.get("trim", Color(0.12, 0.08, 0.06))
	var thin := func(h: float, depth: float) -> Vector3:
		return Vector3(len if axis.x != 0 else depth, h, len if axis.z != 0 else depth)
	# Wainscot panel + chair rail, or a plain baseboard.
	var wains: String = r.get("wainscot", "")
	if wains != "" and r.get("wainscot_height", 1.1) < y1 - 0.05:
		var wh: float = r.get("wainscot_height", 1.1)
		_box(root, center + inward * (WALL_T / 2 + 0.02) + Vector3(0, wh / 2 - center.y, 0), thin.call(wh, 0.04),
			Mats.surface(wains, _merge(base, {"tile_size": 1.2, "grime_amount": 0.35})), false)
		_box(root, center + inward * (WALL_T / 2 + 0.05) + Vector3(0, wh - center.y, 0), thin.call(0.07, 0.07), Mats.trim(trim_col, 0.35), false)
	_box(root, center + inward * (WALL_T / 2 + 0.03) + Vector3(0, 0.07 - center.y, 0), thin.call(0.14, 0.05), Mats.trim(trim_col, 0.5), false)

static func _door_frame(root: Node3D, r: Dictionary, origin: Vector3, axis: Vector3, at: float, width: float, h: float, side: String) -> void:
	if r.get("outdoor", false):
		return
	var col: Color = r.get("trim", Color(0.12, 0.08, 0.06))
	# Through a double wall the frame lines both walls (see the header).
	var inset: float = r.get("wall_inset", {}).get(side, 0.0)
	var depth := WALL_T + 0.08 + inset
	var reveal := -_inward(side) * (inset / 2)
	for edge in [at, at + width]:
		var c: Vector3 = origin + reveal + axis * edge + Vector3(0, h / 2, 0)
		_box(root, c, Vector3(0.1 if axis.x != 0 else depth, h, 0.1 if axis.z != 0 else depth), Mats.trim(col, 0.4), false)
	var top := origin + reveal + axis * (at + width / 2) + Vector3(0, h + 0.05, 0)
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
## "kit/prefix" keeps only the parts of a multi-piece model whose names start
## with prefix (e.g. "vintage_suitcase/vintage_suitcase_01") and re-centres them.
static func prop(parent: Node3D, name: String, pos: Vector3, rot_deg := 0.0, scale := 1.0, collide := true) -> Node3D:
	var part := ""
	if "/" in name:
		part = name.get_slice("/", 1)
		name = name.get_slice("/", 0)
	var path := "res://assets/polyhaven/models/%s/%s.gltf" % [name, name]
	var node: Node3D
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate()
		if part != "":
			for c in node.get_children():
				if not str(c.name).begins_with(part):
					node.remove_child(c)
					c.free()
			var box := _aabb(node, Transform3D.IDENTITY)
			for c in node.get_children():
				if c is Node3D:
					c.position -= Vector3(box.get_center().x, 0, box.get_center().z)
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

## Global brightness tuning for every room light (checked on the Mobile renderer).
const LIGHT_SCALE := 1.9
const RANGE_SCALE := 1.3

## Room light helper: warm/cold key light with optional flicker.
static func light(parent: Node3D, pos: Vector3, color: Color, energy := 1.5, range_m := 8.0, shadows := false, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * LIGHT_SCALE
	l.omni_range = range_m * RANGE_SCALE
	l.omni_attenuation = 1.0
	l.shadow_enabled = shadows
	parent.add_child(l)
	if flicker:
		l.set_script(preload("res://scripts/world/flicker.gd"))
	return l

## Simple steel shelving unit with boxes and binders, for vaults and offices.
static func shelf_unit(parent: Node3D, pos: Vector3, rot_deg: float, w := 1.2, h := 1.9, d := 0.45, seed_key := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = rot_deg
	parent.add_child(n)
	var steel := Mats.trim(Color(0.22, 0.24, 0.25), 0.55, 0.6)
	var board := Mats.trim(Color(0.32, 0.33, 0.33), 0.7, 0.4)
	for x in [-w / 2 + 0.02, w / 2 - 0.02]:
		for z in [-d / 2 + 0.02, d / 2 - 0.02]:
			_box(n, Vector3(x, h / 2, z), Vector3(0.04, h, 0.04), steel, false)
	var levels := [0.08, h * 0.27, h * 0.51, h * 0.75, h - 0.03]
	for y in levels:
		_box(n, Vector3(0, y, 0), Vector3(w, 0.03, d), board, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + str(pos))
	for i in levels.size() - 1:
		var x := -w / 2 + 0.08
		while x < w / 2 - 0.25:
			var kind := rng.randi() % 4
			if kind == 0:
				x += rng.randf_range(0.1, 0.3)  # gap
				continue
			var bw := rng.randf_range(0.25, 0.45)
			var bh := minf(rng.randf_range(0.18, 0.34), levels[i + 1] - levels[i] - 0.05)
			var col := Color(0.55, 0.42, 0.28).darkened(rng.randf_range(0.0, 0.35)) if kind != 3 else Color(0.12, 0.14, 0.2).lightened(rng.randf_range(0.0, 0.3))
			_box(n, Vector3(x + bw / 2, levels[i] + 0.015 + bh / 2, rng.randf_range(-0.04, 0.04)), Vector3(bw, bh, d * 0.8), Mats.trim(col, 0.85), false)
			x += bw + 0.03
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, d)
	cs.shape = bs
	cs.position = Vector3(0, h / 2, 0)
	sb.add_child(cs)
	n.add_child(sb)
	return n

## String course: a stone band around the inside walls at a given height.
static func band(room: Node3D, size: Vector3, y: float, col := Color(0.5, 0.47, 0.42), h := 0.22) -> void:
	var m := Mats.trim(col, 0.65)
	var t := WALL_T / 2 + 0.06
	_box(room, Vector3(size.x / 2, y, t), Vector3(size.x, h, 0.12), m, false)
	_box(room, Vector3(size.x / 2, y, size.z - t), Vector3(size.x, h, 0.12), m, false)
	_box(room, Vector3(t, y, size.z / 2), Vector3(0.12, h, size.z), m, false)
	_box(room, Vector3(size.x - t, y, size.z / 2), Vector3(0.12, h, size.z), m, false)
