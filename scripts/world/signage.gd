class_name Signage
extends RefCounted
## Real signs and lettering for the levels, in place of floating text
## (Label3D). Every sign is a thing in the room, lit like everything else.
##
##   plate()  a plate fixed to a wall or a machine: vitreous enamel, painted
##            sheet steel, an engraved brass (or steel) plaque, a cast maker's
##            plate with raised letters, an engraved laminate panel label
##            (black face, white core), a printed card, a signwritten wooden
##            board or a clock dial. A real slab with edges that catch the
##            light and its bolts, screws or rivets; worn the way that kind of
##            sign wears: chipped enamel and rust bleeding from the bolt
##            holes, tarnish and lost wax in brass, paint rubbed off cast
##            letters, foxed and creased paper.
##   paint()  lettering painted straight onto a surface: stencilled paint,
##            chalk, a vinyl print. On a level wall it takes the wall's own
##            texture (shaders/sign_paint.gdshader samples the same brick
##            normals and mortar), so the paint follows every brick and skips
##            the deep joints instead of hovering in front of the wall.
##
## The letters are set at load time from the game's fonts into a small
## coverage mask (no texture files to ship): TextServer's own rasterised
## glyphs, blitted into an image (this works headless too). The shaders do
## the material and the wear, in the sign's own metres, so wear scales with
## the sign and no two signs share a pattern (each has its own seed).
##
## Placement: like the Label3Ds they replace, a sign faces local +z of its
## node, turned by `rot` (degrees about y, or a Vector3 of degrees). The back
## of a plate (or the painted face) lies on the node's plane, so place it ON
## the surface: a RoomBuilder wall's face is WALL_T / 2 in from the wall's
## line (plus any wall_inset).

const PLATE_SHADER := preload("res://shaders/sign_plate.gdshader")
const PAINT_SHADER := preload("res://shaders/sign_paint.gdshader")

const FONTS := {
	"sans": "res://assets/fonts/Oswald.ttf",
	"stencil": "res://assets/fonts/AllertaStencil.ttf",
	"roman": "res://assets/fonts/Cinzel.ttf",
	"serif": "res://assets/fonts/CormorantGaramond.ttf",
	"hand": "res://assets/fonts/Caveat.ttf",
	"chalk": "res://assets/fonts/RockSalt.ttf",
}
const STYLES := {"enamel": 0, "painted": 1, "brass": 2, "cast": 3, "engraved": 4, "card": 5, "dial": 6, "board": 7}
const PAINTS := {"stencil": 0, "chalk": 1, "print": 2, "brush": 3, "scratch": 4}
## Mask resolution: pixels per metre of sign, the most on a side, and the
## fewest down a side (small panel labels get more pixels per metre).
const PPM := 900.0
const MAX_PX := 1536
const MIN_PX := 96

static var _masks := {}
static var _fonts := {}
static var _fix_mats := {}

# ------------------------------------------------------------------ plates

