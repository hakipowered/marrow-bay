class_name ZombieModel
extends Node3D
## Enemy body. Human infected use a rigged, animated scanned model
## (res://assets/characters/enemies/<model>/<model>.glb plus <model>_anims.res),
## made infected by shaders/infected_body.gdshader. The clip follows the synced
## `state`, so both players see the same thing. Types with no model yet (hound,
## larva, brood mother) build a stand-in whose silhouette matches the type.

var variant := "shambler"
var look := "office"
var data: Dictionary = {}
var _parts := {}
var _anim: AnimationPlayer
var _t := 0.0
var _dead := false
var _base_y := 0.0
var _rigged := false
var _clip := ""
var _oneshot := 0.0          # seconds left of a one-off clip (hit, scream)
var _loop_offset := 0.0
var _speed_var := 1.0
var _wander_clip := "shamble"
var _mat: ShaderMaterial

## Which scanned model each look uses (several looks share one body).
const MODEL_FOR_LOOK := {
	"office": "office", "suit": "office", "nurse": "nurse", "cop": "cop",
	"jogger": "jogger", "student": "jogger", "courier": "jogger",
	"mechanic": "mechanic", "cook": "mechanic",
	"brute": "brute", "grappler": "brute", "bloated": "bloated",
	"screamer": "screamer", "burnt": "burnt", "riot": "riot",
	"spitter": "spitter", "ventling": "spitter",
}
## Infection look per type: shader parameters on top of the defaults.
const INFECTION := {
	"burnt": {"burn": 1.0, "ember": 1.0, "blood": 0.3, "pallor": 0.6},
	"bloated": {"flesh": Color(0.58, 0.66, 0.42), "veins": 1.0, "bile": 0.5},
	"spitter": {"bile": 1.0, "skin_legs": 1.0, "flesh": Color(0.62, 0.68, 0.5)},
	"ventling": {"bile": 0.4, "skin_legs": 1.0, "blood": 1.0},
	"screamer": {"flesh": Color(0.68, 0.68, 0.66), "veins": 1.0},
	"brute": {"blood": 1.0, "flesh": Color(0.55, 0.52, 0.5)},
	"grappler": {"blood": 1.0, "flesh": Color(0.62, 0.5, 0.48)},
	"jogger": {"skin_legs": 0.0},
}
## Native speed of each moving clip in m/s, so feet don't slide.
const CLIP_SPEED := {"shamble": 0.75, "walk": 1.3, "run": 3.6, "sprint": 5.0, "crawl": 0.5}
static var _mesh_cache := {}

