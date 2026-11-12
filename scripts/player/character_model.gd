class_name CharacterModel
extends Node3D
## Survivor body. Loads the rigged model of the chosen outfit (see Outfits:
## each outfit is its own textured Meshy model sharing the skeleton layout)
## with its clip library; when no model ships, builds a stand-in figure so
## every system can still be tested.
##
## Body sliders (0..1, 0.5 = base) scale skeleton bones and drive the soft
## shaping regions on the rigged model, or scale the stand-in's parts.

signal outfit_loaded(outfit: String)

var character := "zegan"
var customization: Dictionary = {}
## Outfit id of the model currently built.
var outfit := ""
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _model: Node3D
var _parts: Dictionary = {}
var _t := 0.0
var _current := ""

const BONE_SLIDERS := {
	# slider -> [[bone name, axis scale weights]] (Meshy rig bone names)
	"shoulders": [["LeftShoulder", Vector3(1, 0, 1)], ["RightShoulder", Vector3(1, 0, 1)]],
	"legs": [["LeftUpLeg", Vector3(0, 1, 0)], ["RightUpLeg", Vector3(0, 1, 0)], ["LeftLeg", Vector3(0, 1, 0)], ["RightLeg", Vector3(0, 1, 0)]],
	"muscle": [["LeftArm", Vector3(1, 0, 1)], ["RightArm", Vector3(1, 0, 1)], ["LeftForeArm", Vector3(0.6, 0, 0.6)], ["RightForeArm", Vector3(0.6, 0, 0.6)]],
}

## Soft shaping regions, measured on the rigged models in the A-pose rest
## (skeleton space, centimetres). bone, centre, radii, facing mask, base
## inflate per character, which slider drives it, and spring settings.
const REGIONS := {
	"obcera": [
		{"bone": "Spine01", "c": Vector3(8.5, 120.5, 9.0), "r": Vector3(11.5, 13.0, 17.0), "mask": 1.0, "base": 0.5, "slider": "chest", "range": 0.5, "spring": [190.0, 6.5, 0.026]},
		{"bone": "Spine01", "c": Vector3(-8.5, 120.5, 9.0), "r": Vector3(11.5, 13.0, 17.0), "mask": 1.0, "base": 0.5, "slider": "chest", "range": 0.5, "spring": [190.0, 6.5, 0.026]},
		{"bone": "Hips", "c": Vector3(8.0, 89.0, -1.0), "r": Vector3(12.5, 13.0, 16.0), "mask": 1.0, "back": true, "base": 0.42, "slider": "hips", "range": 0.5, "spring": [240.0, 8.0, 0.016]},
		{"bone": "Hips", "c": Vector3(-8.0, 89.0, -1.0), "r": Vector3(12.5, 13.0, 16.0), "mask": 1.0, "back": true, "base": 0.42, "slider": "hips", "range": 0.5, "spring": [240.0, 8.0, 0.016]},
		{"bone": "Spine02", "c": Vector3(0.0, 106.0, 4.0), "r": Vector3(22.0, 9.0, 16.0), "mask": 0.0, "base": -0.08, "slider": "waist", "range": 0.25},
		{"bone": "Hips", "c": Vector3(0.0, 88.0, 3.0), "r": Vector3(24.0, 12.0, 18.0), "mask": 0.0, "base": 0.06, "slider": "hips", "range": 0.16},
	],
	"zegan": [
		{"bone": "Spine01", "c": Vector3(8.0, 124.0, 6.0), "r": Vector3(12.0, 12.0, 16.0), "mask": 1.0, "base": 0.0, "slider": "chest", "range": 0.22},
		{"bone": "Spine01", "c": Vector3(-8.0, 124.0, 6.0), "r": Vector3(12.0, 12.0, 16.0), "mask": 1.0, "base": 0.0, "slider": "chest", "range": 0.22},
		{"bone": "Hips", "c": Vector3(8.0, 92.0, -4.0), "r": Vector3(12.0, 12.0, 15.0), "mask": 1.0, "back": true, "base": 0.0, "slider": "hips", "range": 0.2},
		{"bone": "Hips", "c": Vector3(-8.0, 92.0, -4.0), "r": Vector3(12.0, 12.0, 15.0), "mask": 1.0, "back": true, "base": 0.0, "slider": "hips", "range": 0.2},
		{"bone": "Spine02", "c": Vector3(0.0, 108.0, 0.0), "r": Vector3(22.0, 9.0, 18.0), "mask": 0.0, "base": 0.0, "slider": "waist", "range": 0.22},
		{"bone": "Hips", "c": Vector3(0.0, 92.0, 0.0), "r": Vector3(22.0, 12.0, 18.0), "mask": 0.0, "base": 0.0, "slider": "hips", "range": 0.12},
	],
}