## A plate on a wall or a machine. spec:
##   size      Vector2, metres (w, h)
##   style     "enamel" | "painted" | "brass" | "cast" | "engraved" | "card" | "dial" | "board"
##   lines     the text: Strings, or [String, scale]; set centred, filling the
##             plate inside `margin` (see mask())
##   field, ink, core   colours: the plate, the letters, what shows under
##             (enamel's iron, an engraved label's core, brass's wax is `ink`)
##   border    width (m) of a line round the plate, `border_inset` in from the edge
##   corner    corner radius (m); size.x / 2 on a square plate makes a disc
##   thick     plate thickness (m)
##   fix       "bolts" | "screws" | "rivets" | "none"; `fix_at` Array of
##             Vector2 (m from the centre, y up) to place them yourself
##   wear, dirt, rust   0..1
##   seed      any number (each sign gets its own wear)
##   bend      radius (m) to wrap the plate round a pipe or tank (0 = flat);
##             bend_axis "y" (round a vertical one) or "x" (a horizontal one)
##   back      true: a hanging tag, faced on both sides
##   dial      Vector4 for style "dial": track outer r, inner r, hour mark length, 1
## Returns the sign's MeshInstance3D (its node sits at `at`).
static func plate(parent: Node3D, at: Vector3, rot, spec: Dictionary) -> MeshInstance3D:
	var size: Vector2 = spec.get("size", Vector2(0.5, 0.2))
	var style: String = spec.get("style", "enamel")
	var thick: float = spec.get("thick", {"enamel": 0.004, "painted": 0.003, "brass": 0.004, "cast": 0.009,
		"engraved": 0.0025, "card": 0.0006, "dial": 0.003, "board": 0.022}.get(style, 0.004))
	var corner: float = spec.get("corner", minf(size.x, size.y) * (0.08 if style in ["enamel", "painted"] else 0.04))
	var seed: float = spec.get("seed", float(hash(str(spec.get("lines", ""))) % 997))
	var mi := MeshInstance3D.new()
	mi.name = spec.get("name", "Sign")
	_place(mi, at, rot)
	var mesh := _slab(size, corner, thick, spec.get("bend", 0.0), spec.get("bend_axis", "y"), spec.get("back", false))
	var mat := ShaderMaterial.new()
	mat.shader = PLATE_SHADER
	var fixes := _fixings(spec, size, style)
	var spec2 := spec
	if not fixes.is_empty() and not spec.has("margin"):
		# Keep the letters clear of the bolts.
		var m := Vector2(size.y * 0.14, size.y * 0.14)
		for f in fixes:
			if absf(f.y) < size.y * 0.25:
				m.x = maxf(m.x, size.x / 2 - absf(f.x) + f.z * 1.8)
			elif absf(f.x) < size.x * 0.25:
				m.y = maxf(m.y, size.y / 2 - absf(f.y) + f.z * 1.8)
			else:
				m.x = maxf(m.x, size.x / 2 - absf(f.x) + f.z * 1.8)
		spec2 = spec.duplicate()
		spec2["margin"] = m
	var tex := mask(spec2)
	mat.set_shader_parameter("mask", tex)
	mat.set_shader_parameter("texel", Vector2(1.0 / tex.get_width(), 1.0 / tex.get_height()))
	mat.set_shader_parameter("style", STYLES.get(style, 0))
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("corner", corner)
	var defaults := _colours(style)
	for k in ["field", "ink", "core"]:
		mat.set_shader_parameter(k, spec.get(k, defaults[k]))
	mat.set_shader_parameter("border", spec.get("border", 0.0))
	mat.set_shader_parameter("border_inset", spec.get("border_inset", clampf(minf(size.x, size.y) * 0.07, 0.003, 0.02)))
	mat.set_shader_parameter("wear", spec.get("wear", 0.5))
	mat.set_shader_parameter("dirt", spec.get("dirt", 0.45))
	mat.set_shader_parameter("rust", spec.get("rust", 0.5))
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("ink_metal", spec.get("ink_metal", 0.0))
	mat.set_shader_parameter("dial", spec.get("dial", Vector4.ZERO))
	var fv: Array = []
	for i in 8:
		fv.append(Vector4(fixes[i].x, fixes[i].y, fixes[i].z, 1.0) if i < fixes.size() else Vector4.ZERO)
	mat.set_shader_parameter("fix", fv)
	mesh.surface_set_material(0, mat)
	if not fixes.is_empty():
		_add_fixings(mesh, fixes, thick, spec.get("bend", 0.0), spec.get("bend_axis", "y"), spec.get("fix", "bolts"), style)
	mi.mesh = mesh
	parent.add_child(mi)
	return mi

static func _colours(style: String) -> Dictionary:
	match style:
		"brass":
			return {"field": Color(0.74, 0.55, 0.26), "ink": Color(0.035, 0.03, 0.025), "core": Color(0.3, 0.22, 0.1)}
		"cast":
			return {"field": Color(0.22, 0.05, 0.035), "ink": Color(0.82, 0.78, 0.66), "core": Color(0.33, 0.32, 0.3)}
		"engraved":
			return {"field": Color(0.025, 0.025, 0.025), "ink": Color(0.88, 0.87, 0.82), "core": Color(0.88, 0.87, 0.82)}
		"card":
			return {"field": Color(0.83, 0.79, 0.68), "ink": Color(0.08, 0.07, 0.08), "core": Color(0.6, 0.5, 0.36)}
		"board":
			return {"field": Color(0.2, 0.11, 0.06), "ink": Color(0.78, 0.6, 0.3), "core": Color(0.12, 0.07, 0.04)}
		"painted":
			return {"field": Color(0.16, 0.24, 0.18), "ink": Color(0.86, 0.83, 0.72), "core": Color(0.42, 0.17, 0.09)}
		_:
			return {"field": Color(0.86, 0.84, 0.76), "ink": Color(0.06, 0.06, 0.07), "core": Color(0.05, 0.045, 0.04)}

static func _place(n: Node3D, at: Vector3, rot) -> void:
	n.position = at
	if rot is Vector3:
		n.rotation_degrees = rot
	else:
		n.rotation_degrees.y = float(rot)