const LOOK_COLORS := {
	# clothes, trousers, skin
	"office": [Color(0.55, 0.57, 0.6), Color(0.15, 0.15, 0.18), Color(0.47, 0.49, 0.4)],
	"nurse": [Color(0.4, 0.55, 0.6), Color(0.4, 0.55, 0.6), Color(0.5, 0.5, 0.42)],
	"cook": [Color(0.8, 0.78, 0.72), Color(0.2, 0.2, 0.2), Color(0.46, 0.46, 0.38)],
	"jogger": [Color(0.75, 0.25, 0.2), Color(0.1, 0.1, 0.12), Color(0.48, 0.45, 0.36)],
	"cop": [Color(0.12, 0.14, 0.22), Color(0.1, 0.1, 0.14), Color(0.42, 0.44, 0.36)],
	"mechanic": [Color(0.25, 0.3, 0.4), Color(0.25, 0.3, 0.4), Color(0.44, 0.42, 0.34)],
	"student": [Color(0.3, 0.45, 0.25), Color(0.2, 0.25, 0.4), Color(0.5, 0.48, 0.4)],
	"suit": [Color(0.1, 0.1, 0.11), Color(0.1, 0.1, 0.11), Color(0.45, 0.46, 0.38)],
	"courier": [Color(0.9, 0.6, 0.1), Color(0.15, 0.15, 0.15), Color(0.48, 0.46, 0.38)],
	"riot": [Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09), Color(0.4, 0.42, 0.35)],
	"bloated": [Color(0.5, 0.45, 0.35), Color(0.3, 0.25, 0.2), Color(0.55, 0.56, 0.36)],
	"brute": [Color(0.2, 0.1, 0.08), Color(0.12, 0.1, 0.1), Color(0.38, 0.32, 0.3)],
	"screamer": [Color(0.6, 0.55, 0.5), Color(0.3, 0.28, 0.25), Color(0.6, 0.58, 0.55)],
	"burnt": [Color(0.08, 0.06, 0.05), Color(0.08, 0.06, 0.05), Color(0.15, 0.08, 0.05)],
	"grappler": [Color(0.3, 0.2, 0.18), Color(0.15, 0.12, 0.1), Color(0.5, 0.35, 0.3)],
	"ventling": [Color(0.42, 0.3, 0.3), Color(0.42, 0.3, 0.3), Color(0.55, 0.38, 0.36)],
	"spitter": [Color(0.4, 0.45, 0.25), Color(0.3, 0.3, 0.2), Color(0.5, 0.58, 0.3)],
	"hound": [Color(0.25, 0.18, 0.15), Color(0.25, 0.18, 0.15), Color(0.45, 0.25, 0.22)],
	"larva": [Color(0.75, 0.7, 0.55), Color(0.75, 0.7, 0.55), Color(0.75, 0.7, 0.55)],
	"brood": [Color(0.45, 0.2, 0.25), Color(0.35, 0.15, 0.2), Color(0.6, 0.35, 0.35)],
}

func _ready() -> void:
	if not data.get("quadruped") and not data.get("tiny") and variant != "brood_mother" and _load_rigged():
		return
	var c: Array = LOOK_COLORS.get(look, LOOK_COLORS["office"])
	if data.get("quadruped"):
		_build_hound(c)
	elif data.get("crawl"):
		_build_crawler(c)
	else:
		_build_biped(c)
	if look == "burnt":
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.1)
		l.light_energy = 1.2
		l.omni_range = 3.0
		l.position.y = 1.2
		add_child(l)
		l.set_script(preload("res://scripts/world/flicker.gd"))
	if variant == "ventling" or variant == "possum":
		visible = variant != "ventling"
		if variant == "possum":
			rotation.x = -PI / 2
			position.y = 0.15

func _load_rigged() -> bool:
	var id: String = MODEL_FOR_LOOK.get(look, MODEL_FOR_LOOK.get(variant, "mechanic"))
	var own := true
	if not ResourceLoader.exists("res://assets/characters/enemies/%s/%s.glb" % [id, id]):
		id = "mechanic"
		own = false
	var path := "res://assets/characters/enemies/%s/%s.glb" % [id, id]
	var lib_path := "res://assets/characters/enemies/%s/%s_anims.res" % [id, id]
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(lib_path):
		return false
	var m: Node3D = load(path).instantiate()
	m.rotation.y = PI   # Meshy models face +Z; enemies look down -Z
	if not own:
		# Borrowed body: size it to the type.
		m.scale = Vector3.ONE * float(data.get("height", 1.0))
	add_child(m)
	var old_ap := m.find_child("AnimationPlayer", true, false)
	if old_ap:
		old_ap.queue_free()
	_anim = AnimationPlayer.new()
	m.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", load(lib_path))
	_rigged = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(get_parent().name) + look) if get_parent() else randi()
	_loop_offset = rng.randf()
	_speed_var = rng.randf_range(0.85, 1.12)
	_wander_clip = "walk" if rng.randf() < 0.3 else "shamble"
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		_infect(mi, id, rng.randf())
	if look == "burnt":
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.1)
		l.light_energy = 0.8
		l.omni_range = 2.5
		l.position.y = 1.2
		add_child(l)
		l.set_script(preload("res://scripts/world/flicker.gd"))
	if variant == "ventling":
		visible = false
	_play("idle", 0.0)
	return true