## Colours for the stand-in figure only (used when no model ships).
const PALETTES := {
	"zegan": {
		"default": {"jacket": Color(0.16, 0.2, 0.17), "shirt": Color(0.55, 0.5, 0.42), "pants": Color(0.12, 0.12, 0.14), "accent": Color(0.75, 0.42, 0.12), "skin": Color(0.72, 0.55, 0.42), "hair": Color(0.08, 0.06, 0.05)},
		"courier": {"jacket": Color(0.5, 0.12, 0.1), "shirt": Color(0.1, 0.1, 0.1), "pants": Color(0.2, 0.22, 0.3), "accent": Color(0.9, 0.85, 0.2), "skin": Color(0.72, 0.55, 0.42), "hair": Color(0.08, 0.06, 0.05)},
		"night_shift": {"jacket": Color(0.06, 0.06, 0.08), "shirt": Color(0.2, 0.25, 0.35), "pants": Color(0.08, 0.08, 0.1), "accent": Color(0.2, 0.7, 0.9), "skin": Color(0.72, 0.55, 0.42), "hair": Color(0.08, 0.06, 0.05)},
	},
	"obcera": {
		"default": {"jacket": Color(0.42, 0.08, 0.12), "shirt": Color(0.1, 0.1, 0.1), "pants": Color(0.18, 0.16, 0.2), "accent": Color(0.85, 0.75, 0.55), "skin": Color(0.62, 0.44, 0.33), "hair": Color(0.04, 0.03, 0.03)},
		"rider": {"jacket": Color(0.05, 0.05, 0.05), "shirt": Color(0.6, 0.1, 0.15), "pants": Color(0.05, 0.05, 0.05), "accent": Color(0.8, 0.8, 0.85), "skin": Color(0.62, 0.44, 0.33), "hair": Color(0.04, 0.03, 0.03)},
		"evening": {"jacket": Color(0.1, 0.05, 0.15), "shirt": Color(0.55, 0.45, 0.65), "pants": Color(0.1, 0.05, 0.15), "accent": Color(0.9, 0.8, 0.5), "skin": Color(0.62, 0.44, 0.33), "hair": Color(0.04, 0.03, 0.03)},
	},
}

## Outfit ids for a character, in picker order (only those in this build).
static func outfits(for_character: String) -> Array:
	return Outfits.ids(for_character).filter(func(o): return Outfits.available(for_character, o))

func _ready() -> void:
	_build(Outfits.resolve(character, customization.get("outfit", Outfits.DEFAULT)))
	apply_customization(customization)

## Builds (or rebuilds) the body for an outfit.
func _build(id: String) -> void:
	if _model:
		_model.queue_free()
		_model = null
	for k in _parts:
		_parts[k]["mesh"].queue_free()
	_parts.clear()
	_anim = null
	_skel = null
	_body_mat = null
	_current = ""
	_held = ""
	_one_shot = false
	outfit = id
	var path := Outfits.model_path(character, id)
	if path != "" and ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate()
		m.rotation.y = PI   # Meshy models face +Z; the player looks down -Z
		add_child(m)
		_model = m
		_skel = m.find_child("Skeleton3D", true, false)
		var old_ap := m.find_child("AnimationPlayer", true, false)
		if old_ap:
			old_ap.get_parent().remove_child(old_ap)
			old_ap.free()
		_anim = AnimationPlayer.new()
		m.add_child(_anim)
		_anim.root_node = NodePath("..")
		var lib_path := Outfits.anims_path(character, id)
		var lib: AnimationLibrary = load(lib_path) if ResourceLoader.exists(lib_path) else null
		if lib:
			_anim.add_animation_library("", lib)
		_anim.animation_finished.connect(func(_n): _current = "")
		_setup_body(m, lib)
	else:
		_build_standin()
	outfit_loaded.emit(id)