## Where the fixings go (m from the centre, y up) and their head radius.
static func _fixings(spec: Dictionary, size: Vector2, style: String) -> Array:
	var kind: String = spec.get("fix", {"card": "none", "dial": "none", "engraved": "screws", "brass": "screws", "cast": "rivets", "board": "screws"}.get(style, "bolts"))
	if kind == "none":
		return []
	var r: float = {"bolts": 0.0075, "screws": 0.0055, "rivets": 0.006}.get(kind, 0.006)
	if style == "engraved" or size.y < 0.05:
		r *= 0.55
	r = spec.get("fix_r", r)
	var out: Array = []
	if spec.has("fix_at"):
		for v in spec["fix_at"]:
			out.append(Vector3(v.x, v.y, r))
		return out
	var inset: float = clampf(minf(size.x, size.y) * 0.16, r * 2.2, 0.035)
	var hx := size.x / 2 - inset
	var hy := size.y / 2 - inset
	if size.y < 0.11 or size.x < 0.11:
		# A narrow strip: one each end.
		if size.x >= size.y:
			out = [Vector3(-hx, 0, r), Vector3(hx, 0, r)]
		else:
			out = [Vector3(0, hy, r), Vector3(0, -hy, r)]
	else:
		out = [Vector3(-hx, hy, r), Vector3(hx, hy, r), Vector3(-hx, -hy, r), Vector3(hx, -hy, r)]
	return out

## The plate itself: a rounded slab, front face mapped 0..1 (u right, v
## down), sides marked COLOR.r = 1, the back (only for tags) COLOR.g = 1.
static func _slab(size: Vector2, corner: float, thick: float, bend: float, axis: String, back: bool) -> ArrayMesh:
	var outline := _outline(size, corner)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Front: the convex outline cut into horizontal slabs, each split into
	# columns (and rows) fine enough to follow a bend.
	var ys: Array = []
	for v in outline:
		ys.append(snappedf(v.y, 0.00001))
	if bend > 0.0 and axis == "x":
		var n := int(ceil(size.y / maxf(bend * 0.12, 0.01)))
		for k in n + 1:
			ys.append(-size.y / 2 + size.y * k / n)
	var uniq: Array = []
	ys.sort()
	for y in ys:
		if uniq.is_empty() or y - uniq[-1] > 0.00005:
			uniq.append(y)
	var cols := 1
	if bend > 0.0 and axis == "y":
		cols = int(ceil(size.x / maxf(bend * 0.12, 0.01)))
	for i in uniq.size() - 1:
		var y0: float = uniq[i]
		var y1: float = uniq[i + 1]
		var a := _span(outline, y0 + 0.000001)
		var b := _span(outline, y1 - 0.000001)
		for c in cols:
			var t0 := float(c) / cols
			var t1 := float(c + 1) / cols
			var p00 := Vector2(lerpf(a.x, a.y, t0), y0)
			var p10 := Vector2(lerpf(a.x, a.y, t1), y0)
			var p01 := Vector2(lerpf(b.x, b.y, t0), y1)
			var p11 := Vector2(lerpf(b.x, b.y, t1), y1)
			# Godot's front faces wind clockwise.
			for p in [p00, p11, p10, p00, p01, p11]:
				_vert(st, p, thick, size, bend, axis, Color(0, 0, 0, 1), Vector3.BACK)
	# Sides.
	if thick > 0.0:
		var n := outline.size()
		for i in n:
			var p: Vector2 = outline[i]
			var q: Vector2 = outline[(i + 1) % n]
			var d := (q - p).normalized()
			var out := Vector3(d.y, -d.x, 0)   # outline runs counter-clockwise
			var steps := 1
			if bend > 0.0:
				steps = maxi(1, int(ceil(p.distance_to(q) / maxf(bend * 0.12, 0.01))))
			for s in steps:
				var a := p.lerp(q, float(s) / steps)
				var b := p.lerp(q, float(s + 1) / steps)
				var ca := Color(1, 0, 0, 1)
				_side(st, a, b, thick, size, bend, axis, ca, out)
	if back:
		for i in uniq.size() - 1:
			var y0: float = uniq[i]
			var y1: float = uniq[i + 1]
			var a := _span(outline, y0 + 0.000001)
			var b := _span(outline, y1 - 0.000001)
			var p00 := Vector2(a.x, y0)
			var p10 := Vector2(a.y, y0)
			var p01 := Vector2(b.x, y1)
			var p11 := Vector2(b.y, y1)
			for p in [p00, p10, p11, p00, p11, p01]:
				_vert(st, p, 0.0, size, bend, axis, Color(0, 1, 0, 1), Vector3.FORWARD)
	st.generate_tangents()
	return st.commit()

