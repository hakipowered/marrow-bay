class_name CharacterModel
extends Node3D
## Survivor body. Loads the rigged model at res://assets/characters/<id>/<id>.glb
## when present (skeleton + animations); otherwise builds a stand-in figure so
## every system can be tested today.
##
## Body sliders (0..1, 0.5 = base) scale skeleton bones on the rigged model,
## or the stand-in's parts. Outfits swap material sets by name.

var character := "zegan"
var customization: Dictionary = {}
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _parts: Dictionary = {}
var _t := 0.0
var _current := ""

const BONE_SLIDERS := {
	# slider -> [[bone name, axis scale weights]]
	"shoulders": [["clavicle_l", Vector3(1, 0, 1)], ["clavicle_r", Vector3(1, 0, 1)]],
	"chest": [["spine_03", Vector3(1, 0.4, 1)]],
	"waist": [["spine_01", Vector3(1, 0, 1)]],
	"hips": [["pelvis", Vector3(1, 0, 1)], ["thigh_l", Vector3(1, 0, 1)], ["thigh_r", Vector3(1, 0, 1)]],
	"legs": [["thigh_l", Vector3(0, 1, 0)], ["thigh_r", Vector3(0, 1, 0)], ["calf_l", Vector3(0, 1, 0)], ["calf_r", Vector3(0, 1, 0)]],
	"muscle": [["upperarm_l", Vector3(1, 0, 1)], ["upperarm_r", Vector3(1, 0, 1)], ["thigh_l", Vector3(0.5, 0, 0.5)], ["thigh_r", Vector3(0.5, 0, 0.5)]],
}

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

static func outfits(for_character: String) -> Array:
	return PALETTES.get(for_character, {}).keys()

func _ready() -> void:
	var path := "res://assets/characters/%s/%s.glb" % [character, character]
	if ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate()
		add_child(m)
		_anim = m.find_child("AnimationPlayer", true, false)
		_skel = m.find_child("Skeleton3D", true, false)
	else:
		_build_standin()
	apply_customization(customization)

func _slider(name: String) -> float:
	return float(customization.get(name, 0.5)) - 0.5   # -0.5 .. 0.5

func apply_customization(c: Dictionary) -> void:
	customization = c
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
	var pal: Dictionary = PALETTES.get(character, PALETTES["zegan"]).get(c.get("outfit", "default"), PALETTES[character]["default"])
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

func play(state: String, aiming: bool) -> void:
	var anim := ("aim_" if aiming else "") + state
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
	if _anim and _anim.has_animation("hit"):
		_anim.play("hit", 0.05)
