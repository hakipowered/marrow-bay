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
var _sole_local := {}   # side -> [thigh bone, foot bone, point under the ankle in foot space]
var _to_model := Transform3D()
## Finger joints and the hands' grip (null on a stand-in body).
var hand_rig: HandRig

const BONE_SLIDERS := {
	# slider -> [[bone name, axis scale weights]] (Meshy rig bone names)
	"shoulders": [["LeftShoulder", Vector3(1, 0, 1)], ["RightShoulder", Vector3(1, 0, 1)]],
	# Thighs only: the shin and foot inherit the thigh's scale, so the whole leg
	# grows by the same factor (scaling the shin as well compounded to +56%).
	"legs": [["LeftUpLeg", Vector3(0, 0.88, 0)], ["RightUpLeg", Vector3(0, 0.88, 0)]],
	"muscle": [["LeftArm", Vector3(1, 0, 1)], ["RightArm", Vector3(1, 0, 1)], ["LeftForeArm", Vector3(0.6, 0, 0.6)], ["RightForeArm", Vector3(0.6, 0, 0.6)]],
}

## Soft shaping regions, measured on the rigged models in the A-pose rest
## (skeleton space, centimetres). bone, centre, radii, facing mask, base
## inflate per character, which slider drives it, and spring settings.
const REGIONS := {
	"obcera": [
		{"bone": "Spine01", "c": Vector3(8.5, 120.5, 9.0), "r": Vector3(11.5, 13.0, 17.0), "mask": 1.0, "base": 0.5, "slider": "chest", "range": 1.0, "spring": [190.0, 6.5, 0.026]},
		{"bone": "Spine01", "c": Vector3(-8.5, 120.5, 9.0), "r": Vector3(11.5, 13.0, 17.0), "mask": 1.0, "base": 0.5, "slider": "chest", "range": 1.0, "spring": [190.0, 6.5, 0.026]},
		{"bone": "Hips", "c": Vector3(8.0, 89.0, -1.0), "r": Vector3(12.5, 13.0, 16.0), "mask": 1.0, "back": true, "base": 0.42, "slider": "hips", "range": 0.8, "spring": [240.0, 8.0, 0.016]},
		{"bone": "Hips", "c": Vector3(-8.0, 89.0, -1.0), "r": Vector3(12.5, 13.0, 16.0), "mask": 1.0, "back": true, "base": 0.42, "slider": "hips", "range": 0.8, "spring": [240.0, 8.0, 0.016]},
		{"bone": "Spine02", "c": Vector3(0.0, 106.0, 4.0), "r": Vector3(22.0, 9.0, 16.0), "mask": 0.0, "base": -0.08, "slider": "waist", "range": 0.6},
		{"bone": "Hips", "c": Vector3(0.0, 88.0, 3.0), "r": Vector3(24.0, 12.0, 18.0), "mask": 0.0, "base": 0.06, "slider": "hips", "range": 0.4},
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

## Characters who wear one shared head on every outfit (the outfit models
## have their own head cut away by tools/outfits/shared_head.py).
const SHARED_HEAD := {"obcera": "res://assets/characters/obcera/head/obcera_head.glb"}

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
	hand_rig = null
	_sole_local.clear()
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
		# Finger joints, before the animations bind to the skeleton.
		var meshes := m.find_children("*", "MeshInstance3D", true, false)
		hand_rig = HandRig.build(_skel, meshes[0] if meshes.size() > 0 else null)
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
			ClipFix.fix_library(lib)
			_anim.add_animation_library("", lib)
		# Every other library (combat clips, the aim stance) goes on now,
		# before anything plays: adding one mid-blend crashes Godot 4.4.
		prepare_clips()
		_anim.animation_finished.connect(func(_n): _current = "")
		_setup_body(m, lib)
		_attach_head()
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
		# Keep the soles on the floor: longer legs would push the feet through
		# it, and some outfits' heels stand a little proud of the base model.
		if _model:
			_skel.force_update_all_bone_transforms()
			_update_lift()
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

## Keeps the soles where they would be without the Legs slider: the thigh's
## scale carries the shin and foot with it, so longer legs would push the
## feet through the floor. Worked out on the current pose every frame (bent
## knees lengthen less than straight ones) from a point under each ankle.
func _update_lift() -> void:
	if _sole_local.is_empty():
		var chain := Transform3D()
		var n: Node = _skel
		while n != _model and n is Node3D:
			chain = (n as Node3D).transform * chain
			n = n.get_parent()
		_to_model = Transform3D(_model.transform.basis, Vector3.ZERO) * chain
		for side in ["Left", "Right"]:
			var u := _skel.find_bone(side + "UpLeg")
			var ft := _skel.find_bone(side + "Foot")
			if u < 0 or ft < 0:
				continue
			var foot := _skel.get_bone_global_rest(ft)
			var ankle := _to_model * foot.origin
			var sole := _to_model.affine_inverse() * Vector3(ankle.x, 0.0, ankle.z)
			_sole_local[side] = [u, ft, foot.affine_inverse() * sole]
	var low_scaled := INF
	var low_plain := INF
	for side in _sole_local:
		var e: Array = _sole_local[side]
		var thigh := _skel.get_bone_global_pose(e[0])
		var sole: Vector3 = _skel.get_bone_global_pose(e[1]) * e[2]
		var undo := Basis.from_scale(Vector3.ONE / _skel.get_bone_pose_scale(e[0]))
		var plain := thigh * Transform3D(undo, Vector3.ZERO) * thigh.affine_inverse() * sole
		low_scaled = minf(low_scaled, (_to_model * sole).y)
		low_plain = minf(low_plain, (_to_model * plain).y)
	var lift := low_plain - low_scaled if low_scaled < INF else 0.0
	_model.position.y = lift - float(Outfits.info(character, outfit).get("sole", 0.0))

## Where a bone is in the current pose, in this node's space, or null when
## the model has no skeleton or no such bone.
func bone_position(bone: String) -> Variant:
	if not _skel or not _skel.is_inside_tree():
		return null
	var i := _skel.find_bone(bone)
	if i < 0:
		return null
	return to_local(_skel.global_transform * _skel.get_bone_global_pose(i).origin)

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

## Moving with the gun up uses stance/aim_walk (walking legs, the aim held
## steady above the hips), not the rig's shoot_walk, whose feet barely move.
const AIM_ANIMS := {"idle": "stance/aim", "walk": "stance/aim_walk", "run": "stance/aim_walk"}
## How fast each loop's feet carry the body at 1x (measured from the clips'
## foot travel). The clip plays at ground speed / this, so feet don't skate.
const NATURAL_SPEED := {"walk": 1.23, "run": 2.9, "stance/aim_walk": 1.23, "shoot_walk": 0.25, "run_shoot": 1.4}
## The body's real ground speed (m/s), set by the player every frame.
var move_speed := 0.0
## Aiming with a knife, hatchet or grenade: the combat stance when standing.
const GUARD_ANIMS := {"idle": "combat/guard"}
const STATE_CLIPS := {"downed": "knockdown", "reload": "reload", "hit": "hit"}
var _one_shot := false
var _held := ""   # one-shot clip finished and holding its last pose (knocked down)
var _cancel_at := -1.0   # a combat clip may give way to movement after this point
## How the equipped weapon is held (HeldWeapon.MODELS hold): gun, blade, palm.
var hold := "gun"

func play(state: String, aiming: bool) -> void:
	var aims: Dictionary = AIM_ANIMS if hold == "gun" or hold == "" else GUARD_ANIMS
	var anim: String = aims.get(state, state) if aiming else state
	anim = STATE_CLIPS.get(state, anim)
	if _anim and anim in STATE_CLIPS.values():
		if _current != anim and _held != anim:
			_anim.speed_scale = 1.0
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
		# Gestures give way as soon as the player moves; hits and reloads
		# finish; a swing can be cut short once it has landed.
		var cancel := _cancel_at >= 0.0 and _anim.current_animation_position >= _cancel_at
		if not (state != "idle" and (_current in ["call", "shout", "stand_up"] or cancel)):
			return
	_one_shot = false
	if _anim and _current != anim:
		if not _anim.has_animation(anim) and _anim.has_animation(state):
			anim = state
		if _anim.has_animation(anim):
			_anim.play(anim, 0.2)
		_current = anim
	if _anim:
		var nat: float = NATURAL_SPEED.get(_current, 0.0)
		_anim.speed_scale = clampf(move_speed / nat, 0.6, 1.7) if nat > 0.0 and move_speed > 0.05 else 1.0
	elif _parts.has("leg_l"):
		_t += get_process_delta_time() * (9.0 if state == "run" else 5.5 if state == "walk" else 0.0)
		var swing := sin(_t) * (0.5 if state != "idle" else 0.0)
		_parts["leg_l"]["mesh"].rotation.x = swing
		_parts["leg_r"]["mesh"].rotation.x = -swing
		_parts["arm_l"]["mesh"].rotation.x = -1.4 if aiming else -swing * 0.7
		_parts["arm_r"]["mesh"].rotation.x = -1.4 if aiming else swing * 0.7

## Adds the melee and throw clips and the standing aim to this body's
## AnimationPlayer. Call it right after the base clips are added and before
## anything plays: adding a clip library while a clip is playing or blending
## crashes the engine (the player keeps pointers into its old clip table).
func prepare_clips() -> void:
	if _anim == null or _skel == null:
		return
	CombatClips.attach(_anim, _skel, character)
	build_stance(_anim)

## Bones that carry the aim: everything above the hips.
const UPPER_BONES := ["Spine02", "Spine01", "Spine", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]

## Standing aim, "stance/aim": the raised two-handed hold from the walking
## aim clip, frozen, over the idle clip's legs and breathing hips. (The rig's
## own "aim" clip holds the gun down at the hip, which reads as not aiming
## once a real gun is in the hand.) Built from whatever clips this player
## has, so it fits every outfit skeleton.
static func build_stance(ap: AnimationPlayer) -> void:
	if ap.has_animation_library("stance") or not ap.has_animation("idle") or not ap.has_animation("shoot_walk"):
		return
	var idle := ap.get_animation("idle")
	var walk := ap.get_animation("shoot_walk")
	var a: Animation = idle.duplicate(true)
	for t in a.get_track_count():
		var path := a.track_get_path(t)
		var bone := path.get_concatenated_subnames()
		var type := a.track_get_type(t)
		var upper := bone in UPPER_BONES
		var hips_turn := bone == "Hips" and type == Animation.TYPE_ROTATION_3D
		if not (upper or hips_turn) or type == Animation.TYPE_SCALE_3D:
			continue
		var src := walk.find_track(path, type)
		if src < 0:
			continue
		var v: Variant = walk.rotation_track_interpolate(src, 0.5) if type == Animation.TYPE_ROTATION_3D else walk.position_track_interpolate(src, 0.5)
		if type == Animation.TYPE_POSITION_3D and not upper:
			continue
		for k in range(a.track_get_key_count(t) - 1, -1, -1):
			a.track_remove_key(t, k)
		a.track_insert_key(t, 0.0, v)
	var lib := AnimationLibrary.new()
	lib.add_animation("aim", a)
	var aw := _aim_walk(ap)
	if aw:
		lib.add_animation("aim_walk", aw)
	ap.add_animation_library("stance", lib)

## Walking with the gun up: the walk clip's legs and hip sway, with the
## upper body held in the aim from shoot_walk. Spine02 (the first bone above
## the hips) is counter-rotated against the hip sway each key, so the torso
## and the gun stay pointed where she aims instead of swinging with her hips.
static func _aim_walk(ap: AnimationPlayer) -> Animation:
	if not ap.has_animation("walk") or not ap.has_animation("shoot_walk"):
		return null
	var walk := ap.get_animation("walk")
	var sw := ap.get_animation("shoot_walk")
	var a: Animation = walk.duplicate(true)
	var hips_t := -1
	for t in a.get_track_count():
		if a.track_get_path(t).get_concatenated_subnames() == "Hips" and a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			hips_t = t
	if hips_t < 0:
		return null
	var sw_hips_t := sw.find_track(a.track_get_path(hips_t), Animation.TYPE_ROTATION_3D)
	var sw_hips: Quaternion = sw.rotation_track_interpolate(sw_hips_t, 0.5) if sw_hips_t >= 0 else Quaternion.IDENTITY
	for t in a.get_track_count():
		var path := a.track_get_path(t)
		var bone := path.get_concatenated_subnames()
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D or not (bone in UPPER_BONES):
			continue
		var src := sw.find_track(path, Animation.TYPE_ROTATION_3D)
		if src < 0:
			continue
		var v: Quaternion = sw.rotation_track_interpolate(src, 0.5)
		for k in range(a.track_get_key_count(t) - 1, -1, -1):
			a.track_remove_key(t, k)
		if bone == "Spine02":
			for k in walk.track_get_key_count(hips_t):
				var tk := walk.track_get_key_time(hips_t, k)
				var wh: Quaternion = walk.rotation_track_interpolate(hips_t, tk)
				a.track_insert_key(t, tk, (wh.inverse() * sw_hips * v).normalized())
		else:
			a.track_insert_key(t, 0.0, v)
	return a

## Taking a hit: a sharp jolt of the whole body. Moving cuts it short once
## the blow has landed (the player's feet are held for that moment), so the
## legs never freeze while the body is pushed around.
func flinch(heavy := false) -> void:
	if _anim == null or not _anim.has_animation("hit"):
		return
	if _held != "" or _current in ["knockdown", "stand_up"]:
		return
	play_once("hit", 0.04, 1.35 if heavy else 1.75)
	_cancel_at = 0.75 if heavy else 0.55

## Plays a non-looping clip (hit, reload, call, shout, knockdown, stand_up),
## then returns to the movement loop.
func play_once(clip: String, blend := 0.15, speed := 1.0) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.speed_scale = 1.0
		_anim.play(clip, blend, speed)
		_current = clip
		_one_shot = true
		_cancel_at = -1.0

## Knife slashes, the hatchet chop and grenade throws (the "combat" library,
## retargeted onto this skeleton on first use). After cancel_after seconds
## of clip time, moving cuts the recovery short.
func play_combat(clip: String, speed := 1.0, cancel_after := -1.0) -> void:
	if _anim == null:
		return
	play_once("combat/" + clip, 0.08, speed)
	_cancel_at = cancel_after

## Cutscenes: jump to the last frame of a clip and hold it (lying in the road
## after the crash, before standing up).
func hold_end(clip: String) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.speed_scale = 1.0
		_anim.play(clip, 0.0)
		_anim.seek(_anim.get_animation(clip).length, true)
		_current = clip
		_one_shot = true

# ---------- Body shaping and secondary motion ----------

var _body_mat: ShaderMaterial
var _regions: Array = []      # runtime state per region
var _body_mesh: MeshInstance3D

func _setup_body(m: Node3D, lib: AnimationLibrary = null) -> void:
	_body_mesh = m.find_children("*", "MeshInstance3D", true, false)[0]
	_body_mat = _skin_material(_body_mesh)
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

## The scanned PBR textures of a model mesh on the body shader.
func _skin_material(mi: MeshInstance3D) -> ShaderMaterial:
	var std := mi.get_active_material(0) as StandardMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/character_body.gdshader")
	if std:
		mat.set_shader_parameter("albedo_tex", std.albedo_texture)
		mat.set_shader_parameter("has_normal", std.normal_enabled and std.normal_texture != null)
		mat.set_shader_parameter("normal_tex", std.normal_texture)
		mat.set_shader_parameter("normal_scale", std.normal_scale)
		mat.set_shader_parameter("orm_tex", std.roughness_texture if std.roughness_texture else std.metallic_texture)
		var chans := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
		mat.set_shader_parameter("rough_ch", chans[std.roughness_texture_channel] if std.roughness_texture else Vector4.ZERO)
		mat.set_shader_parameter("metal_ch", chans[std.metallic_texture_channel] if std.metallic_texture else Vector4.ZERO)
		mat.set_shader_parameter("roughness", std.roughness)
		mat.set_shader_parameter("metallic", std.metallic)
	return mat

## Puts the character's shared head (the same face on every outfit, see
## tools/outfits/shared_head.py) on the outfit's skeleton. Its skin binds by
## bone name, so it sits on this outfit's own neck and follows its pose.
func _attach_head() -> void:
	var path: String = SHARED_HEAD.get(character, "")
	if path == "" or not ResourceLoader.exists(path) or _skel == null:
		return
	var scene: Node = load(path).instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		scene.free()
		return
	var mi: MeshInstance3D = found[0]
	var local := mi.transform
	mi.get_parent().remove_child(mi)
	scene.free()
	mi.owner = null
	mi.name = "SharedHead"
	_skel.add_child(mi)
	mi.transform = local
	mi.skeleton = NodePath("..")
	mi.material_override = _skin_material(mi)

func _process(delta: float) -> void:
	if hand_rig:
		hand_rig.update(delta)
	if _body_mat and delta > 0.0:
		_update_regions(minf(delta, 0.05))
	if _skel and _model and not is_equal_approx(_slider("legs"), 0.0):
		_update_lift()

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