## The outline of a rounded rectangle (counter-clockwise, y up).
static func _outline(size: Vector2, corner: float) -> PackedVector2Array:
	var hx := size.x / 2
	var hy := size.y / 2
	var r := clampf(corner, 0.0, minf(hx, hy))
	var pts := PackedVector2Array()
	if r < 0.0005:
		return PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	var seg := clampi(int(r * 400.0), 3, 16)
	if is_equal_approx(r, minf(hx, hy)) and is_equal_approx(hx, hy):
		seg = 16   # a disc: 64 sides
	var centres := [Vector2(hx - r, -hy + r), Vector2(hx - r, hy - r), Vector2(-hx + r, hy - r), Vector2(-hx + r, -hy + r)]
	for c in 4:
		var a0 := -PI / 2 + c * PI / 2
		for k in seg + 1:
			var a := a0 + (PI / 2) * k / seg
			var p: Vector2 = centres[c] + Vector2(cos(a), sin(a)) * r
			if pts.is_empty() or pts[-1].distance_to(p) > 0.00001:
				pts.append(p)
	if pts[0].distance_to(pts[-1]) < 0.00001:
		pts.remove_at(pts.size() - 1)
	return pts

## Where the convex outline crosses the row y: Vector2(x left, x right).
static func _span(outline: PackedVector2Array, y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := outline.size()
	for i in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		if (a.y - y) * (b.y - y) <= 0.0 and absf(b.y - a.y) > 0.0000001:
			var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			lo = minf(lo, x)
			hi = maxf(hi, x)
	if lo > hi:
		return Vector2.ZERO
	return Vector2(lo, hi)

## A point of the plate (x, y in plate metres, z out from its back) after
## any bend, and its normal.
static func _bent(p: Vector2, z: float, bend: float, axis: String, nrm: Vector3) -> Array:
	if bend <= 0.0:
		return [Vector3(p.x, p.y, z), nrm]
	var r := bend + z
	if axis == "x":
		var t := p.y / bend
		var pos := Vector3(p.x, sin(t) * r, cos(t) * r - bend)
		return [pos, nrm.rotated(Vector3.LEFT, t)]
	var a := p.x / bend
	return [Vector3(sin(a) * r, p.y, cos(a) * r - bend), nrm.rotated(Vector3.UP, a)]

static func _uv(p: Vector2, size: Vector2) -> Vector2:
	return Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y)

static func _vert(st: SurfaceTool, p: Vector2, z: float, size: Vector2, bend: float, axis: String, col: Color, nrm: Vector3) -> void:
	var b := _bent(p, z, bend, axis, nrm)
	st.set_color(col)
	st.set_uv(_uv(p, size))
	st.set_normal(b[1])
	st.add_vertex(b[0])

static func _side(st: SurfaceTool, a: Vector2, b: Vector2, thick: float, size: Vector2, bend: float, axis: String, col: Color, out: Vector3) -> void:
	var quad := [[a, thick], [b, thick], [b, 0.0], [a, thick], [b, 0.0], [a, 0.0]]
	for q in quad:
		var bb := _bent(q[0], q[1], bend, axis, out)
		st.set_color(col)
		st.set_uv(_uv(q[0], size))
		st.set_normal(bb[1])
		st.add_vertex(bb[0])

