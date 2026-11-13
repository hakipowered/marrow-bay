extends Node
## Runtime decals (blood, bullet holes) with a cap so mobile GPUs stay happy.
## Textures: res://assets/textures/decals/<kind>_N.png (falls back to tinted blobs).

const MAX_DECALS := 80
var _live: Array = []
var _tex: Dictionary = {}

func _textures(kind: String) -> Array:
	if _tex.has(kind):
		return _tex[kind]
	var out := []
	for i in range(1, 7):
		var p := "res://assets/textures/decals/%s_%d.png" % [kind, i]
		if ResourceLoader.exists(p):
			out.append(load(p))
	if out.is_empty():
		out.append(_blob(Color(0.3, 0.0, 0.0, 0.85) if kind == "blood" else Color(0.05, 0.05, 0.05, 0.9)))
	_tex[kind] = out
	return out

func _blob(c: Color) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var n := 0.75 + 0.25 * sin(x * 0.7) * cos(y * 0.5)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clamp((1.0 - d) * 2.0 * n, 0, 1) * c.a))
	return ImageTexture.create_from_image(img)

## Default sizes (metres across) by kind; blood varies.
const SIZE := {"bullet_hole": 0.14, "scorch": 2.5, "acid": 0.7}

func splat(kind: String, pos: Vector3, normal: Vector3, size := -1.0) -> Decal:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var d := Decal.new()
	d.texture_albedo = _textures(kind).pick_random()
	var s: float = size if size > 0.0 else (randf_range(0.5, 1.1) if kind == "blood" else SIZE.get(kind, 0.08))
	d.size = Vector3(s, 0.3, s)
	d.cull_mask = 1
	scene.add_child(d)
	d.global_position = pos
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	d.global_basis = Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	_live.append(d)
	if _live.size() > MAX_DECALS:
		var old = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d