## Swap the scanned material for the infected shader, and bake the rest-pose
## position into vertex colours (once per model) so the shader can place
## wounds and blood on the body.
func _infect(mi: MeshInstance3D, id: String, rnd: float) -> void:
	var key := id + ":" + str(mi.name)
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _with_rest_colors(mi.mesh)
	var std := mi.get_active_material(0) as StandardMaterial3D
	mi.mesh = _mesh_cache[key]
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/infected_body.gdshader")
	if std:
		_mat.set_shader_parameter("albedo_tex", std.albedo_texture)
		_mat.set_shader_parameter("has_normal", std.normal_enabled and std.normal_texture != null)
		_mat.set_shader_parameter("normal_tex", std.normal_texture)
		_mat.set_shader_parameter("normal_scale", std.normal_scale)
		_mat.set_shader_parameter("orm_tex", std.roughness_texture if std.roughness_texture else std.metallic_texture)
		var chans := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
		_mat.set_shader_parameter("rough_ch", chans[std.roughness_texture_channel] if std.roughness_texture else Vector4.ZERO)
		_mat.set_shader_parameter("metal_ch", chans[std.metallic_texture_channel] if std.metallic_texture else Vector4.ZERO)
		_mat.set_shader_parameter("roughness", std.roughness)
		_mat.set_shader_parameter("metallic", std.metallic)
	_mat.set_shader_parameter("seed", rnd)
	_mat.set_shader_parameter("blood", lerpf(0.45, 1.0, fmod(rnd * 7.3, 1.0)))
	_mat.set_shader_parameter("bite", 1.0 if fmod(rnd * 3.1, 1.0) < 0.7 else 0.0)
	var fx: Dictionary = INFECTION.get(look, INFECTION.get(variant, {}))
	for k in fx:
		_mat.set_shader_parameter(k, fx[k])
	mi.material_override = _mat

static func _with_rest_colors(src: Mesh) -> Mesh:
	if not (src is ArrayMesh):
		return src
	var am := ArrayMesh.new()
	var aabb := src.get_aabb()
	var size := aabb.size
	for i in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for v in verts.size():
			var p := (verts[v] - aabb.position) / size
			cols[v] = Color(p.x, p.y, p.z)
		arrays[Mesh.ARRAY_COLOR] = cols
		var flags: int = src.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		am.surface_set_material(i, src.surface_get_material(i))
	return am

func _play(clip: String, blend := 0.25, speed := 1.0, from_offset := false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if clip == _clip:
		_anim.speed_scale = speed
		return
	_clip = clip
	_anim.play(clip, blend)
	_anim.speed_scale = speed
	if from_offset:
		_anim.seek(_loop_offset * _anim.current_animation_length, true)

## A one-off clip (hit, scream) that plays over the state clip, then hands back.
func play_once(clip: String, blend := 0.12) -> void:
	if not _rigged or _dead or _anim == null or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, blend)
	_anim.speed_scale = 1.0
	_oneshot = _anim.get_animation(clip).length * (0.55 if clip == "hit" else 0.9)

func _animate_rigged(state: int, speed: float, crippled: bool) -> void:
	var dt := get_process_delta_time()
	if _oneshot > 0.0:
		_oneshot -= dt
		return
	var runner: bool = data.get("runner", false) or variant in ["runner", "hound"]
	match state:
		Zombie.S.IDLE, Zombie.S.FEED:
			if crippled or data.get("crawl"):
				_play("crawl", 0.4, 0.15, true)
			else:
				_play("idle", 0.4, _speed_var * 0.8, true)
		Zombie.S.HIDDEN:
			_play("idle", 0.0)
		Zombie.S.PLAY_DEAD:
			if _clip != "death":
				_play("death", 0.0)
				_anim.seek(_anim.current_animation_length - 0.01, true)
				_anim.pause()
		Zombie.S.ATTACK:
			_play("attack", 0.15, 1.25)
		Zombie.S.PINNING:
			_play("grab", 0.2)
		Zombie.S.STAGGER:
			_play("hit", 0.1, 0.8)
		Zombie.S.DEAD:
			pass
		_:
			if crippled or data.get("crawl"):
				_play("crawl", 0.3, clampf(speed / CLIP_SPEED["crawl"], 0.4, 2.0), true)
			elif speed < 0.12:
				_play("idle", 0.4, _speed_var * 0.8, true)
			else:
				var clip := _wander_clip
				if state == Zombie.S.CHARGE or (runner and speed > 2.2):
					clip = "sprint"
				elif speed > 2.0:
					clip = "run"
				_play(clip, 0.3, clampf(speed / CLIP_SPEED[clip], 0.5, 1.8) * _speed_var, true)

