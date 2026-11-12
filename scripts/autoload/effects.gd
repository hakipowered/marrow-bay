extends Node
## Visual effects: muzzle blasts, bullet tracers, impact sparks and dust, blood
## sprays, drops and stains, fire, smoke, the flamethrower's stream, burning
## infected and explosions.
##
## Flames, smoke, flashes and blood are photographed sprites keyed out of
## generated sheets (assets/textures/fx, made by tools/fx/make_fx_textures.py),
## so nothing reads as the flat squares the old particles were. Streaks
## (tracers, sparks, drops) and anything stretched along a direction (a blast
## along the barrel, a spray along the shot) use shaders/fx/fx_axial, which
## turns a quad to the camera around its own axis.
##
## One-shot bursts are CPUParticles3D that free themselves; anything that keeps
## burning (fires, the flamethrower) is GPUParticles3D.

const FIRE_TEX := preload("res://assets/textures/fx/fire_atlas.png")
const FIREBALL_TEX := preload("res://assets/textures/fx/fireball_atlas.png")
const SMOKE_TEX := preload("res://assets/textures/fx/smoke_atlas.png")
const MUZZLE_TEX := preload("res://assets/textures/fx/muzzle_atlas.png")
const SPRAY_TEX := preload("res://assets/textures/fx/blood_spray_atlas.png")
const AXIAL_ADD := preload("res://shaders/fx/fx_axial_add.gdshader")
const AXIAL_MIX := preload("res://shaders/fx/fx_axial_mix.gdshader")

## How big each gun's blast is (1 = a pistol-sized flash, a bit bigger).
const FLASH_SIZE := {"p9": 0.8, "vk18": 0.8, "bastion": 1.35, "hornet": 0.75, "m12": 1.5,
	"breacher": 1.4, "longshot": 1.45, "carbine": 1.0, "gl": 0.9, "rocket": 1.7}
const MAX_PATCHES := 6          # burning puddles the flamethrower leaves at once
const BLOOD_DECAL_GAP := 90     # ms between blood stains from one burst source

var _mats := {}
var slowmo := 1.0   # < 1 slows new bursts down (for checking them in renders)
var _compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
var _flickers: Array = []        # [light, base energy]
var _burns: Array = []           # [fire node, until msec]
var _streams := {}               # shooter instance id -> {node, last}
var _patches: Array = []         # [fire node, until msec]
var _last_patch := 0
var _last_blood_decal := 0
var _blood_frame := -1
var _blood_pos := Vector3.ZERO

func _scene() -> Node:
	return get_tree().current_scene

func _now() -> int:
	return Time.get_ticks_msec()

# ---------------------------------------------------------------- materials

## A camera-facing sprite from a 2x2 atlas (frames picked per particle).
func _sprite_mat(tex: Texture2D, additive: bool, boost := 1.0, soft := 0.0) -> StandardMaterial3D:
	var key := "s%s%s%.2f%.2f" % [tex.resource_path, additive, boost, soft]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this a particle's scale (scale_amount, scale curves) is thrown
	# away and every sprite is drawn the size of its quad.
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 2
	m.particles_anim_v_frames = 2
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = Color(boost, boost, boost, 1.0)
	m.disable_receive_shadows = true
	if soft > 0.0 and not _compat:
		# Fades where it meets a wall or the floor instead of a hard seam
		# (needs the depth texture, which the GL renderer doesn't give).
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = soft
	_mats[key] = m
	return m

## A streak (mode 0) or an atlas sprite stretched along a direction (mode 1).
func _axial_mat(additive: bool, width: float, tint: Color, energy := 1.0, tex: Texture2D = null, first := 0, count := 1, tail_fade := 1.5) -> ShaderMaterial:
	var key := "a%s%.3f%s%.2f%s%d%d%.2f" % [additive, width, tint, energy, tex.resource_path if tex else "", first, count, tail_fade]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = AXIAL_ADD if additive else AXIAL_MIX
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("tail_fade", tail_fade)
	m.set_shader_parameter("mode", 1 if tex else 0)
	if tex:
		m.set_shader_parameter("atlas", tex)
		m.set_shader_parameter("first_frame", first)
		m.set_shader_parameter("frame_count", count)
	_mats[key] = m
	return m

func _quad(w: float, h: float, anchored := false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	if anchored:
		q.center_offset = Vector3(0, h * 0.5, 0)   # starts at the emitter
	return q

func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	return c

func _ramp(points: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(p): return p[0]))
	g.colors = PackedColorArray(points.map(func(p): return p[1]))
	return g

## A one-shot burst of particles that frees itself.
func _burst(pos: Vector3, mesh: Mesh, mat: Material, o: Dictionary) -> CPUParticles3D:
	var scene := _scene()
	if scene == null:
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = o.get("explosiveness", 1.0)
	p.amount = maxi(int(o.get("amount", 8)), 1)
	p.lifetime = maxf(o.get("life", 0.5), 0.02)
	p.lifetime_randomness = o.get("life_rand", 0.0)
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = o.get("dir", Vector3.UP)
	p.spread = o.get("spread", 30.0)
	p.initial_velocity_min = o.get("vmin", 1.0)
	p.initial_velocity_max = o.get("vmax", 2.0)
	p.gravity = o.get("gravity", Vector3(0, -9.8, 0))
	p.damping_min = o.get("damp", 0.0)
	p.damping_max = o.get("damp", 0.0)
	p.scale_amount_min = o.get("smin", 1.0)
	p.scale_amount_max = o.get("smax", 1.0)
	if o.has("scurve"):
		p.scale_amount_curve = _curve(o["scurve"])
	if o.has("ramp"):
		p.color_ramp = _ramp(o["ramp"])
	p.color = o.get("color", Color.WHITE)
	p.angle_min = o.get("amin", 0.0)
	p.angle_max = o.get("amax", 0.0)
	p.anim_offset_min = o.get("frame_min", 0.0)
	p.anim_offset_max = o.get("frame_max", 1.0)
	p.particle_flag_align_y = o.get("align", false)
	if o.has("sphere"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = o["sphere"]
	if not o.get("additive", true):
		p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.speed_scale = slowmo
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime / slowmo + 0.3, false).timeout.connect(p.queue_free)
	return p

func _light(pos: Vector3, color: Color, energy: float, range_m: float, secs: float, fade := false) -> void:
	var scene := _scene()
	if scene == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	scene.add_child(l)
	l.global_position = pos
	if fade:
		var t := l.create_tween()
		t.tween_property(l, "light_energy", 0.0, secs).set_ease(Tween.EASE_OUT)
		t.tween_callback(l.queue_free)
	else:
		get_tree().create_timer(secs, false).timeout.connect(l.queue_free)