func _slider(name: String) -> float:
	return float(customization.get(name, 0.5)) - 0.5   # -0.5 .. 0.5

func apply_customization(c: Dictionary) -> void:
	customization = c
	if is_inside_tree() and Outfits.resolve(character, c.get("outfit", Outfits.DEFAULT)) != outfit:
		_build(Outfits.resolve(character, c.get("outfit", Outfits.DEFAULT)))
	var h := 1.0 + _slider("height") * 0.16
	scale = Vector3(h, h, h)
	if _skel:
		for slider in BONE_SLIDERS:
			var amount := _slider(slider) * 0.5
			for entry in BONE_SLIDERS[slider]:
				var idx := _skel.find_bone(entry[0])
				if idx >= 0:
					_skel.set_bone_pose_scale(idx, Vector3.ONE + entry[1] * amount)
		return
	var pal: Dictionary = PALETTES.get(character, PALETTES["zegan"]).get(outfit, PALETTES[character]["default"])
	for part in _parts:
		var mi: MeshInstance3D = _parts[part]["mesh"]
		mi.material_override = Mats.trim(pal.get(_parts[part]["color"], Color.GRAY), _parts[part].get("rough", 0.6))
	var female := character == "obcera"
	_scale_part("chest", Vector3(1.0 + _slider("chest") * 0.5 + _slider("shoulders") * 0.2, 1, 1.0 + _slider("chest") * 0.6))
	_scale_part("waist", Vector3(1.0 + _slider("waist") * 0.5, 1, 1.0 + _slider("waist") * 0.4))
	_scale_part("hips", Vector3(1.0 + _slider("hips") * 0.5, 1, 1.0 + _slider("hips") * 0.45))
	for leg in ["leg_l", "leg_r"]:
		_scale_part(leg, Vector3(1.0 + _slider("muscle") * 0.3, 1.0 + _slider("legs") * 0.2, 1.0 + _slider("muscle") * 0.3))
	for arm in ["arm_l", "arm_r"]:
		_scale_part(arm, Vector3(1.0 + _slider("muscle") * 0.4, 1, 1.0 + _slider("muscle") * 0.4))

func _scale_part(name: String, s: Vector3) -> void:
	if _parts.has(name):
		_parts[name]["mesh"].scale = s

func _build_standin() -> void:
	var f := character == "obcera"
	var defs := {
		"hips": [Vector3(0, 0.95, 0), Vector3(0.36 if f else 0.34, 0.2, 0.22), "pants"],
		"waist": [Vector3(0, 1.15, 0), Vector3(0.3 if f else 0.34, 0.22, 0.2), "shirt"],
		"chest": [Vector3(0, 1.38, 0), Vector3(0.38 if f else 0.44, 0.28, 0.24), "jacket"],
		"head": [Vector3(0, 1.66, 0), Vector3(0.19, 0.24, 0.21), "skin"],
		"hair": [Vector3(0, 1.74 if not f else 1.66, 0.03), Vector3(0.21, 0.14 if not f else 0.34, 0.23), "hair"],
		"arm_l": [Vector3(-0.27 if not f else -0.24, 1.2, 0), Vector3(0.1, 0.55, 0.1), "jacket"],
		"arm_r": [Vector3(0.27 if not f else 0.24, 1.2, 0), Vector3(0.1, 0.55, 0.1), "jacket"],
		"leg_l": [Vector3(-0.1, 0.45, 0), Vector3(0.14, 0.9, 0.15), "pants"],
		"leg_r": [Vector3(0.1, 0.45, 0), Vector3(0.14, 0.9, 0.15), "pants"],
		"belt": [Vector3(0, 1.04, 0), Vector3(0.37 if f else 0.36, 0.05, 0.24), "accent"],
	}
	for k in defs:
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new() if k in ["arm_l", "arm_r", "leg_l", "leg_r", "head"] else BoxMesh.new()
		if cap is CapsuleMesh:
			cap.radius = defs[k][1].x / 2
			cap.height = defs[k][1].y
		else:
			cap.size = defs[k][1]
		mi.mesh = cap
		mi.position = defs[k][0]
		add_child(mi)
		_parts[k] = {"mesh": mi, "color": defs[k][2]}