## Bolt heads, screw heads or rivets into the sign's mesh, as its second
## surface.
static func _add_fixings(mesh: ArrayMesh, fixes: Array, thick: float, bend: float, axis: String, kind: String, style: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(fixes))
	for f in fixes:
		var r: float = f.z
		var place := _bent(Vector2(f.x, f.y), thick, bend, axis, Vector3.BACK)
		var nrm: Vector3 = place[1]
		var basis := Basis(Quaternion(Vector3.UP, nrm))
		var xf := Transform3D(basis, place[0])
		match kind:
			"bolts":
				var washer := CylinderMesh.new()
				washer.top_radius = r * 1.45
				washer.bottom_radius = r * 1.45
				washer.height = 0.0012
				washer.radial_segments = 12
				washer.rings = 1
				st.append_from(washer, 0, xf * Transform3D(Basis(), Vector3(0, 0.0006, 0)))
				var head := CylinderMesh.new()
				head.top_radius = r
				head.bottom_radius = r
				head.height = r * 0.7
				head.radial_segments = 6
				head.rings = 1
				st.append_from(head, 0, xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, 0.0012 + r * 0.35, 0)))
			"screws":
				var dome := SphereMesh.new()
				dome.radius = r
				dome.height = r * 0.9
				dome.radial_segments = 12
				dome.rings = 4
				dome.is_hemisphere = true
				st.append_from(dome, 0, xf * Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), Vector3.ZERO))
				var slot := BoxMesh.new()
				slot.size = Vector3(r * 1.9, r * 0.32, r * 0.22)
				st.append_from(slot, 0, xf * Transform3D(Basis(Vector3.UP, rng.randf() * PI), Vector3(0, r * 0.62, 0)))
			_:
				var rv := SphereMesh.new()
				rv.radius = r
				rv.height = r * 1.1
				rv.radial_segments = 10
				rv.rings = 4
				rv.is_hemisphere = true
				st.append_from(rv, 0, xf * Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3.ZERO))
	st.generate_tangents()
	st.commit(mesh)
	var key := kind + ":" + style
	if not _fix_mats.has(key):
		var m := StandardMaterial3D.new()
		if style == "brass" and kind == "screws":
			m.albedo_color = Color(0.5, 0.37, 0.17)
			m.metallic = 0.9
			m.roughness = 0.45
		elif style == "engraved":
			m.albedo_color = Color(0.55, 0.55, 0.53)
			m.metallic = 0.9
			m.roughness = 0.35
		elif style == "cast":
			m.albedo_color = Color(0.2, 0.08, 0.05)
			m.metallic = 0.4
			m.roughness = 0.65
		else:
			m.albedo_color = Color(0.2, 0.12, 0.07)
			m.metallic = 0.55
			m.roughness = 0.75
		_fix_mats[key] = m
	mesh.surface_set_material(mesh.get_surface_count() - 1, _fix_mats[key])

# ------------------------------------------------------------------ paint

## Lettering painted onto a surface. spec (and the mask() keys):
##   size     Vector2, metres
##   kind     "stencil" (sprayed or dabbed through a stencil: overspray,
##            the odd run), "chalk", "print" (a crisp vinyl or silkscreen
##            print), "brush" (signwritten), "scratch" (scored into it)
##   color    the paint
##   wear     0..1: worn away, faded
##   surface  the Material it's painted on. Left out, the nearest parent
##            with a "wall_mat" meta (RoomBuilder rooms set it) is used;
##            null or a plain material: flat (metal, glass)
##   rough, metal   the surface's own roughness and metalness, for a flat one
##   offset   gap off the surface (m), default 2.5 mm
##   bend, bend_axis   as plate()
##   back     true: seen from behind too, mirrored (print on clear glass)
static func paint(parent: Node3D, at: Vector3, rot, spec: Dictionary) -> MeshInstance3D:
	var size: Vector2 = spec.get("size", Vector2(1, 0.3))
	var kind: String = spec.get("kind", "stencil")
	var mi := MeshInstance3D.new()
	mi.name = spec.get("name", "Paint")
	_place(mi, at, rot)
	var off: float = spec.get("offset", 0.0025)
	mi.position += mi.basis.z * off
	var spec2 := spec.duplicate()
	if not spec2.has("font"):
		spec2["font"] = {"chalk": "chalk", "scratch": "chalk", "print": "sans", "brush": "sans"}.get(kind, "stencil")
	var mesh := _slab(size, 0.0, 0.0, spec.get("bend", 0.0), spec.get("bend_axis", "y"), spec.get("back", false))
	var mat := ShaderMaterial.new()
	mat.shader = PAINT_SHADER
	var tex := mask(spec2)
	mat.set_shader_parameter("mask", tex)
	mat.set_shader_parameter("texel", Vector2(1.0 / tex.get_width(), 1.0 / tex.get_height()))
	mat.set_shader_parameter("kind", PAINTS.get(kind, 0))
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("paint", spec.get("color", Color(0.86, 0.82, 0.7)))
	mat.set_shader_parameter("wear", spec.get("wear", 0.45))
	mat.set_shader_parameter("seed", spec.get("seed", float(hash(str(spec.get("lines", ""))) % 997)))
	mat.set_shader_parameter("base_rough", spec.get("rough", 0.6))
	mat.set_shader_parameter("base_metal", spec.get("metal", 0.0))
	var surf = spec.get("surface", _wall_mat(parent))
	if surf is ShaderMaterial and (surf as ShaderMaterial).get_shader_parameter("normal_tex") != null:
		var sm := surf as ShaderMaterial
		mat.set_shader_parameter("has_surface", true)
		for k in ["normal_tex", "arm_tex", "tile_size", "blend_sharpness", "grime_height", "grime_amount",
				"floor_y", "ceiling_y", "stain_amount", "normal_strength"]:
			var v = sm.get_shader_parameter(k)
			if v != null:
				mat.set_shader_parameter(k, v)
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _wall_mat(n: Node) -> Variant:
	while n != null:
		if n.has_meta("wall_mat"):
			return n.get_meta("wall_mat")
		n = n.get_parent()
	return null