# ---------------------------------------------------------------- guns

## The blast at the end of a barrel: a flame along the barrel, a bright star
## at the muzzle, a flash of light and a wisp of smoke.
func muzzle_flash(pos: Vector3, dir: Vector3, weapon_id := "") -> void:
	var s: float = FLASH_SIZE.get(weapon_id, 1.0) * randf_range(0.85, 1.15)
	dir = dir.normalized()
	var blast := _axial_mat(true, 0.24 * s, Color(1.0, 0.72, 0.38), 1.5, MUZZLE_TEX, 0, 2)
	_burst(pos, _quad(1.0, 0.24 * s, true), blast, {"amount": 1, "life": 0.055, "dir": dir, "spread": 0.0,
		"vmin": 0.01, "vmax": 0.01, "gravity": Vector3.ZERO, "align": true})
	_burst(pos, _quad(1, 1), _sprite_mat(MUZZLE_TEX, true, 1.4), {"amount": 1, "life": 0.045, "spread": 0.0,
		"vmin": 0.0, "vmax": 0.0, "gravity": Vector3.ZERO, "smin": 0.12 * s, "smax": 0.15 * s,
		"color": Color(1.0, 0.78, 0.5),
		"amin": 0.0, "amax": 360.0, "frame_min": 0.5, "frame_max": 0.99})
	_light(pos + dir * 0.15, Color(1.0, 0.72, 0.4), 3.5 * s, 4.0 + 2.0 * s, 0.05)
	_burst(pos + dir * 0.1, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.2), {"amount": 3, "life": 1.0,
		"life_rand": 0.4, "dir": dir, "spread": 20.0, "vmin": 0.3, "vmax": 0.9, "damp": 1.5,
		"gravity": Vector3(0, 0.35, 0), "smin": 0.07 * s, "smax": 0.11 * s, "scurve": [[0, 0.5], [1, 2.4]],
		"amin": 0.0, "amax": 360.0, "additive": false,
		"ramp": [[0.0, Color(0.7, 0.68, 0.65, 0.0)], [0.1, Color(0.7, 0.68, 0.65, 0.16)], [1.0, Color(0.6, 0.6, 0.6, 0.0)]]})

## A bullet's glowing streak, flying from the muzzle to where it hit.
func tracer(from: Vector3, to: Vector3, thick := 1.0) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.6:
		return
	var dir := d / dist
	var length := minf(2.4, dist * 0.5)
	var speed := 240.0
	var life := maxf((dist - length) / speed, 0.025)
	var mat := _axial_mat(true, 0.016 * thick, Color(1.0, 0.78, 0.45), 3.2, null, 0, 1, 1.1)
	_burst(from + dir * length * 0.5, _quad(1.0, length), mat, {"amount": 1, "life": life, "dir": dir,
		"spread": 0.0, "vmin": speed, "vmax": speed, "gravity": Vector3.ZERO, "align": true})

## A bullet striking a wall or the floor: a spray of sparks, a puff of dust
## and grit, and a bullet hole.
func impact(pos: Vector3, normal: Vector3, _col: Object) -> void:
	if normal == Vector3.ZERO:
		normal = Vector3.UP
	normal = normal.normalized()
	var sparks := _axial_mat(true, 0.016, Color(1.0, 0.75, 0.4), 4.0, null, 0, 1, 1.0)
	_burst(pos + normal * 0.02, _quad(1.0, 0.16), sparks, {"amount": 12, "life": 0.35, "life_rand": 0.6,
		"dir": normal, "spread": 55.0, "vmin": 3.5, "vmax": 9.0, "align": true,
		"ramp": [[0.0, Color(1, 0.9, 0.7, 1)], [0.6, Color(1, 0.5, 0.15, 0.9)], [1.0, Color(0.8, 0.2, 0.05, 0)]]})
	_burst(pos + normal * 0.05, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.15), {"amount": 4, "life": 1.1,
		"life_rand": 0.4, "dir": normal, "spread": 35.0, "vmin": 0.4, "vmax": 1.3, "damp": 2.0,
		"gravity": Vector3(0, -0.25, 0), "smin": 0.1, "smax": 0.16, "scurve": [[0, 0.6], [1, 2.6]],
		"amin": 0.0, "amax": 360.0, "additive": false,
		"ramp": [[0.0, Color(0.5, 0.47, 0.42, 0.0)], [0.08, Color(0.5, 0.47, 0.42, 0.35)], [1.0, Color(0.45, 0.43, 0.4, 0.0)]]})
	var grit := _axial_mat(false, 0.018, Color(0.18, 0.16, 0.14), 1.0, null, 0, 1, 0.4)
	_burst(pos + normal * 0.02, _quad(1.0, 0.025), grit, {"amount": 5, "life": 0.6, "life_rand": 0.3,
		"dir": normal, "spread": 50.0, "vmin": 1.5, "vmax": 3.5, "align": true, "additive": false})
	Decals.splat("bullet_hole", pos, normal)

# ---------------------------------------------------------------- blood

