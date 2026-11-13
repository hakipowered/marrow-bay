class_name ZombieModel
extends Node3D
## Enemy body. Human infected use a rigged, animated scanned model
## (res://assets/characters/enemies/<model>/<model>.glb plus <model>_anims.res),
## made infected by shaders/infected_body.gdshader. The clip follows the synced
## `state`, so both players see the same thing. The hound has its own scanned,
## rigged dog (shaders/infected_hound.gdshader; clips from tools/hound/).
## Types with no model yet (larva, brood mother) are never spawned
## (EnemyDB.has_model); the stand-in builders below are only for tests.

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
var _hound := false
var _bone_att := {}
var _last_state := -1

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
	"bloated": {"flesh": Color(0.6, 0.62, 0.52), "veins": 1.0, "bile": 0.35},
	"spitter": {"bile": 0.8, "skin_legs": 1.0, "flesh": Color(0.62, 0.64, 0.55)},
	"ventling": {"bile": 0.4, "skin_legs": 1.0, "blood": 1.0},
	"screamer": {"flesh": Color(0.68, 0.68, 0.66), "veins": 1.0},
	"brute": {"blood": 1.0, "flesh": Color(0.55, 0.52, 0.5)},
	"grappler": {"blood": 1.0, "flesh": Color(0.62, 0.5, 0.48)},
	"jogger": {"skin_legs": 0.0},
}
## Fixes for how a scanned model's materials came out, per model.
const MODEL_FIX := {
	"brute": {"rough_min": 0.62, "metallic": 0.0},   # shirt scanned as glossy latex
}
## Riot shield placement in the left forearm bone's space (tuned by render).
const SHIELD_OFFSET := Vector3(0.0, 0.16, 0.09)
const SHIELD_ROT := Vector3(0, 0, 0)
## Native speed of each moving clip in m/s, so feet don't slide.
const CLIP_SPEED := {"shamble": 0.75, "walk": 1.3, "run": 3.6, "sprint": 5.0, "crawl": 0.5}
## The hound's gaits (tools/hound/animate.py): walk, trot, gallop.
const HOUND_CLIP_SPEED := {"walk": 1.0, "trot": 2.5, "run": 4.1}
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
	if not data.get("tiny") and variant != "brood_mother" and _load_rigged():
		return
	if data.get("quadruped"):
		return   # no hound model: EnemyDB.has_model keeps it out of the game
	var c: Array = LOOK_COLORS.get(look, LOOK_COLORS["office"])
	if data.get("crawl"):
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
	_hound = data.get("quadruped", false)
	if _hound:
		id = "hound"
	var own := true
	if not ResourceLoader.exists("res://assets/characters/enemies/%s/%s.glb" % [id, id]):
		if _hound:
			return false
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
	var lib: AnimationLibrary = load(lib_path)
	ClipFix.fix_library(lib)
	_anim.add_animation_library("", lib)
	# The death clips fitted to this body (tools/import_death_clips.gd). Added
	# here, before anything plays: adding a library mid-clip crashes 4.4.
	var deaths_path := "res://assets/characters/enemies/%s/%s_deaths.res" % [id, id]
	if ResourceLoader.exists(deaths_path):
		_deaths = load(deaths_path)
		_anim.add_animation_library("deaths", _deaths)
	_body = m
	_skel = m.find_child("Skeleton3D", true, false) as Skeleton3D
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
	if data.get("shield"):
		_strap_shield(m)
	if variant == "ventling":
		visible = false
	_play("idle", 0.0)
	return true