const AIM_ANIMS := {"idle": "aim", "walk": "shoot_walk", "run": "run_shoot"}
const STATE_CLIPS := {"downed": "knockdown", "reload": "reload", "hit": "hit"}
var _one_shot := false
var _held := ""   # one-shot clip finished and holding its last pose (knocked down)

func play(state: String, aiming: bool) -> void:
	var anim: String = AIM_ANIMS.get(state, state) if aiming else state
	anim = STATE_CLIPS.get(state, anim)
	if _anim and anim in STATE_CLIPS.values():
		if _current != anim and _held != anim:
			_anim.play(anim, 0.15, 2.0 if anim == "reload" else 1.0)
			_current = anim
			_held = anim if anim == "knockdown" else ""
		return
	if _anim and _held == "knockdown":
		# Back on their feet after a rescue.
		_held = ""
		play_once("stand_up", 0.2, 2.5)
		return
	if _anim and _one_shot and _anim.is_playing():
		# Gestures give way as soon as the player moves; hits and reloads finish.
		if not (state != "idle" and _current in ["call", "shout", "stand_up"]):
			return
	_one_shot = false
	if _anim and _current != anim:
		if _anim.has_animation(anim):
			_anim.play(anim, 0.2)
		elif _anim.has_animation(state):
			_anim.play(state, 0.2)
		_current = anim
	elif not _anim and _parts.has("leg_l"):
		_t += get_process_delta_time() * (9.0 if state == "run" else 5.5 if state == "walk" else 0.0)
		var swing := sin(_t) * (0.5 if state != "idle" else 0.0)
		_parts["leg_l"]["mesh"].rotation.x = swing
		_parts["leg_r"]["mesh"].rotation.x = -swing
		_parts["arm_l"]["mesh"].rotation.x = -1.4 if aiming else -swing * 0.7
		_parts["arm_r"]["mesh"].rotation.x = -1.4 if aiming else swing * 0.7

func flinch() -> void:
	play_once("hit", 0.05)

## Plays a non-looping clip (hit, reload, call, shout, knockdown, stand_up),
## then returns to the movement loop.
func play_once(clip: String, blend := 0.15, speed := 1.0) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, blend, speed)
		_current = clip
		_one_shot = true

# ---------- Body shaping and secondary motion ----------

var _body_mat: ShaderMaterial
var _regions: Array = []      # runtime state per region
var _body_mesh: MeshInstance3D