## A hit on flesh: a burst of blood out of the wound along the shot (and a
## smaller one back toward the shooter), a red mist, drops that fall, and
## stains on the wall behind and the floor below. amount: about 1 for a
## pistol round, more for big guns, less for each shotgun pellet.
func blood(pos: Vector3, normal: Vector3, dir := Vector3.ZERO, amount := 1.0) -> void:
	if dir == Vector3.ZERO:
		dir = -normal
	dir = dir.normalized()
	if normal == Vector3.ZERO:
		normal = -dir
	var a := clampf(amount, 0.3, 2.5)
	# Hitboxes sit inside the body, so the hit point is under the skin: start
	# the entry side's blood a little toward the shooter and the exit side's
	# beyond the far side, where the camera can see them.
	var front := pos - dir * 0.12
	var back := pos + dir * 0.22
	# More pellets into the same body in the same frame add drops and a
	# stain, not another cloud each.
	var frame := Engine.get_process_frames()
	var extra := frame == _blood_frame and pos.distance_to(_blood_pos) < 0.8
	_blood_frame = frame
	_blood_pos = pos
	if extra:
		var d2 := _axial_mat(false, 0.03, Color(0.5, 0.02, 0.02), 1.0, null, 0, 1, 0.6)
		_burst(back, _quad(1.0, 0.1), d2, {"amount": 5, "life": 0.7, "life_rand": 0.5,
			"dir": (dir + Vector3.UP * 0.3).normalized(), "spread": 40.0, "vmin": 1.8, "vmax": 4.5, "align": true,
			"additive": false, "smin": 0.6, "smax": 1.2})
		_blood_stains(pos, dir, a)
		return
	if amount < 0.6:
		a = 0.8   # the first pellet stands for the whole load
	var spray := _axial_mat(false, 0.8, Color(1.25, 1.0, 1.0), 1.0, SPRAY_TEX, 0, 4)
	var spray_o := {"amount": 1, "life": 0.42, "spread": 0.0, "vmin": 0.05, "vmax": 0.05, "gravity": Vector3.ZERO,
		"align": true, "additive": false, "scurve": [[0, 0.25], [0.35, 1.0], [1, 1.15]],
		"ramp": [[0.0, Color(1, 1, 1, 1)], [0.45, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0)]]}
	# Out of the far side in a fan around the shot, angled off it so it
	# still reads from behind the shooter (straight along the line of sight
	# a spray is seen end-on and looks like a dot).
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized().rotated(dir, randf_range(-0.6, 0.6))
	for k in [[1.0, 0.75], [-1.0, 0.5]]:
		spray_o["dir"] = (dir + side * 0.65 * k[0] + Vector3.UP * randf_range(0.0, 0.25)).normalized()
		spray_o["smin"] = k[1] * a
		spray_o["smax"] = k[1] * 1.25 * a
		_burst(back, _quad(1.0, 0.75, true), spray, spray_o)
	# Back out of the entry wound, smaller.
	spray_o["dir"] = (normal + side * 0.4 + Vector3(0, 0.15, 0)).normalized()
	spray_o["smin"] = 0.35 * a
	spray_o["smax"] = 0.45 * a
	_burst(front, _quad(1.0, 0.75, true), spray, spray_o)
	# A fine red mist hanging where the round went in.
	_burst(front, _quad(1, 1), _sprite_mat(SPRAY_TEX, false, 1.0), {"amount": 2, "life": 0.5, "life_rand": 0.3,
		"dir": (normal + Vector3.UP * 0.2).normalized(), "spread": 50.0, "vmin": 0.2, "vmax": 0.5, "damp": 3.0, "gravity": Vector3(0, -0.6, 0),
		"smin": 0.45 * a, "smax": 0.6 * a, "scurve": [[0, 0.45], [1, 1.5]], "amin": 0.0, "amax": 360.0, "additive": false,
		"ramp": [[0.0, Color(1, 1, 1, 0.8)], [0.5, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]]})
	var drop := _axial_mat(false, 0.03, Color(0.55, 0.02, 0.02), 1.0, null, 0, 1, 0.6)
	_burst(back, _quad(1.0, 0.1), drop, {"amount": int(18 * a), "life": 0.75, "life_rand": 0.5,
		"dir": (dir + Vector3.UP * 0.35).normalized(), "spread": 50.0, "vmin": 1.8, "vmax": 4.8, "align": true,
		"additive": false, "smin": 0.6, "smax": 1.3})
	_blood_stains(pos, dir, a)

func _blood_stains(pos: Vector3, dir: Vector3, a: float) -> void:
	if _now() - _last_blood_decal < BLOOD_DECAL_GAP:
		return
	_last_blood_decal = _now()
	var world := get_viewport().world_3d if get_viewport() else null
	if world == null:
		return
	var space := world.direct_space_state
	# The wall behind them, if it's close.
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * 2.6, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		Decals.splat("blood", hit.position, hit.normal, randf_range(0.55, 1.0) * clampf(a, 0.7, 1.5))
	# The floor a little way along the spray.
	var at := pos + Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.3, 1.1)
	q = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 3.0, 1)
	hit = space.intersect_ray(q)
	if not hit.is_empty():
		Decals.splat("blood", hit.position, hit.normal, randf_range(0.35, 0.75) * clampf(a, 0.7, 1.5))

# ---------------------------------------------------------------- fire

## A fire that keeps burning: flame tongues, embers, smoke and a flickering
## light. extents: the burning area (half sizes); strength scales everything.
func make_fire(extents := Vector3(0.3, 0.05, 0.3), strength := 1.0, smoke := true, light := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var k := sqrt(maxf(strength, 0.1))
	var flames := GPUParticles3D.new()
	flames.amount = maxi(int(26 * strength), 6)
	flames.lifetime = 0.85
	flames.randomness = 0.3
	flames.draw_pass_1 = _quad(1, 1)
	# Alpha-blended flame photos: layered, they stay orange and yellow
	# instead of adding up to a white blob.
	flames.material_override = _sprite_mat(FIRE_TEX, false, 1.25, 0.3)
	flames.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.visibility_aabb = AABB(-extents - Vector3(1, 0.5, 1) * k, extents * 2.0 + Vector3(2, 3.5, 2) * k)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 0.5 * k
	pm.initial_velocity_max = 1.2 * k
	pm.gravity = Vector3(0, 1.4, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.5 * k
	pm.scale_max = 0.95 * k
	pm.scale_curve = _curve_tex([[0, 0.45], [0.25, 1.0], [1, 0.35]])
	pm.angle_min = -14.0
	pm.angle_max = 14.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = _ramp_tex([[0.0, Color(1, 0.9, 0.75, 0.0)], [0.1, Color(1, 0.88, 0.65, 1.0)],
		[0.45, Color(1, 0.58, 0.22, 0.95)], [0.75, Color(0.75, 0.2, 0.06, 0.55)], [1.0, Color(0.25, 0.05, 0.02, 0.0)]])
	flames.process_material = pm
	root.add_child(flames)

	var embers := GPUParticles3D.new()
	embers.amount = maxi(int(10 * strength), 3)
	embers.lifetime = 1.8
	embers.randomness = 0.5
	embers.draw_pass_1 = _quad(1.0, 0.05)
	embers.material_override = _axial_mat(true, 0.012, Color(1.0, 0.55, 0.18), 3.0, null, 0, 1, 0.8)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 7, 6))
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	em.emission_box_extents = extents
	em.direction = Vector3.UP
	em.spread = 25.0
	em.initial_velocity_min = 1.2 * k
	em.initial_velocity_max = 2.8 * k
	em.gravity = Vector3(0.2, 0.5, 0)
	em.particle_flag_align_y = true
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 2.0
	em.turbulence_noise_scale = 2.0
	em.turbulence_influence_min = 0.05
	em.turbulence_influence_max = 0.15
	em.color_ramp = _ramp_tex([[0.0, Color(1, 0.8, 0.4, 1)], [0.7, Color(1, 0.4, 0.1, 0.8)], [1.0, Color(0.6, 0.1, 0.02, 0)]])
	embers.process_material = em
	root.add_child(embers)

	if smoke:
		var sm := GPUParticles3D.new()
		sm.amount = maxi(int(12 * strength), 4)
		sm.lifetime = 3.6
		sm.randomness = 0.3
		sm.position = Vector3(0, extents.y + 0.7 * k, 0)
		sm.draw_pass_1 = _quad(1, 1)
		sm.material_override = _sprite_mat(SMOKE_TEX, false, 1.0, 0.4)
		sm.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sm.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 12, 10))
		var spm := ParticleProcessMaterial.new()
		spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		spm.emission_box_extents = extents * 0.7
		spm.direction = Vector3.UP
		spm.spread = 12.0
		spm.initial_velocity_min = 0.6 * k
		spm.initial_velocity_max = 1.1 * k
		spm.gravity = Vector3(0.15, 0.25, 0.05)
		spm.scale_min = 0.6 * k
		spm.scale_max = 1.0 * k
		spm.scale_curve = _curve_tex([[0, 0.4], [1, 2.4]])
		spm.angle_min = 0.0
		spm.angle_max = 360.0
		spm.anim_offset_max = 1.0
		spm.color_ramp = _ramp_tex([[0.0, Color(0.07, 0.06, 0.055, 0.0)], [0.15, Color(0.09, 0.08, 0.07, 0.6)],
			[1.0, Color(0.12, 0.12, 0.12, 0.0)]])
		sm.process_material = spm
		root.add_child(sm)

	if light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.18)
		l.light_energy = 2.4 * k
		l.omni_range = 4.5 * k + 1.5
		l.position = Vector3(0, extents.y + 0.45 * k, 0)
		l.shadow_enabled = false
		root.add_child(l)
		_flickers.append([l, l.light_energy])
	return root

