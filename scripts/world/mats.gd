class_name Mats
## Builds level materials from the fetched Poly Haven sets (see tools/assets_manifest.json).
## Each room passes its own tint, grime and wetness, so rooms that share a texture
## still look like different places.

const TEX_ROOT := "res://assets/polyhaven/textures/"
static var _cache: Dictionary = {}

static func surface(slot: String, opts: Dictionary = {}) -> Material:
	var key := slot + JSON.stringify(opts)
	if _cache.has(key):
		return _cache[key]
	var dir := TEX_ROOT + slot + "/"
	var m: Material
	if ResourceLoader.exists(dir + "albedo.jpg"):
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/surface.gdshader")
		sm.set_shader_parameter("albedo_tex", load(dir + "albedo.jpg"))
		sm.set_shader_parameter("normal_tex", load(dir + "normal.jpg"))
		sm.set_shader_parameter("arm_tex", load(dir + "arm.jpg"))
		for k in opts:
			sm.set_shader_parameter(k, opts[k])
		m = sm
	else:
		# Assets not fetched yet: a neutral but still lit material.
		var std := StandardMaterial3D.new()
		std.albedo_color = opts.get("tint", Color(0.5, 0.5, 0.5))
		std.roughness = 0.8
		m = std
	_cache[key] = m
	return m

static func trim(color: Color, rough := 0.45, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