func _setup_body(m: Node3D, lib: AnimationLibrary = null) -> void:
	_body_mesh = m.find_children("*", "MeshInstance3D", true, false)[0]
	var std := _body_mesh.get_active_material(0) as StandardMaterial3D
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = preload("res://shaders/character_body.gdshader")
	if std:
		_body_mat.set_shader_parameter("albedo_tex", std.albedo_texture)
		_body_mat.set_shader_parameter("has_normal", std.normal_enabled and std.normal_texture != null)
		_body_mat.set_shader_parameter("normal_tex", std.normal_texture)
		_body_mat.set_shader_parameter("normal_scale", std.normal_scale)
		_body_mat.set_shader_parameter("orm_tex", std.roughness_texture if std.roughness_texture else std.metallic_texture)
		var chans := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
		_body_mat.set_shader_parameter("rough_ch", chans[std.roughness_texture_channel] if std.roughness_texture else Vector4.ZERO)
		_body_mat.set_shader_parameter("metal_ch", chans[std.metallic_texture_channel] if std.metallic_texture else Vector4.ZERO)
		_body_mat.set_shader_parameter("roughness", std.roughness if std.roughness_texture else std.roughness)
		_body_mat.set_shader_parameter("metallic", std.metallic)
	_body_mesh.material_override = _body_mat
	_regions.clear()
	# Outfit models carry their own shape, so they keep only part of the base
	# model's built-in shaping; their shaping centres were moved onto their
	# own skeleton by the outfit import.
	var shape: float = Outfits.info(character, outfit).get("shape", 1.0)
	var centers: Array = lib.get_meta("region_centers", []) if lib else []
	var defs: Array = REGIONS.get(character, [])
	for i in defs.size():
		var def: Dictionary = defs[i].duplicate()
		var idx := _skel.find_bone(def["bone"])
		if idx < 0:
			continue
		if i < centers.size():
			def["c"] = centers[i]
		def["base"] = def["base"] * shape
		var rest := _skel.get_bone_global_rest(idx)
		var fwd := Vector3(0, 0, -1) if def.get("back", false) else Vector3(0, 0, 1)
		_regions.append({
			"def": def, "bone": idx,
			"local": rest.affine_inverse() * def["c"],
			"fwd_local": (rest.basis.inverse() * fwd).normalized(),
			"disp": Vector3.ZERO, "vel": Vector3.ZERO, "prev": Vector3.ZERO, "prev_v": Vector3.ZERO, "init": false,
		})
	_update_regions(0.0)

func _process(delta: float) -> void:
	if _body_mat and delta > 0.0:
		_update_regions(minf(delta, 0.05))

func _update_regions(delta: float) -> void:
	var n := 6
	var centers := PackedVector3Array()
	var radii := PackedVector3Array()
	var fwds := PackedVector3Array()
	var offsets := PackedVector3Array()
	var inflates := PackedFloat32Array()
	var masks := PackedFloat32Array()
	var skel_xf := _skel.global_transform
	var to_skel := skel_xf.basis.inverse()
	for i in n:
		if i >= _regions.size():
			centers.append(Vector3(0, -9999, 0)); radii.append(Vector3.ONE); fwds.append(Vector3.FORWARD)
			offsets.append(Vector3.ZERO); inflates.append(0.0); masks.append(0.0)
			continue
		var rg: Dictionary = _regions[i]
		var def: Dictionary = rg["def"]
		var pose := _skel.get_bone_global_pose(rg["bone"])
		var c: Vector3 = pose * rg["local"]
		centers.append(c)
		radii.append(def["r"])
		fwds.append((pose.basis * rg["fwd_local"]).normalized())
		masks.append(def["mask"])
		inflates.append(def["base"] + _slider(def["slider"]) * 2.0 * def["range"] * 0.5)
		# Spring secondary motion, simulated in world metres.
		var off := Vector3.ZERO
		if def.has("spring") and delta > 0.0:
			var wp: Vector3 = skel_xf * c
			if not rg["init"]:
				rg["prev"] = wp
				rg["prev_v"] = Vector3.ZERO
				rg["init"] = true
			var v: Vector3 = (wp - rg["prev"]) / delta
			var acc: Vector3 = (v - rg["prev_v"]) / delta
			rg["prev"] = wp
			rg["prev_v"] = v
			var k: float = def["spring"][0]
			var damp: float = def["spring"][1]
			var lim: float = def["spring"][2]
			var a: Vector3 = -k * rg["disp"] - damp * rg["vel"] - acc.limit_length(60.0) * 0.6
			rg["vel"] += a * delta
			rg["disp"] = (rg["disp"] + rg["vel"] * delta).limit_length(lim)
			off = to_skel * rg["disp"]
		offsets.append(off)
	_body_mat.set_shader_parameter("r_center", centers)
	_body_mat.set_shader_parameter("r_radius", radii)
	_body_mat.set_shader_parameter("r_fwd", fwds)
	_body_mat.set_shader_parameter("r_offset", offsets)
	_body_mat.set_shader_parameter("r_inflate", inflates)
	_body_mat.set_shader_parameter("r_mask", masks)