## A low cloud of sickly yellow-green gas (a bloater bursting): slow,
## rolling smoke puffs that hug the floor and fill radius metres, thinning
## at the edges. Call stop() via set_emitting(false) on the returned
## particles to let it drift away.
func gas_cloud(radius: float) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = clampi(int(radius * 9.0), 14, 34)
	g.lifetime = 3.2
	g.randomness = 0.35
	g.preprocess = 1.2   # already billowing when it appears
	g.draw_pass_1 = _quad(1, 1)
	g.material_override = _sprite_mat(SMOKE_TEX, false, 1.0, 0.6)
	g.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-radius - 3, -1, -radius - 3), Vector3(radius * 2 + 6, 6, radius * 2 + 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius * 0.7, 0.35, radius * 0.7)
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.06, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	pm.scale_min = 1.3
	pm.scale_max = 2.3
	pm.scale_curve = _curve_tex([[0, 0.55], [1, 1.35]])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = _ramp_tex([[0.0, Color(0.42, 0.5, 0.12, 0.0)], [0.2, Color(0.46, 0.56, 0.14, 0.42)],
		[0.65, Color(0.38, 0.46, 0.12, 0.3)], [1.0, Color(0.3, 0.36, 0.1, 0.0)]])
	g.process_material = pm
	g.position = Vector3(0, 0.45, 0)
	# A thick, sickly yellow core rolling over itself where the body burst...
	var core := GPUParticles3D.new()
	core.amount = clampi(int(radius * 4.0), 8, 16)
	core.lifetime = 2.6
	core.randomness = 0.4
	core.preprocess = 1.0
	core.draw_pass_1 = g.draw_pass_1
	core.material_override = g.material_override
	core.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.visibility_aabb = g.visibility_aabb
	var cm: ParticleProcessMaterial = pm.duplicate()
	cm.emission_box_extents = Vector3(radius * 0.35, 0.25, radius * 0.35)
	cm.initial_velocity_min = 0.1
	cm.initial_velocity_max = 0.35
	cm.scale_min = 0.9
	cm.scale_max = 1.6
	cm.scale_curve = _curve_tex([[0, 0.4], [1, 1.3]])
	cm.color_ramp = _ramp_tex([[0.0, Color(0.6, 0.66, 0.16, 0.0)], [0.15, Color(0.62, 0.7, 0.18, 0.6)],
		[0.6, Color(0.5, 0.58, 0.15, 0.42)], [1.0, Color(0.36, 0.42, 0.12, 0.0)]])
	core.process_material = cm
	g.add_child(core)
	# ...and wisps curling up out of it.
	var wisps := GPUParticles3D.new()
	wisps.amount = clampi(int(radius * 2.0), 4, 8)
	wisps.lifetime = 3.0
	wisps.randomness = 0.5
	wisps.preprocess = 1.0
	wisps.draw_pass_1 = g.draw_pass_1
	wisps.material_override = g.material_override
	wisps.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wisps.visibility_aabb = g.visibility_aabb
	var wm: ParticleProcessMaterial = pm.duplicate()
	wm.emission_box_extents = Vector3(radius * 0.5, 0.2, radius * 0.5)
	wm.spread = 25.0
	wm.initial_velocity_min = 0.35
	wm.initial_velocity_max = 0.7
	wm.gravity = Vector3(0, 0.1, 0)
	wm.scale_min = 0.6
	wm.scale_max = 1.1
	wm.scale_curve = _curve_tex([[0, 0.5], [1, 1.6]])
	wm.color_ramp = _ramp_tex([[0.0, Color(0.5, 0.6, 0.15, 0.0)], [0.25, Color(0.52, 0.6, 0.16, 0.3)],
		[1.0, Color(0.4, 0.46, 0.12, 0.0)]])
	wisps.process_material = wm
	g.add_child(wisps)
	return g

func _curve_tex(points: Array) -> CurveTexture:
	var t := CurveTexture.new()
	t.curve = _curve(points)
	return t

func _ramp_tex(points: Array) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = _ramp(points)
	return t

## Stops a fire's emitters and frees it once the last flames have died.
func put_out(fire: Node) -> void:
	if not is_instance_valid(fire):
		return
	var longest := 0.0
	for p in fire.find_children("*", "GPUParticles3D", true, false):
		p.emitting = false
		longest = maxf(longest, p.lifetime)
	for l in fire.find_children("*", "OmniLight3D", true, false):
		l.set_meta("out", true)
		var t := l.create_tween()
		t.tween_property(l, "light_energy", 0.0, 0.6)
	# A tween on the fire itself, so a scene change that frees it first
	# leaves nothing behind waiting on it.
	var t := fire.create_tween()
	t.tween_interval(longest + 0.2)
	t.tween_callback(fire.queue_free)