## Riot type: a scuffed clear riot shield strapped to the left forearm, so it
## swings with the arm in every clip.
func _strap_shield(m: Node3D) -> void:
	var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.find_bone("LeftForeArm") < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "LeftForeArm"
	sk.add_child(att)
	# Meshy armatures are scaled 0.01 (centimetre bones); undo that so the
	# shield is built in metres.
	var k := 1.0
	var n: Node = sk
	while n != null and n != m:
		if n is Node3D:
			k *= (n as Node3D).scale.x
		n = n.get_parent()
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / k
	holder.position = SHIELD_OFFSET / k
	holder.rotation_degrees = SHIELD_ROT
	att.add_child(holder)
	_shield = holder
	var clear := StandardMaterial3D.new()
	clear.albedo_color = Color(0.55, 0.6, 0.62, 0.32)
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.roughness = 0.12
	clear.metallic_specular = 0.8
	clear.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pane := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.52, 0.86, 0.012)
	pane.mesh = pm
	pane.material_override = clear
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(pane)
	# Cracks spread over the pane as it takes fire (crack_shield).
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_texture = _crack_texture()
	_crack_mat.albedo_color = Color(0.92, 0.95, 0.97, 0.0)
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var crack := MeshInstance3D.new()
	var cm := QuadMesh.new()
	cm.size = Vector2(0.5, 0.84)
	crack.mesh = cm
	crack.position.z = 0.008
	crack.material_override = _crack_mat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(crack)
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.05, 0.05, 0.06)
	rim.roughness = 0.6
	for e in [[Vector3(0, 0.44, 0), Vector3(0.54, 0.03, 0.025)], [Vector3(0, -0.44, 0), Vector3(0.54, 0.03, 0.025)],
			[Vector3(0.265, 0, 0), Vector3(0.03, 0.9, 0.025)], [Vector3(-0.265, 0, 0), Vector3(0.03, 0.9, 0.025)]]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		b.mesh = bm
		b.position = e[0]
		b.material_override = rim
		holder.add_child(b)
	var band := MeshInstance3D.new()
	var bandm := BoxMesh.new()
	bandm.size = Vector3(0.4, 0.05, 0.014)
	band.mesh = bandm
	band.position = Vector3(0, 0.12, 0.002)
	var bandmat := StandardMaterial3D.new()
	bandmat.albedo_color = Color(0.7, 0.7, 0.68)
	bandmat.roughness = 0.5
	band.material_override = bandmat
	holder.add_child(band)

var _shield: Node3D = null
var _crack_mat: StandardMaterial3D = null
static var _crack_tex: Texture2D = null

## 0 = clear .. 1 = about to give: the crack web shows through more and more.
func crack_shield(amount: float) -> void:
	if _crack_mat:
		_crack_mat.albedo_color.a = clampf(0.25 + amount * 0.85, 0.0, 1.0)

## The shield breaks off: it drops from his arm, tumbles and lies there.
func drop_shield() -> void:
	if _shield == null or not is_instance_valid(_shield):
		return
	var xf := _shield.global_transform
	var level := get_tree().current_scene
	_shield.get_parent().remove_child(_shield)
	level.add_child(_shield)
	_shield.global_transform = xf
	if _crack_mat:
		_crack_mat.albedo_color.a = 1.0
	var floor_y := global_position.y + 0.03
	var side := global_transform.basis.x * (0.3 if randf() < 0.5 else -0.3)
	var t := _shield.create_tween()
	t.set_parallel(true)
	t.tween_property(_shield, "global_position", Vector3(xf.origin.x, floor_y, xf.origin.z) + side - global_transform.basis.z * 0.4, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_shield, "rotation", Vector3(-PI / 2, _shield.rotation.y + randf_range(-0.6, 0.6), 0.0), 0.55)
	_shield = null