func _mesh(kind: String, size: Vector3, pos: Vector3, color: Color, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	match kind:
		"cap":
			mesh = CapsuleMesh.new()
			mesh.radius = size.x / 2
			mesh.height = max(size.y, size.x + 0.01)
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = size.x / 2
			mesh.height = size.y
		_:
			mesh = BoxMesh.new()
			mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = Mats.trim(color, rough)
	add_child(mi)
	return mi

func _build_biped(c: Array) -> void:
	var b: float = data.get("bulk", 1.0)
	var h: float = data.get("height", 1.0)
	var long_arms := 1.6 if variant == "ventling" else 1.0
	_parts["head"] = _mesh("cap", Vector3(0.2, 0.25, 0.22) * (1.15 if variant == "screamer" else 1.0), Vector3(0, 1.58 * h, 0.1), c[2])
	_parts["torso"] = _mesh("sphere" if variant in ["bloater", "brood_mother"] else "box", Vector3(0.42 * b, 0.6 * h, 0.26 * b) if variant not in ["bloater", "brood_mother"] else Vector3(0.7 * b, 0.8, 0.7 * b), Vector3(0, 1.2 * h, 0.04), c[0])
	_parts["arm_l"] = _mesh("cap", Vector3(0.1 * b, 0.6 * h * long_arms, 0.1), Vector3(-0.3 * b, 1.25 * h - (long_arms - 1) * 0.3, -0.15), c[2])
	_parts["arm_r"] = _mesh("cap", Vector3(0.1 * b, 0.6 * h * long_arms, 0.1), Vector3(0.3 * b, 1.25 * h - (long_arms - 1) * 0.3, -0.15), c[2])
	_parts["leg_l"] = _mesh("cap", Vector3(0.15 * b, 0.9 * h, 0.15), Vector3(-0.12 * b, 0.45 * h, 0), c[1])
	_parts["leg_r"] = _mesh("cap", Vector3(0.15 * b, 0.9 * h, 0.15), Vector3(0.12 * b, 0.45 * h, 0), c[1])
	_parts["arm_l"].rotation.x = -1.3
	_parts["arm_r"].rotation.x = -1.1
	_parts["torso"].rotation.x = 0.25 if variant != "brute" else 0.1
	if data.get("shield"):
		_parts["shield"] = _mesh("box", Vector3(0.6, 1.0, 0.04), Vector3(-0.1, 1.15, -0.45), Color(0.25, 0.28, 0.3), 0.2)
		_parts["shield"].material_override.metallic = 0.6
		_parts["helmet"] = _mesh("sphere", Vector3(0.27, 0.24, 0.27), Vector3(0, 1.66, 0.08), Color(0.1, 0.1, 0.11), 0.3)
	if variant == "spitter":
		_parts["sac"] = _mesh("sphere", Vector3(0.35, 0.3, 0.3), Vector3(0, 1.38, 0.05), Color(0.55, 0.8, 0.15), 0.2)
	if variant == "brood_mother":
		for i in 6:
			_mesh("sphere", Vector3(0.35, 0.35, 0.35), Vector3(cos(i) * 0.8, 0.4 + i * 0.12, sin(i) * 0.8), Color(0.7, 0.6, 0.4), 0.3)

func _build_crawler(c: Array) -> void:
	var s := 0.35 if data.get("tiny") else 1.0
	_parts["torso"] = _mesh("box", Vector3(0.44, 0.26, 0.7) * s, Vector3(0, 0.22, -0.2) * s, c[0])
	_parts["head"] = _mesh("cap", Vector3(0.2, 0.25, 0.22) * s, Vector3(0, 0.3, -0.68) * s, c[2])
	_parts["arm_l"] = _mesh("cap", Vector3(0.1, 0.6, 0.1) * s, Vector3(-0.28, 0.15, -0.75) * s, c[2])
	_parts["arm_r"] = _mesh("cap", Vector3(0.1, 0.6, 0.1) * s, Vector3(0.28, 0.15, -0.75) * s, c[2])
	_parts["arm_l"].rotation.x = -1.4
	_parts["arm_r"].rotation.x = -1.4

func _build_hound(c: Array) -> void:
	_parts["torso"] = _mesh("cap", Vector3(0.3, 0.85, 0.3), Vector3(0, 0.55, 0), c[0])
	_parts["torso"].rotation.x = PI / 2
	_parts["head"] = _mesh("box", Vector3(0.2, 0.2, 0.32), Vector3(0, 0.65, -0.55), c[2])
	for x in [-0.12, 0.12]:
		for z in [-0.3, 0.3]:
			_parts["leg_%s_%s" % [x, z]] = _mesh("cap", Vector3(0.08, 0.5, 0.08), Vector3(x, 0.25, z), c[1])

func attach_hitbox(_zone: String, _area: Area3D) -> void:
	pass  # hitboxes are created on the Zombie body itself

func animate(state: int, speed: float, crippled: bool, head_gone: bool) -> void:
	if _rigged:
		if not _dead:
			_animate_rigged(state, speed, crippled)
		return
	if _dead or _parts.is_empty():
		return
	_t += get_process_delta_time() * (2.0 + speed * 3.0)
	var sway: float = sin(_t) * 0.35 * clamp(speed, 0.0, 1.0)
	if _parts.has("leg_l"):
		_parts["leg_l"].rotation.x = sway
		_parts["leg_r"].rotation.x = -sway
	if _parts.has("torso") and not data.get("quadruped"):
		_parts["torso"].rotation.z = sin(_t * 0.5) * 0.08
	if head_gone and _parts.has("head"):
		_parts["head"].visible = false
	if crippled and not data.get("crawl") and not data.get("quadruped"):
		position.y = -0.7
		rotation.x = 1.2
	if state == Zombie.S.ATTACK and _parts.has("arm_l"):
		_parts["arm_l"].rotation.x = -1.6
		_parts["arm_r"].rotation.x = -1.6
	if variant == "bloater" and _parts.has("torso"):
		_parts["torso"].scale = Vector3.ONE * (1.0 + sin(_t * 0.7) * 0.04)

func hit_react(zone: String) -> void:
	if _rigged:
		if _clip not in ["attack", "grab", "scream"]:
			play_once("hit")
		return
	var t := create_tween()
	t.tween_property(self, "rotation:y", rotation.y + randf_range(-0.15, 0.15), 0.06)
	t.tween_property(self, "rotation:y", rotation.y, 0.2)

func rise() -> void:
	if _rigged:
		play_once("rise", 0.05)
		_oneshot = 2.6
		if _anim and _anim.has_animation("rise"):
			_anim.speed_scale = 2.4   # scrambling up, not a lazy stretch
		return
	var t := create_tween()
	t.tween_property(self, "rotation:x", 0.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", 0.0, 0.9)

func drop_from_ceiling() -> void:
	visible = true
	if _rigged:
		play_once("hit", 0.0)
	position.y = 3.0
	rotation.z = PI
	var t := create_tween()
	t.tween_property(self, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "rotation:z", 0.0, 0.35)

func die(_head_gone: bool) -> void:
	_dead = true
	if _anim and _anim.has_animation("death"):
		_anim.speed_scale = randf_range(0.95, 1.2)
		_anim.play("death", 0.1)
		return
	var t := create_tween()
	t.tween_property(self, "rotation:x", -PI / 2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", 0.15, 0.6)