## Sets someone on fire for a while (the flamethrower's victims).
func ignite(target: Node3D, secs := 3.0) -> void:
	if not is_instance_valid(target):
		return
	var until := _now() + int(secs * 1000.0)
	for b in _burns:
		if is_instance_valid(b[0]) and b[0].get_parent() == target:
			b[1] = until
			return
	var f := make_fire(Vector3(0.16, 0.45, 0.12), 0.6, true, false)
	f.name = "Burning"
	f.position = Vector3(0, 0.95, 0)
	target.add_child(f)
	_burns.append([f, until])

## One tick of the flamethrower: keeps this shooter's stream of fire going
## (it dies down on its own a moment after the trigger is let go).
func flame_stream(shooter: Node, from: Vector3, dir: Vector3, length: float) -> void:
	var scene := _scene()
	if scene == null:
		return
	var id := shooter.get_instance_id()
	var s: Dictionary = _streams.get(id, {})
	if s.is_empty() or not is_instance_valid(s["node"]):
		s = {"node": _make_stream(length), "last": 0}
		scene.add_child(s["node"])
		_streams[id] = s
	var node: Node3D = s["node"]
	node.global_position = from
	if absf(dir.normalized().dot(Vector3.UP)) < 0.99:
		node.look_at(from + dir, Vector3.UP)
	for p in node.find_children("*", "GPUParticles3D", false, false):
		p.emitting = true
	s["last"] = _now()
	# Where the stream meets the floor or a wall, the fuel keeps burning.
	if _now() - _last_patch > 260:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * length, 1)
		var hit := node.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_last_patch = _now()
			_burn_patch(hit.position, hit.normal)

func _make_stream(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FlameStream"
	var life := 0.55
	var speed := length / life * 1.35
	for layer in [["body", FIREBALL_TEX, 26, 0.9, false, 1.15], ["tongues", FIRE_TEX, 12, 0.75, true, 0.55]]:
		var p := GPUParticles3D.new()
		p.amount = layer[2]
		p.lifetime = life
		p.randomness = 0.25
		p.draw_pass_1 = _quad(1, 1)
		p.material_override = _sprite_mat(layer[1], layer[4], layer[5], 0.25)
		if not layer[4]:
			p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-length, -length, -length), Vector3(length, length, length) * 2.0)
		p.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, -1)
		pm.spread = 5.0
		pm.initial_velocity_min = speed * 0.85
		pm.initial_velocity_max = speed
		pm.damping_min = speed * 1.1
		pm.damping_max = speed * 1.4
		pm.gravity = Vector3(0, 2.2, 0)
		pm.scale_min = 0.8 * layer[3]
		pm.scale_max = 1.25 * layer[3]
		pm.scale_curve = _curve_tex([[0, 0.2], [0.25, 0.55], [1, 1.25]])
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -90.0
		pm.angular_velocity_max = 90.0
		pm.anim_offset_max = 1.0
		if layer[4]:
			pm.color_ramp = _ramp_tex([[0.0, Color(0.45, 0.55, 1.0, 0.3)], [0.1, Color(1, 0.72, 0.3, 0.6)],
				[0.38, Color(1, 0.48, 0.1, 0.55)], [0.72, Color(0.75, 0.2, 0.03, 0.35)], [1.0, Color(0.2, 0.05, 0.02, 0)]])
		else:
			pm.color_ramp = _ramp_tex([[0.0, Color(0.7, 0.8, 1.0, 0.0)], [0.1, Color(1, 0.9, 0.7, 0.9)],
				[0.4, Color(1, 0.7, 0.42, 0.85)], [0.75, Color(0.7, 0.32, 0.14, 0.55)], [1.0, Color(0.2, 0.12, 0.08, 0)]])
		p.process_material = pm
		root.add_child(p)
	var smoke := GPUParticles3D.new()
	smoke.amount = 22
	smoke.lifetime = 1.7
	smoke.randomness = 0.3
	smoke.draw_pass_1 = _quad(1, 1)
	smoke.material_override = _sprite_mat(SMOKE_TEX, false, 1.0, 0.3)
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	smoke.emitting = false
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 0, -1)
	sm.spread = 8.0
	sm.initial_velocity_min = speed * 0.6
	sm.initial_velocity_max = speed * 0.8
	sm.damping_min = speed * 0.9
	sm.damping_max = speed
	sm.gravity = Vector3(0, 1.0, 0)
	sm.scale_min = 0.6
	sm.scale_max = 1.0
	sm.scale_curve = _curve_tex([[0, 0.3], [1, 2.4]])
	sm.angle_max = 360.0
	sm.anim_offset_max = 1.0
	sm.color_ramp = _ramp_tex([[0.0, Color(0.08, 0.07, 0.06, 0.0)], [0.3, Color(0.08, 0.07, 0.06, 0.45)], [1.0, Color(0.1, 0.1, 0.1, 0.0)]])
	smoke.process_material = sm
	root.add_child(smoke)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 4.0
	l.omni_range = 8.0
	l.position = Vector3(0, 0.2, -length * 0.35)
	l.shadow_enabled = false
	root.add_child(l)
	_flickers.append([l, 4.0])
	return root

func _burn_patch(pos: Vector3, normal: Vector3) -> void:
	var scene := _scene()
	if scene == null:
		return
	while _patches.size() >= MAX_PATCHES:
		var old = _patches.pop_front()
		put_out(old[0])
	var f := make_fire(Vector3(0.25, 0.03, 0.25), 0.55, true, true)
	scene.add_child(f)
	f.global_position = pos + normal * 0.05
	_patches.append([f, _now() + 2600])

## Backwards-compatible single flamethrower tick (no shooter to key on).
func flame(from: Vector3, dir: Vector3, length: float) -> void:
	flame_stream(self, from, dir, length)

func _process(_d: float) -> void:
	var now := _now()
	# Fire light flickers.
	for i in range(_flickers.size() - 1, -1, -1):
		var f: Array = _flickers[i]
		if not is_instance_valid(f[0]):
			_flickers.remove_at(i)
			continue
		var l: OmniLight3D = f[0]
		if l.is_visible_in_tree() and not l.has_meta("out"):
			l.light_energy = lerpf(l.light_energy, f[1] * randf_range(0.6, 1.25), 0.35)
	for id in _streams.keys():
		var s: Dictionary = _streams[id]
		if not is_instance_valid(s["node"]):
			_streams.erase(id)
			continue
		var node: Node3D = s["node"]
		var on: bool = now - int(s["last"]) < 120
		for p in node.find_children("*", "GPUParticles3D", false, false):
			p.emitting = on
		node.visible = on or now - int(s["last"]) < 2000
		for l in node.find_children("*", "OmniLight3D", false, false):
			l.visible = on
		if now - int(s["last"]) > 4000:
			node.queue_free()
			_streams.erase(id)
	for list in [_burns, _patches]:
		for i in range(list.size() - 1, -1, -1):
			var b: Array = list[i]
			if not is_instance_valid(b[0]):
				list.remove_at(i)
			elif now > int(b[1]):
				put_out(b[0])
				list.remove_at(i)