# ------------------------------------------------------------------ the letters

static func font(id: String) -> Font:
	if not _fonts.has(id):
		var path: String = FONTS.get(id, id)
		var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
		# Our own copy at oversampling 1: otherwise the glyphs come out
		# scaled by the window's stretch (the UI's oversampling), smaller
		# than the advances they are set with.
		if f is FontFile:
			f = (f as FontFile).duplicate()
			(f as FontFile).oversampling = 1.0
		_fonts[id] = f
	return _fonts[id]

## The sign's letters as a coverage mask (L8, white = ink), mipmapped.
## spec keys:
##   size     Vector2, metres; ppm (pixels per metre, default PPM)
##   lines    Strings or [String, scale], stacked and centred, scaled
##            together to fill the plate inside `margin`; "" for a gap
##   font     a FONTS key or a font path; weight (variable fonts)
##   margin   Vector2 (m) clear round the text (default 12% of the height)
##   gap      gap between lines, as a fraction of the cap height (0.45)
##   track    letter spacing, as a fraction of the font size
##   align    "center" | "left" | "right"
##   arrow    "left" | "right": an arrow before / after the last line
##   items    free texts: {"text", "at" (Vector2 m from the centre, y up),
##            "h" (cap height, m), "font"}
##   max_h    the tallest a line's capitals may be (m), so short words don't
##            balloon to fill a big plate
##   strokes  straight marks: Vector4(ax, ay, bx, by), m from the centre (y
##            up), `stroke_w` wide (tally marks: see tally())
static func mask(spec: Dictionary) -> ImageTexture:
	var key := JSON.stringify([spec.get("size"), spec.get("lines", []), spec.get("font", "sans"), spec.get("margin"),
		spec.get("gap"), spec.get("track"), spec.get("align"), spec.get("arrow"), str(spec.get("items", [])), spec.get("weight"),
		spec.get("ppm"), spec.get("max_h"), str(spec.get("strokes", [])), spec.get("stroke_w")])
	if _masks.has(key):
		return _masks[key]
	var size: Vector2 = spec.get("size", Vector2(0.5, 0.2))
	var ppm: float = spec.get("ppm", PPM)
	if minf(size.x, size.y) * ppm < MIN_PX:
		ppm = MIN_PX / maxf(minf(size.x, size.y), 0.001)
	if maxf(size.x, size.y) * ppm > MAX_PX:
		ppm = MAX_PX / maxf(size.x, size.y)
	var w := maxi(16, int(round(size.x * ppm)))
	var h := maxi(16, int(round(size.y * ppm)))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var fnt := font(spec.get("font", "sans"))
	var margin: Vector2 = spec.get("margin", Vector2(size.y * 0.14, size.y * 0.14))
	var area := Vector2(w, h) - margin * ppm * 2.0
	var lines: Array = []
	for l in spec.get("lines", []):
		lines.append(l if l is Array else [l, 1.0])
	if not lines.is_empty() and area.x > 4 and area.y > 4:
		_set_lines(img, lines, spec, fnt, margin * ppm, area, ppm)
	for it in spec.get("items", []):
		var f2 := font(it.get("font", spec.get("font", "sans")))
		var cap: float = it.get("h", 0.02) * ppm
		var at: Vector2 = it.get("at", Vector2.ZERO)
		var c := Vector2(w / 2.0 + at.x * ppm, h / 2.0 - at.y * ppm)
		_set_text(img, it["text"], f2, cap, c, spec.get("track", 0.0), spec.get("weight", 0), "center")
	var sw: float = spec.get("stroke_w", 0.006) * ppm
	for st in spec.get("strokes", []):
		var a := Vector2(w / 2.0 + st.x * ppm, h / 2.0 - st.y * ppm)
		var b := Vector2(w / 2.0 + st.z * ppm, h / 2.0 - st.w * ppm)
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		# A scored or chalked mark: full width in the middle, tapering off
		# at both ends.
		var mid := (a + b) / 2.0
		_fill_convex(img, [a, mid + n * sw / 2.0 - d * 0.0, b, mid - n * sw / 2.0])
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_masks[key] = tex
	return tex