## A web of cracks radiating from a few impact points (made once, shared).
static func _crack_texture() -> Texture2D:
	if _crack_tex:
		return _crack_tex
	var w := 128
	var h := 214
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for c in 4:
		var origin := Vector2(rng.randf_range(0.25, 0.75) * w, rng.randf_range(0.2, 0.8) * h)
		for r in 9:
			var p := origin
			var ang := rng.randf() * TAU
			for step in rng.randi_range(20, 60):
				ang += rng.randf_range(-0.35, 0.35)
				p += Vector2(cos(ang), sin(ang)) * 1.6
				if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
					break
				var a := 0.95 - step * 0.012
				img.set_pixelv(Vector2i(p), Color(1, 1, 1, maxf(a, 0.35)))
		# The ring around each impact.
		for i in 40:
			var ang2 := TAU * i / 40.0
			var q := origin + Vector2(cos(ang2), sin(ang2)) * rng.randf_range(4.0, 7.0)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				img.set_pixelv(Vector2i(q), Color(1, 1, 1, 0.8))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex

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
	_mat.shader = preload("res://shaders/infected_hound.gdshader") if id == "hound" else preload("res://shaders/infected_body.gdshader")
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
	var fix: Dictionary = MODEL_FIX.get(id, {})
	for k in fix:
		_mat.set_shader_parameter(k, fix[k])
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
func play_once(clip: String, blend := 0.12, speed := 1.0) -> void:
	if not _rigged or _dead or _anim == null or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, blend)
	_anim.speed_scale = speed
	_oneshot = _anim.get_animation(clip).length * (0.55 if clip == "hit" else 0.9) / speed

func _animate_rigged(state: int, speed: float, crippled: bool) -> void:
	var dt := get_process_delta_time()
	# A swing starting always shows from its first frame (the strike is timed
	# from it), even if a scream or a flinch was still finishing.
	if state == Zombie.S.ATTACK and _clip not in ["attack", "lunge", "bite"] and not (crippled or data.get("crawl")):
		_oneshot = 0.0
	if _oneshot > 0.0:
		_oneshot -= dt
		return
	if _hound:
		_animate_hound(state, speed)
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
			# Lies as if it had died, each one sprawled its own way. One
			# dropping in through the ceiling flails until it lands (land()).
			var lying := _lying_anim()
			if not _falling and _clip != lying:
				_play(lying, 0.0)
				_anim.seek(_anim.current_animation_length - 0.01, true)
				_anim.pause()
		Zombie.S.ATTACK:
			if crippled or data.get("crawl"):
				_play("crawl", 0.15, 1.6)
			elif _clip != "attack":
				var at := Zombie.attack_timing(data)
				_play("attack", 0.1, at["speed"])
				_anim.seek(at["from"], true)
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
				if state == Zombie.S.CHARGE or (runner and speed > 3.2):
					clip = "sprint"
				elif speed > 1.8:
					clip = "run"
				elif speed > 1.1:
					clip = "walk"
				# Clip speed follows the ground speed so the feet don't skate.
				_play(clip, 0.3, clampf(speed / CLIP_SPEED[clip], 0.5, 1.8), true)

## The hound: idles or feeds on a kill, walks, trots or gallops by pace, leaps
## at you when it comes in at a gallop or snaps when it's already close, and
## reels from a hit. The bite lands on the clip's 1.5 s mark like a swing.
func _animate_hound(state: int, speed: float) -> void:
	var entered := state != _last_state
	_last_state = state
	match state:
		Zombie.S.IDLE, Zombie.S.HIDDEN:
			_play("idle", 0.4, _speed_var * 0.9, true)
		Zombie.S.FEED:
			_play("feed", 0.4, _speed_var, true)
		Zombie.S.ATTACK:
			if entered or _clip not in ["lunge", "bite"]:
				var at := Zombie.attack_timing(data)
				var clip := "lunge" if _clip in ["run", "lunge"] and entered else "bite"
				_clip = ""
				_play(clip, 0.08, at["speed"])
				_anim.seek(at["from"], true)
		Zombie.S.STAGGER:
			_play("hit", 0.1, 0.8)
		Zombie.S.DEAD, Zombie.S.PLAY_DEAD:
			pass
		_:
			if speed < 0.15:
				_play("idle", 0.3, _speed_var * 0.9, true)
			else:
				var clip := "walk"
				if speed > 3.0 or state == Zombie.S.CHARGE:
					clip = "run"
				elif speed > 1.5:
					clip = "trot"
				_play(clip, 0.22, clampf(speed / HOUND_CLIP_SPEED[clip], 0.6, 1.8), true)

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