# ---------------------------------------------------------------- explosions

## A grenade, rocket or barrel going off: a rolling fireball, flame licks,
## sparks and debris, a column of smoke, a blinding flash and a scorch mark.
func explosion(pos: Vector3, radius: float) -> void:
	if radius < 1.0:
		flash_burst(pos)
		return
	var r := radius
	_burst(pos + Vector3.UP * 0.3, _quad(1, 1), _sprite_mat(FIREBALL_TEX, false, 1.25, 0.3), {"amount": 12, "life": 0.9,
		"life_rand": 0.3, "dir": Vector3.UP, "spread": 180.0, "vmin": 0.6 * r, "vmax": 1.3 * r, "damp": 2.5 * r,
		"gravity": Vector3(0, 1.5, 0), "smin": 0.36 * r, "smax": 0.52 * r, "scurve": [[0, 0.3], [0.3, 1.0], [1, 1.15]],
		"amin": 0.0, "amax": 360.0, "sphere": 0.2 * r, "additive": false,
		"ramp": [[0.0, Color(1, 0.95, 0.85, 1)], [0.3, Color(1, 0.72, 0.42, 0.95)], [0.7, Color(0.5, 0.22, 0.1, 0.7)], [1.0, Color(0.14, 0.1, 0.08, 0)]]})
	_burst(pos + Vector3.UP * 0.2, _quad(1, 1), _sprite_mat(FIRE_TEX, true, 1.0, 0.3), {"amount": 10, "life": 0.55,
		"life_rand": 0.4, "dir": Vector3.UP, "spread": 70.0, "vmin": 1.0 * r, "vmax": 2.0 * r, "damp": 3.0 * r,
		"gravity": Vector3(0, 2.0, 0), "smin": 0.25 * r, "smax": 0.4 * r, "amin": -20.0, "amax": 20.0,
		"ramp": [[0.0, Color(1, 0.9, 0.7, 1)], [0.6, Color(1, 0.45, 0.12, 0.8)], [1.0, Color(0.5, 0.1, 0.02, 0)]]})
	_burst(pos + Vector3.UP * 0.5, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.5), {"amount": 24, "life": 4.5,
		"life_rand": 0.35, "explosiveness": 0.8, "dir": Vector3.UP, "spread": 45.0, "vmin": 0.5, "vmax": 0.3 * r + 1.0,
		"damp": 0.8, "gravity": Vector3(0.2, 0.45, 0), "smin": 0.32 * r, "smax": 0.5 * r, "scurve": [[0, 0.4], [1, 1.7]],
		"amin": 0.0, "amax": 360.0, "sphere": 0.3 * r, "additive": false,
		"ramp": [[0.0, Color(0.05, 0.045, 0.04, 0.0)], [0.12, Color(0.07, 0.06, 0.055, 0.6)], [0.6, Color(0.1, 0.1, 0.1, 0.35)], [1.0, Color(0.14, 0.14, 0.14, 0.0)]]})
	var sparks := _axial_mat(true, 0.02, Color(1.0, 0.7, 0.35), 3.0, null, 0, 1, 0.9)
	_burst(pos + Vector3.UP * 0.2, _quad(1.0, 0.28), sparks, {"amount": 40, "life": 1.1, "life_rand": 0.6,
		"dir": Vector3.UP, "spread": 85.0, "vmin": 5.0, "vmax": 16.0, "damp": 1.0, "align": true,
		"ramp": [[0.0, Color(1, 0.9, 0.6, 1)], [0.7, Color(1, 0.45, 0.1, 0.9)], [1.0, Color(0.6, 0.1, 0.0, 0)]]})
	var debris := _axial_mat(false, 0.05, Color(0.1, 0.09, 0.08), 1.0, null, 0, 1, 0.2)
	_burst(pos + Vector3.UP * 0.2, _quad(1.0, 0.06), debris, {"amount": 16, "life": 1.4, "life_rand": 0.4,
		"dir": Vector3.UP, "spread": 70.0, "vmin": 4.0, "vmax": 10.0, "align": true, "additive": false, "smin": 0.6, "smax": 1.6})
	_light(pos + Vector3.UP * 1.0, Color(1.0, 0.62, 0.3), 16.0, r * 3.0, 0.7, true)
	var world := get_viewport().world_3d if get_viewport() else null
	if world:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.5, 1)
		var hit := world.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			Decals.splat("scorch", hit.position, hit.normal, r * 0.7)