## Stacks the lines into the area, all scaled by one factor so they keep
## their relative sizes, centred both ways.
static func _set_lines(img: Image, lines: Array, spec: Dictionary, fnt: Font, margin: Vector2, area: Vector2, ppm: float) -> void:
	const BASE := 100.0
	var track: float = spec.get("track", 0.0)
	var weight: int = spec.get("weight", 0)
	var gap: float = spec.get("gap", 0.45)
	var arrow: String = spec.get("arrow", "")
	var widths: Array = []
	var caps: Array = []
	for l in lines:
		var s: float = l[1]
		var m := _measure(l[0], fnt, BASE * s, track, weight)
		var cap := _cap(fnt, BASE * s, weight)
		var wd: float = m.x
		if arrow != "" and l == lines[-1]:
			wd += cap * 2.1
		widths.append(wd)
		caps.append(cap if l[0] != "" else cap)
	var total := 0.0
	var widest := 0.0
	for i in lines.size():
		total += caps[i]
		if i > 0:
			total += gap * (caps[i] + caps[i - 1]) / 2.0
		widest = maxf(widest, widths[i])
	var k := minf(area.x / maxf(widest, 1.0), area.y / maxf(total, 1.0))
	if spec.has("max_h"):
		var biggest := 0.0
		for c in caps:
			biggest = maxf(biggest, c)
		k = minf(k, spec["max_h"] * ppm / maxf(biggest, 1.0))
	var y := margin.y + (area.y - total * k) / 2.0
	var align: String = spec.get("align", "center")
	for i in lines.size():
		var cap_px: float = caps[i] * k
		var size_px := BASE * float(lines[i][1]) * k
		if i > 0:
			y += gap * (caps[i] + caps[i - 1]) / 2.0 * k
		var lw: float = widths[i] * k
		var x0 := margin.x + (area.x - lw) / 2.0
		if align == "left":
			x0 = margin.x
		elif align == "right":
			x0 = margin.x + area.x - lw
		var tx := x0
		if arrow == "left" and i == lines.size() - 1:
			_arrow(img, Vector2(x0, y), cap_px * 1.7, cap_px, true)
			tx += cap_px * 2.1
		if lines[i][0] != "":
			var adv := _blit(img, lines[i][0], fnt, size_px, Vector2(tx, y + cap_px), track, weight)
			if arrow == "right" and i == lines.size() - 1:
				_arrow(img, Vector2(tx + adv + cap_px * 0.4, y), cap_px * 1.7, cap_px, false)
		y += cap_px

## A text centred on c (its capitals' middle).
static func _set_text(img: Image, text: String, fnt: Font, cap_px: float, c: Vector2, track: float, weight: int, _align: String) -> void:
	var base_cap := _cap(fnt, 100.0, weight)
	var size_px := 100.0 * cap_px / maxf(base_cap, 1.0)
	var m := _measure(text, fnt, size_px, track, weight)
	_blit(img, text, fnt, size_px, Vector2(c.x - m.x / 2.0, c.y + cap_px / 2.0), track, weight)

static func _variant(fnt: Font, size_px: float, track: float, weight: int) -> Font:
	if track == 0.0 and weight == 0:
		return fnt
	var fv := FontVariation.new()
	fv.base_font = fnt
	if track != 0.0:
		fv.spacing_glyph = int(round(track * size_px))
	if weight > 0:
		fv.variation_opentype = {"wght": weight}
	return fv

## Width (and height) of a line set at size_px.
static func _measure(text: String, fnt: Font, size_px: float, track: float, weight: int) -> Vector2:
	if text == "":
		return Vector2.ZERO
	var tl := TextLine.new()
	tl.add_string(text, _variant(fnt, size_px, track, weight), maxi(1, int(round(size_px))))
	return tl.get_size()

## How tall the capitals are at size_px (the ink of "H").
static func _cap(fnt: Font, size_px: float, weight: int) -> float:
	var f := _variant(fnt, size_px, 0.0, weight)
	var ts := TextServerManager.get_primary_interface()
	var tl := TextLine.new()
	tl.add_string("H", f, maxi(1, int(round(size_px))))
	var glyphs: Array = ts.shaped_text_get_glyphs(tl.get_rid())
	for g in glyphs:
		var fs := Vector2i(g["font_size"], 0)
		var gs: Vector2 = ts.font_get_glyph_size(g["font_rid"], fs, g["index"])
		if gs.y > 0.0:
			return gs.y
	return size_px * 0.7