## Hitboxes that ride on a bone (the hound's), so a leaping, reeling or dead
## hound is hit where its body actually is. False if there's no such bone.
func attach_hitbox(bone: String, area: Area3D) -> bool:
	if _skel == null or _skel.find_bone(bone) < 0:
		return false
	var att: BoneAttachment3D = _bone_att.get(bone)
	if att == null:
		att = BoneAttachment3D.new()
		att.bone_name = bone
		_skel.add_child(att)
		_bone_att[bone] = att
	att.add_child(area)
	return true

func has_bones() -> bool:
	return _skel != null

func animate(state: int, speed: float, crippled: bool, head_gone: bool) -> void:
	if _rigged:
		if not _dead:
			_animate_rigged(state, speed, crippled)
		elif _death_on:
			_tick_death(get_physics_process_delta_time())
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

## flinch: the hit rocked it (a sharp, quick jolt of the hit clip). Hits
## that don't (it's still shrugging off the last one) show as blood and sound.
func hit_react(zone: String, flinch := true) -> void:
	if _rigged:
		if flinch and _clip not in ["grab", "scream", "rise"]:
			play_once("hit", 0.06, 1.7)
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

## Out of a vent: drops feet first from `from_y` (its feet at the opening,
## the rest of it still up in the duct), flailing, straight down through
## the hole onto the floor.
func drop_from_ceiling(from_y := 3.0) -> void:
	visible = true
	if _rigged:
		play_once("hit", 0.0)
	position.y = from_y
	var dur := clampf(sqrt(2.0 * from_y / 16.0), 0.35, 0.8)
	var t := create_tween()
	t.tween_property(self, "position:y", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# ---------------------------------------------------------------- deaths
#
# Each body has its own fitted death clips ("deaths/<clip>", see
# tools/import_death_clips.gd). The host picks one per kill (Zombie._death_plan:
# by where the round came from, the weapon, the body part, what the infected
# was doing and its type) and sends the same plan to both phones:
#   c  clip            y  yaw the body twists to as it goes down (radians)
#   s  clip speed      k  how much of the clip's own travel to keep (a wall
#   p  push (zombie-local metres, a blast or a charge carrying the body on)
#   f  floor step (metres; the body comes to rest lower or higher than its feet)
#   from  seconds into the clip to start at (a crawler only slumps flat)

var _deaths: AnimationLibrary = null
var _body: Node3D = null          # the scanned model (faces +Z, maybe scaled)
var _skel: Skeleton3D = null
var _death := {}
var _death_on := false
var _death_t := 0.0
var _death_name := ""
var _death_yaw0 := 0.0
var _pooled := false

## The death clips this body has (empty for stand-ins).
func death_clips() -> PackedStringArray:
	return _deaths.get_meta("clips", PackedStringArray()) if _deaths else PackedStringArray()

## Where the clip leaves the body lying, in the zombie's own space: its head,
## hands, feet, hips and chest, for a plan's twist, travel and push.
func death_points(clip: String, yaw: float, k := 1.0, push := Vector3.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _deaths == null or _body == null:
		return out
	var pts: PackedVector3Array = _deaths.get_meta("end_" + clip, PackedVector3Array())
	var fall: Vector2 = _deaths.get_meta("fall_" + clip, Vector2.ZERO)
	var shift := Vector3(fall.x, 0.0, fall.y) * (k - 1.0)
	var turn := Basis(Vector3.UP, yaw)
	for p in pts:
		out.append(turn * (_body.transform * (p + shift)) + push)
	return out

## Which way the clip throws the body (zombie space, flat, unit; zero if it
## folds up where it stands).
func death_fall(clip: String) -> Vector3:
	if _deaths == null or _body == null:
		return Vector3.ZERO
	var fall: Vector2 = _deaths.get_meta("fall_" + clip, Vector2.ZERO)
	var v := _body.transform.basis * Vector3(fall.x, 0.0, fall.y)
	v.y = 0.0
	return v.normalized() if v.length() > 0.35 else Vector3.ZERO

func death_length(clip: String) -> float:
	if _deaths and _deaths.has_animation(clip):
		return _deaths.get_animation(clip).length
	return 0.0

## Seconds into the clip when the body is down.
func death_land(clip: String) -> float:
	return float(_deaths.get_meta("land_" + clip, 1.0)) if _deaths else 1.0

## The death pose a body playing dead lies in ("" if none).
func lying_clip() -> String:
	return _lying

var _lying := ""

## The clip a body lying there plays: its own sprawl (on its back, so the
## stand-up clip starts from the same pose), or the plain death clip.
func _lying_anim() -> String:
	if _deaths == null:
		return "death"
	if _lying == "":
		_lying = ["fall_back", "slow_back", "sit_back"][int(_loop_offset * 3.0) % 3]
	return "deaths/" + _lying

## Dropping in through a hole in the ceiling: flailing as it falls (the hit
## clip, slowed), then it buckles backward where it lands (the last part of a
## fall-on-its-back death) and lies still until it gets up (rise).
var _falling := false

func fall() -> void:
	visible = true
	if not _rigged:
		return
	_falling = true
	_oneshot = 0.0
	# Not fall_back here: its arms fly out level as it topples (reads as a
	# T-pose). It still lies the way it landed when it's shot or gets up.
	if _deaths:
		_lying = ["slow_back", "sit_back"][int(_loop_offset * 2.0) % 2]
	_clip = "hit"
	_anim.play("hit", 0.0)
	_anim.seek(0.15, true)
	_anim.speed_scale = 0.8

func land() -> void:
	_falling = false
	if not _rigged:
		var t := create_tween()
		t.tween_property(self, "rotation:x", -PI / 2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(self, "position:y", 0.15, 0.5)
		return
	var clip := _lying_anim()
	_clip = clip
	_anim.play(clip, 0.15)
	if _deaths:
		# Already folding when it hits: on the floor a beat later.
		_anim.seek(maxf(death_land(_lying) - 0.2, 0.0), true)
		_anim.speed_scale = 1.2
	else:
		_anim.seek(1.7, true)
		_anim.speed_scale = 1.5

func die(head_gone: bool, plan := {}) -> void:
	_dead = true
	_falling = false
	_oneshot = 0.0
	if _hound and _anim:
		# The host picked it (Zombie._death_plan): shot down at full tilt its
		# legs fold under it; otherwise it rolls onto one side or the other.
		var pick: String = plan.get("c", "death")
		if not _anim.has_animation(pick):
			pick = "death"
		_anim.speed_scale = float(plan.get("s", 1.0))
		_anim.play(pick, 0.12)
		return
	if _rigged and _anim:
		var clip: String = plan.get("c", "")
		if _deaths and _deaths.has_animation(clip):
			_start_death(clip, plan)
		elif _anim.has_animation("death"):
			var down := _anim.assigned_animation == "death" and not _anim.is_playing() \
					and _anim.current_animation_position >= _anim.get_animation("death").length - 0.05
			if not down:   # (already down: played dead, or dropped in and crumpled)
				_anim.speed_scale = randf_range(0.95, 1.2)
				_anim.play("death", 0.1)
		_carry_flames()
		return
	# Stand-ins (hound, larva, brood mother) flop over to one side or the other.
	var side := 1.0 if float(plan.get("y", randf() - 0.5)) >= 0.0 else -1.0
	var t := create_tween()
	if data.get("quadruped") or data.get("tiny") or data.get("crawl"):
		t.tween_property(self, "rotation:z", side * PI / 2, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(self, "position:y", 0.12, 0.45)
	else:
		t.tween_property(self, "rotation:x", -PI / 2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(self, "position:y", 0.15, 0.6)

func _start_death(clip: String, plan: Dictionary) -> void:
	_death = plan
	_death_name = "deaths/" + clip
	_death_t = 0.0
	_death_on = true
	_death_yaw0 = rotation.y
	_clip = _death_name
	var from: float = plan.get("from", 0.0)
	_anim.play(_death_name, 0.45 if from > 0.0 else 0.14)
	_anim.speed_scale = float(plan.get("s", 1.0))
	if from > 0.0:
		_anim.seek(from, true)

## Twist, push and floor step, eased in over the fall; then the pool of
## blood once it's down.
func _tick_death(dt: float) -> void:
	_death_t += dt
	var playing := _anim.current_animation == _death_name
	var ct: float = _anim.current_animation_position if playing else death_length(_death_name.trim_prefix("deaths/"))
	var clip := _death_name.trim_prefix("deaths/")
	var land: float = _deaths.get_meta("land_" + clip, 1.0)
	var tw := clampf(_death_t / 0.32, 0.0, 1.0)
	rotation.y = lerp_angle(_death_yaw0, float(_death.get("y", 0.0)), 1.0 - pow(1.0 - tw, 3.0))
	var push: Vector3 = _death.get("p", Vector3.ZERO)
	var pk := clampf(_death_t / 0.5, 0.0, 1.0)
	var off := push * (1.0 - pow(1.0 - pk, 2.0))
	var k: float = _death.get("k", 1.0)
	if absf(k - 1.0) > 0.01:
		off += Basis(Vector3.UP, rotation.y) * (_body.transform.basis * (_travel_at(clip, ct) * (k - 1.0)))
	off.y += float(_death.get("f", 0.0)) * smoothstep(0.0, maxf(land, 0.1), ct)
	position = off
	if not _pooled and ct >= land:
		_pooled = true
		_blood_pool()
	if not playing and _death_t > 0.5:
		_death_on = false

## The hips' travel at clip time t (model space, metres; flat).
func _travel_at(clip: String, t: float) -> Vector3:
	var c: PackedVector3Array = _deaths.get_meta("travel_" + clip, PackedVector3Array())
	if c.is_empty():
		return Vector3.ZERO
	if t <= c[0].x:
		return Vector3(c[0].y, 0.0, c[0].z)
	for i in range(1, c.size()):
		if c[i].x >= t:
			var f := (t - c[i - 1].x) / maxf(c[i].x - c[i - 1].x, 0.0001)
			return Vector3(lerpf(c[i - 1].y, c[i].y, f), 0.0, lerpf(c[i - 1].z, c[i].z, f))
	var e := c[c.size() - 1]
	return Vector3(e.y, 0.0, e.z)

## Blood seeping out from under the chest once the body is down.
func _blood_pool() -> void:
	if _skel == null or not is_inside_tree():
		return
	var b := _skel.find_bone("Spine01")
	if b < 0:
		return
	var at := _skel.global_transform * _skel.get_bone_global_pose(b).origin
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 1.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var big: float = data.get("bulk", 1.0)
	var d: Decal = Decals.splat("blood", hit.position, hit.normal, 0.35 * big)
	if d == null:
		return
	var grow := d.create_tween()
	grow.tween_property(d, "size", Vector3(1.25, 0.3, 1.25) * big * randf_range(0.85, 1.15), 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## If it was burning, the flames stay on the body as it falls instead of
## hanging in the air where its chest was.
func _carry_flames() -> void:
	var fire := get_parent().get_node_or_null("Burning") as Node3D if get_parent() else null
	if fire == null or _skel == null or _skel.find_bone("Spine01") < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Spine01"
	_skel.add_child(att)
	var holder := Node3D.new()
	var k := 1.0
	var n: Node = _skel
	while n != null and n != self:
		if n is Node3D:
			k *= (n as Node3D).scale.x
		n = n.get_parent()
	holder.scale = Vector3.ONE / k
	att.add_child(holder)
	fire.reparent(holder, false)
	fire.position = Vector3.ZERO