## A flash grenade: a white burst and a light bright enough to blind.
func flash_burst(pos: Vector3) -> void:
	_burst(pos, _quad(1, 1), _sprite_mat(MUZZLE_TEX, true, 3.0), {"amount": 2, "life": 0.18, "spread": 0.0,
		"vmin": 0.0, "vmax": 0.0, "gravity": Vector3.ZERO, "smin": 2.5, "smax": 3.2, "amin": 0.0, "amax": 360.0,
		"frame_min": 0.5, "frame_max": 0.99, "color": Color(0.85, 0.9, 1.0),
		"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]]})
	_burst(pos, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.4), {"amount": 6, "life": 2.5, "dir": Vector3.UP,
		"spread": 90.0, "vmin": 0.3, "vmax": 1.0, "damp": 0.8, "gravity": Vector3(0, 0.3, 0), "smin": 0.6, "smax": 1.0,
		"scurve": [[0, 0.5], [1, 1.8]], "amin": 0.0, "amax": 360.0, "additive": false,
		"ramp": [[0.0, Color(0.8, 0.8, 0.8, 0.0)], [0.1, Color(0.75, 0.75, 0.75, 0.5)], [1.0, Color(0.6, 0.6, 0.6, 0.0)]]})
	_light(pos + Vector3.UP * 0.5, Color(0.9, 0.95, 1.0), 30.0, 14.0, 0.5, true)

## Lets a projectile's trail (smoke behind a rocket) finish on its own after
## the projectile is gone.
func detach_trail(trail: Node3D) -> void:
	var scene := _scene()
	if scene == null or not is_instance_valid(trail):
		return
	var at := trail.global_transform
	trail.get_parent().remove_child(trail)
	scene.add_child(trail)
	trail.global_transform = at
	put_out(trail)

# ---------------------------------------------------------------- breakables

## Extra fire for a drum or can of fuel going up, on top of explosion(): a
## tall rolling column of burning fuel, flaming splashes thrown out in arcs
## that fall back down, and a long orange glow while it burns off.
func fuel_blast(pos: Vector3, radius: float) -> void:
	var r := radius
	_burst(pos + Vector3.UP * 0.4, _quad(1, 1), _sprite_mat(FIREBALL_TEX, false, 1.3, 0.3), {"amount": 10, "life": 1.5,
		"life_rand": 0.3, "explosiveness": 0.75, "dir": Vector3.UP, "spread": 14.0, "vmin": 3.0, "vmax": 6.5,
		"damp": 2.6, "gravity": Vector3(0, 1.2, 0), "smin": 0.3 * r, "smax": 0.44 * r,
		"scurve": [[0, 0.3], [0.35, 1.0], [1, 1.3]], "amin": 0.0, "amax": 360.0, "sphere": 0.2, "additive": false,
		"ramp": [[0.0, Color(1, 0.93, 0.8, 1)], [0.3, Color(1, 0.66, 0.32, 0.95)], [0.65, Color(0.5, 0.2, 0.08, 0.7)], [1.0, Color(0.1, 0.08, 0.07, 0)]]})
	_burst(pos + Vector3.UP * 0.5, _quad(1, 1), _sprite_mat(FIRE_TEX, false, 1.25, 0.0), {"amount": 18, "life": 1.1,
		"life_rand": 0.35, "dir": Vector3.UP, "spread": 70.0, "vmin": 3.5, "vmax": 8.0, "damp": 0.3,
		"gravity": Vector3(0, -9.8, 0), "smin": 0.25, "smax": 0.5, "amin": -25.0, "amax": 25.0, "additive": false,
		"ramp": [[0.0, Color(1, 0.9, 0.7, 1)], [0.55, Color(1, 0.52, 0.16, 0.9)], [1.0, Color(0.35, 0.08, 0.02, 0)]]})
	# Black smoke from burning fuel rolls up long after the flash.
	_burst(pos + Vector3.UP * 1.2, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.5), {"amount": 14, "life": 6.0,
		"life_rand": 0.3, "explosiveness": 0.5, "dir": Vector3.UP, "spread": 20.0, "vmin": 0.8, "vmax": 1.8,
		"damp": 0.4, "gravity": Vector3(0.15, 0.35, 0.05), "smin": 0.25 * r, "smax": 0.4 * r, "scurve": [[0, 0.4], [1, 1.9]],
		"amin": 0.0, "amax": 360.0, "sphere": 0.3, "additive": false,
		"ramp": [[0.0, Color(0.03, 0.03, 0.03, 0.0)], [0.15, Color(0.04, 0.035, 0.03, 0.7)], [1.0, Color(0.08, 0.08, 0.08, 0.0)]]})
	_light(pos + Vector3.UP * 1.6, Color(1.0, 0.55, 0.22), 9.0, r * 3.2, 2.2, true)

## A gas cylinder bursting: a sharp white-hot flash and a short, fast ball of
## flame, more bang than burn.
func gas_burst(pos: Vector3, radius: float) -> void:
	_burst(pos, _quad(1, 1), _sprite_mat(MUZZLE_TEX, true, 2.5), {"amount": 2, "life": 0.12, "spread": 0.0,
		"vmin": 0.0, "vmax": 0.0, "gravity": Vector3.ZERO, "smin": radius * 0.45, "smax": radius * 0.6,
		"amin": 0.0, "amax": 360.0, "frame_min": 0.5, "frame_max": 0.99, "color": Color(1.0, 0.85, 0.6),
		"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 0.8, 0.5, 0)]]})
	_light(pos + Vector3.UP * 0.5, Color(1.0, 0.85, 0.6), 22.0, radius * 3.0, 0.25, true)

## Burning fuel jetting out of a bullet hole, pointing along the node's +Y
## (turn the returned node to face out of the hole). Until put_out().
func fire_jet() -> Node3D:
	var root := Node3D.new()
	root.name = "FireJet"
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.45
	p.randomness = 0.3
	p.local_coords = false
	p.draw_pass_1 = _quad(1, 1)
	p.material_override = _sprite_mat(FIRE_TEX, false, 1.3, 0.0)
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 5, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 9.0
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0, 2.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 0.12
	pm.scale_max = 0.2
	pm.scale_curve = _curve_tex([[0, 0.3], [0.35, 1.0], [1, 1.6]])
	pm.angle_min = -20.0
	pm.angle_max = 20.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = _ramp_tex([[0.0, Color(1, 0.95, 0.8, 1)], [0.3, Color(1, 0.7, 0.3, 1)],
		[0.75, Color(0.9, 0.3, 0.08, 0.7)], [1.0, Color(0.2, 0.05, 0.02, 0.0)]])
	p.process_material = pm
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.6
	l.omni_range = 3.5
	l.position = Vector3(0, 0.3, 0)
	l.shadow_enabled = false
	root.add_child(l)
	_flickers.append([l, l.light_energy])
	return root

var _shard_tex: Texture2D

## Four jagged slivers of glass in a 2x2 atlas, drawn once: a pale body, a
## bright edge where it catches the light.
func _shards() -> Texture2D:
	if _shard_tex:
		return _shard_tex
	var n := 64
	var img := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for cell in 4:
		var ox := (cell % 2) * n
		var oy := (cell / 2) * n
		var pts := PackedVector2Array()
		var k := 3 + cell % 2
		for i in k:
			var a := TAU * i / k + rng.randf_range(-0.4, 0.4)
			var rr := rng.randf_range(0.25, 0.47) * n * (1.6 if i == 0 else 1.0)
			pts.append(Vector2(n / 2.0, n / 2.0) + Vector2(cos(a), sin(a)) * minf(rr, n * 0.48))
		for y in n:
			for x in n:
				var p := Vector2(x + 0.5, y + 0.5)
				if not Geometry2D.is_point_in_polygon(p, pts):
					continue
				var edge := INF
				for i in pts.size():
					var a2 := pts[i]
					var b2 := pts[(i + 1) % pts.size()]
					edge = minf(edge, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a2, b2)))
				var rim := clampf(1.0 - edge / 2.5, 0.0, 1.0)
				var c := Color(0.75 + 0.25 * rim, 0.85 + 0.15 * rim, 0.95, 0.35 + 0.65 * rim)
				img.set_pixel(ox + x, oy + y, c)
	_shard_tex = ImageTexture.create_from_image(img)
	return _shard_tex