## Draws a line of text with its baseline at `at` (x = the pen's start).
## Returns how far the pen went.
static func _blit(img: Image, text: String, fnt: Font, size_px: float, at: Vector2, track: float, weight: int) -> float:
	var ts := TextServerManager.get_primary_interface()
	var tl := TextLine.new()
	tl.add_string(text, _variant(fnt, size_px, track, weight), maxi(1, int(round(size_px))))
	var glyphs: Array = ts.shaped_text_get_glyphs(tl.get_rid())
	var pen := at.x
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for g in glyphs:
		var frid: RID = g["font_rid"]
		var fs := Vector2i(g["font_size"], 0)
		var idx: int = g["index"]
		var ti: int = ts.font_get_glyph_texture_idx(frid, fs, idx)
		if ti >= 0 and frid.is_valid():
			var atlas: Image = ts.font_get_texture_image(frid, fs, ti)
			var uv: Rect2 = ts.font_get_glyph_uv_rect(frid, fs, idx)
			var off: Vector2 = ts.font_get_glyph_offset(frid, fs, idx)
			if atlas and uv.size.x >= 1 and uv.size.y >= 1:
				# Glyphs come as coverage in alpha: white over the black canvas.
				var rgba := atlas.get_region(Rect2i(uv.position, uv.size))
				rgba.convert(Image.FORMAT_RGBA8)
				var dst := Vector2i(int(round(pen + g["offset"].x + off.x)), int(round(at.y + g["offset"].y + off.y)))
				if bounds.intersects(Rect2i(dst, rgba.get_size())):
					img.blend_rect(rgba, Rect2i(Vector2i.ZERO, rgba.get_size()), dst)
		pen += float(g["advance"]) * g.get("repeat", 1)
	return pen - at.x

## Tally marks in fives (four down, one struck across), in rows, as
## strokes for mask() (m from the sign's centre). `counts`: marks per row.
## Each mark leans and wanders a little, as a hand makes them.
static func tally(counts: Array, size: Vector2, mark_h: float, seed_n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var out: Array = []
	var rows := counts.size()
	var row_gap := size.y / maxf(rows, 1)
	var step := mark_h * 0.24
	var group := step * 4.0 + mark_h * 0.45
	for r in rows:
		var y := size.y / 2.0 - row_gap * (r + 0.5)
		var x := -size.x / 2.0 + mark_h * 0.2
		var n: int = counts[r]
		for i in n:
			var k := i % 5
			var g0 := x + (i / 5) * group
			var jy := rng.randf_range(-0.08, 0.08) * mark_h
			if k < 4:
				var mx := g0 + k * step + rng.randf_range(-0.12, 0.12) * step
				var lean := rng.randf_range(-0.06, 0.12) * mark_h
				out.append(Vector4(mx - lean / 2, y - mark_h / 2 + jy, mx + lean / 2, y + mark_h / 2 + jy + rng.randf_range(-0.08, 0.04) * mark_h))
			else:
				out.append(Vector4(g0 - step * 0.6, y - mark_h * rng.randf_range(0.2, 0.35), g0 + step * 3.6, y + mark_h * rng.randf_range(0.15, 0.32)))
	return out

## A plain arrow (shaft and head), w x h pixels from top-left `at`.
static func _arrow(img: Image, at: Vector2, w: float, h: float, left: bool) -> void:
	var head := h * 0.95
	var shaft := h * 0.34
	var pts := [Vector2(0, h / 2 - shaft / 2), Vector2(w - head, h / 2 - shaft / 2), Vector2(w - head, 0.0),
		Vector2(w, h / 2), Vector2(w - head, h), Vector2(w - head, h / 2 + shaft / 2), Vector2(0, h / 2 + shaft / 2)]
	if left:
		for i in pts.size():
			pts[i].x = w - pts[i].x
	# Shaft and head as two convex pieces.
	var shaft_poly := [pts[0], pts[1], pts[5], pts[6]] if not left else [pts[6], pts[5], pts[1], pts[0]]
	var head_poly := [pts[2], pts[3], pts[4]] if not left else [pts[4], pts[3], pts[2]]
	for poly in [shaft_poly, head_poly]:
		var moved: Array = []
		for p in poly:
			moved.append(p + at)
		_fill_convex(img, moved)

## Fills a convex polygon (pixels), anti-aliased by distance to its edges.
static func _fill_convex(img: Image, poly: Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	# Winding: make the edge normals point out.
	var area := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var edges: Array = []
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x) * sgn
		edges.append([n, n.dot(a)])
	var x0 := maxi(0, int(floor(lo.x)) - 1)
	var x1 := mini(img.get_width() - 1, int(ceil(hi.x)) + 1)
	var y0 := maxi(0, int(floor(lo.y)) - 1)
	var y1 := mini(img.get_height() - 1, int(ceil(hi.y)) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var dmax := -INF
			for e in edges:
				dmax = maxf(dmax, (e[0] as Vector2).dot(p) - e[1])
			var cov := clampf(0.5 - dmax, 0.0, 1.0)
			if cov > 0.0:
				var c := img.get_pixel(x, y)
				var v := maxf(c.r, cov)
				img.set_pixel(x, y, Color(v, v, v, 1.0))