## A pane bursting: glinting shards that spin as they fall, and a little
## glass dust. size: about the pane's width in metres.
func glass_shatter(pos: Vector3, normal: Vector3, size := 1.0) -> void:
	if normal == Vector3.ZERO:
		normal = Vector3.UP
	var mat := _sprite_mat(_shards(), true, 1.4)
	_burst(pos, _quad(1, 1), mat, {"amount": int(18 + 26 * size), "life": 1.4, "life_rand": 0.4,
		"dir": normal.normalized(), "spread": 70.0, "vmin": 0.8, "vmax": 4.0, "gravity": Vector3(0, -9.8, 0),
		"smin": 0.035, "smax": 0.12, "amin": 0.0, "amax": 360.0, "sphere": 0.35 * size,
		"ramp": [[0.0, Color(1, 1, 1, 1)], [0.2, Color(0.6, 0.7, 0.8, 0.7)], [0.35, Color(1, 1, 1, 1)],
			[0.55, Color(0.5, 0.6, 0.7, 0.6)], [0.75, Color(1, 1, 1, 0.9)], [1.0, Color(0.6, 0.7, 0.8, 0.0)]]})
	_burst(pos, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.2), {"amount": 4, "life": 1.0, "dir": normal,
		"spread": 50.0, "vmin": 0.3, "vmax": 0.9, "damp": 1.5, "gravity": Vector3(0, -0.3, 0), "smin": 0.15 * size + 0.1,
		"smax": 0.25 * size + 0.12, "scurve": [[0, 0.5], [1, 2.0]], "amin": 0.0, "amax": 360.0, "additive": false,
		"ramp": [[0.0, Color(0.8, 0.85, 0.9, 0.0)], [0.1, Color(0.8, 0.85, 0.9, 0.22)], [1.0, Color(0.8, 0.85, 0.9, 0.0)]]})

## A light bulb shot out: a pop of light, a shower of sparks raining down and
## a few glints of glass.
func lamp_burst(pos: Vector3) -> void:
	var sparks := _axial_mat(true, 0.012, Color(1.0, 0.8, 0.45), 3.5, null, 0, 1, 0.9)
	_burst(pos, _quad(1.0, 0.14), sparks, {"amount": 28, "life": 1.0, "life_rand": 0.5, "dir": Vector3.DOWN,
		"spread": 75.0, "vmin": 1.0, "vmax": 4.5, "gravity": Vector3(0, -9.8, 0), "align": true,
		"ramp": [[0.0, Color(1, 0.95, 0.8, 1)], [0.5, Color(1, 0.6, 0.2, 0.9)], [1.0, Color(0.7, 0.2, 0.05, 0)]]})
	glass_shatter(pos, Vector3.DOWN, 0.3)
	_light(pos, Color(1.0, 0.9, 0.7), 7.0, 6.0, 0.1, true)

## Wood smashed apart: chips and splinters flying, a puff of old dust.
func splinters(pos: Vector3, size := 1.0) -> void:
	var chips := _axial_mat(false, 0.03, Color(0.32, 0.22, 0.13), 1.0, null, 0, 1, 0.15)
	_burst(pos, _quad(1.0, 0.09), chips, {"amount": int(20 * size) + 6, "life": 1.2, "life_rand": 0.4, "dir": Vector3.UP,
		"spread": 80.0, "vmin": 2.0, "vmax": 6.0, "gravity": Vector3(0, -9.8, 0), "align": true, "additive": false,
		"smin": 0.6, "smax": 1.5})
	_burst(pos, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.3), {"amount": 6, "life": 1.8, "dir": Vector3.UP,
		"spread": 80.0, "vmin": 0.4, "vmax": 1.4, "damp": 1.6, "gravity": Vector3(0, -0.15, 0), "smin": 0.3 * size,
		"smax": 0.5 * size, "scurve": [[0, 0.5], [1, 2.0]], "amin": 0.0, "amax": 360.0, "additive": false, "sphere": 0.25 * size,
		"ramp": [[0.0, Color(0.42, 0.37, 0.3, 0.0)], [0.1, Color(0.42, 0.37, 0.3, 0.4)], [1.0, Color(0.4, 0.36, 0.3, 0.0)]]})

## A spitter's acid glob bursting: sizzling droplets and a puff of fumes.
func acid_splash(pos: Vector3, normal: Vector3) -> void:
	if normal == Vector3.ZERO:
		normal = Vector3.UP
	var drops := _axial_mat(false, 0.025, Color(0.55, 0.8, 0.12), 1.4, null, 0, 1, 0.5)
	_burst(pos + normal * 0.05, _quad(1.0, 0.07), drops, {"amount": 16, "life": 0.6, "life_rand": 0.4, "dir": normal,
		"spread": 70.0, "vmin": 1.5, "vmax": 4.0, "gravity": Vector3(0, -9.8, 0), "align": true, "additive": false,
		"smin": 0.6, "smax": 1.3})
	_burst(pos + normal * 0.1, _quad(1, 1), _sprite_mat(SMOKE_TEX, false, 1.0, 0.3), {"amount": 6, "life": 1.6, "dir": normal,
		"spread": 60.0, "vmin": 0.3, "vmax": 0.9, "damp": 1.4, "gravity": Vector3(0, 0.25, 0), "smin": 0.35,
		"smax": 0.6, "scurve": [[0, 0.5], [1, 1.8]], "amin": 0.0, "amax": 360.0, "additive": false, "sphere": 0.15,
		"ramp": [[0.0, Color(0.55, 0.65, 0.16, 0.0)], [0.12, Color(0.55, 0.65, 0.16, 0.45)], [1.0, Color(0.45, 0.52, 0.14, 0.0)]]})

## A wet, glistening acid glob in flight, dripping as it goes.
func acid_glob() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.2
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.62, 0.08)
	m.roughness = 0.06
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.35, 0.55, 0.06)
	m.emission_energy_multiplier = 0.8
	m.rim_enabled = true
	m.rim = 0.6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var drip := CPUParticles3D.new()
	drip.amount = 14
	drip.lifetime = 0.5
	drip.local_coords = false
	drip.mesh = _quad(1, 1)
	drip.material_override = _sprite_mat(SMOKE_TEX, false, 1.0, 0.0)
	drip.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	drip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drip.spread = 180.0
	drip.initial_velocity_min = 0.05
	drip.initial_velocity_max = 0.2
	drip.gravity = Vector3(0, -2.0, 0)
	drip.scale_amount_min = 0.12
	drip.scale_amount_max = 0.22
	drip.angle_max = 360.0
	drip.color_ramp = _ramp([[0.0, Color(0.5, 0.7, 0.12, 0.6)], [1.0, Color(0.4, 0.5, 0.1, 0.0)]])
	root.add_child(drip)
	return root
