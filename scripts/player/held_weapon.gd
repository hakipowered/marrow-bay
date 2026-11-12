class_name HeldWeapon
extends Node3D
## The equipped weapon, in the survivor's right hand.
##
## Follows the RightHand bone every frame (top level, so arm slider scale never
## squashes the gun). How the gun sits in the hand is worked out from the
## clips themselves: the gun points straight ahead in the "aim" pose, and the
## knife points ahead and a little up in the "combat/guard" stance. That works
## for both survivors and every outfit skeleton without hand-tuned offsets.
##
## Weapon space (what build_model returns): grip at the origin, barrel or
## blade along -Z, top of the weapon +Y.

## src "meshy": res://assets/weapons/<id>/<id>.glb, made with Meshy from our
##   own concept art. Muzzle or tip at -X; grip in model units (x, y).
##   len = real length in metres.
## src "ph": a CC0 Poly Haven model in metres with the muzzle at +X, or
##   "up": true for a model standing along +Y (hatchet, stick grenade).
## hold: gun (aligned with the aim pose), blade (aligned with the guard
##   stance), palm (grenade resting in the hand).
## align: [clip, time, pitch, yaw] points the weapon straight ahead (turned
##   by pitch and yaw) at that moment of that clip, instead of the hold's
##   default. The knife stands tip-up so it shows from behind.
const MODELS := {
	"knife": {"len": 0.34, "grip": Vector2(0.5, 0.0), "hold": "blade", "align": ["combat/guard", 0.3, 0.9, -0.4], "fist": Vector3(0, -0.003, -0.01), "edge": Vector3.DOWN},
	"hatchet": {"ph": "hatchet", "up": true, "len": 0.4, "grip": Vector2(0.0, -0.03), "hold": "blade", "align": ["combat/chop", 1.0, -0.5], "fist": Vector3(0, 0.002, -0.005), "edge": Vector3.UP},
	"p9": {"ph": "service_pistol", "grip": Vector2(-0.005, -0.01), "hold": "gun", "show": ["pistol_a", "slide_a", "hammer_a", "trigger_a"], "fist": Vector3(0, -0.005, 0.0045), "rake": 17.0},
	"vk18": {"len": 0.26, "grip": Vector2(0.70, -0.25), "hold": "gun", "fist": Vector3(0, 0.03, -0.011), "rake": 17.0},
	"bastion": {"len": 0.38, "grip": Vector2(0.72, -0.30), "hold": "gun", "fist": Vector3(0, 0.037, 0.0), "rake": 30.0},
	"hornet": {"len": 0.62, "grip": Vector2(0.17, -0.08), "hold": "gun", "fist": Vector3(0, 0.013, 0.0085), "rake": 17.0},
	"m12": {"len": 0.98, "grip": Vector2(0.36, 0.0), "hold": "gun", "fist": Vector3(0, 0.028, 0.028), "rake": 50.0},
	"breacher": {"len": 0.95, "grip": Vector2(0.39, -0.18), "hold": "gun", "fist": Vector3(0, 0.002, -0.009), "rake": 25.0},
	"longshot": {"ph": "bolt_action_rifle_7_62", "grip": Vector2(-0.32, -0.03), "hold": "gun", "hide": ["bolt_b", "bullet"], "fist": Vector3(0, 0.026, 0.009), "rake": 50.0},
	"carbine": {"len": 0.80, "grip": Vector2(0.33, -0.15), "hold": "gun", "fist": Vector3(0, -0.004, 0.008), "rake": 25.0},
	"bolt": {"len": 0.85, "grip": Vector2(0.29, -0.18), "hold": "gun", "fist": Vector3(0, -0.011, 0.003), "rake": 24.0},
	"gl": {"len": 0.72, "grip": Vector2(0.2, -0.02), "hold": "gun", "fist": Vector3(0, 0.027, 0.003), "rake": 50.0},
	"flamer": {"len": 0.95, "grip": Vector2(0.60, -0.03), "hold": "gun", "fist": Vector3(0, 0.013, -0.0056), "rake": 30.0},
	"rocket": {"len": 1.15, "grip": Vector2(-0.15, -0.15), "hold": "gun", "fist": Vector3(0, 0.024, 0.012), "rake": 13.0},
	"flash": {"len": 0.13, "up": true, "grip": Vector2(0.0, -0.1), "hold": "palm"},
	"frag": {"ph": "stick_grenade", "up": true, "grip": Vector2(0.0, -0.05), "hold": "palm", "fist": Vector3.ZERO, "edge": Vector3.UP},
}

## In the fist (survivors with finger joints, see HandRig): "fist" is the
## middle of the handle in weapon space (metres), where the middle of the
## closed hand goes. A gun's handle runs down and back by "rake" degrees
## from straight down; a blade's handle runs along the blade, its "edge"
## facing the front of the fist. Measured from slices through each model's
## handle, then checked in close-ups.

## Middle of the closed hand, from the wrist bone, in metres along the bone
## (Y runs to the fingertips on these rigs), for a body without finger
## joints. HandRig.grip_point finds it for each outfit's own hand.
const PALM := Vector3(0.0, 0.085, 0.015)

var model: CharacterModel
var weapon_id := ""
var hold := ""
var muzzle_local := Vector3.ZERO   # in weapon space

var _gun: Node3D
var _skel: Skeleton3D
var _hand := -1
var _align := {}      # hold -> Basis, hand frame to weapon frame
var _kick := 0.0
var _rot := Quaternion.IDENTITY   # hand-to-weapon turn now, eased between holds
var _grip := Basis.IDENTITY       # hand-to-weapon turn with the handle in the fist
var _hold := Basis.IDENTITY       # the same once the wrist has turned (a gun's leftover turn)
var _turned := {}                 # bone -> [turn we set, the clip's own turn]
var _snap := true                 # jump straight to the hold (new weapon or body)
var _long := false                # a long gun hangs lower than a pistol

## Clips where the weapon is up and working; anything else (standing, walking,
## running) carries it lowered at her side.
const RAISED_ANIMS := ["shoot_walk", "run_shoot", "reload"]

func _ready() -> void:
	top_level = true
	# After the AnimationPlayer has posed the skeleton this frame.
	process_priority = 100

func set_weapon(id: String) -> void:
	if id == weapon_id and _gun:
		return
	weapon_id = id
	if _gun:
		_gun.queue_free()
		_gun = null
	var def: Dictionary = MODELS.get(id, {})
	hold = def.get("hold", "")
	if def.is_empty():
		return
	_gun = build_model(id)
	if _gun == null:
		return
	muzzle_local = _gun.get_meta("muzzle", Vector3(0, 0, -0.2))
	var box: AABB = _gun.get_meta("aabb", AABB())
	_long = box.size.z > 0.55
	_snap = true
	add_child(_gun)

## Brief muzzle flash and recoil.
func fired(recoil: float) -> void:
	_kick = clampf(_kick + recoil, 0.0, 1.5)
	if hold == "gun" and weapon_id not in ["flamer", "bolt"] and is_inside_tree():
		# A photographed blast along the barrel, a star at the muzzle, a flash
		# of light and a wisp of smoke (Effects.muzzle_flash).
		Effects.muzzle_flash(muzzle_global(), -global_basis.z, weapon_id)

func muzzle_global() -> Vector3:
	return global_transform * muzzle_local

func hand_global() -> Vector3:
	return global_position

func _process(delta: float) -> void:
	_kick = maxf(_kick - delta * 7.0, 0.0)
	if model == null or not is_instance_valid(model):
		return
	# A new skeleton (first frame, or an outfit change rebuilt the body).
	# Bound here, never from the skeleton's own update signal: adding clip
	# libraries while the AnimationPlayer is mid-update crashes the engine.
	if model._skel != _skel:
		_bind(model._skel)
	_set_fingers()
	if _in_fist():
		_grip = _fist_basis(MODELS[weapon_id])
	if _skel and _hand >= 0 and _gun:
		var want := _target_align().get_rotation_quaternion()
		_rot = want if _snap else _rot.slerp(want, 1.0 - exp(-16.0 * clampf(delta, 0.0, 0.1)))
		_snap = false
	_turn_wrist()
	_follow()

## Whether the handle sits in a closed fist (a body with finger joints and
## a weapon whose handle we know).
func _in_fist() -> bool:
	return model.hand_rig != null and MODELS.get(weapon_id, {}).has("fist")

## Snaps the weapon to the hand. Also runs right after the skeleton poses
## itself each frame, so the gun never trails the hand by a frame.
func _follow() -> void:
	if model == null or not is_instance_valid(model) or model._skel != _skel:
		return
	if _skel == null or _hand < 0 or _gun == null:
		visible = false
		return
	if not _skel.is_inside_tree():
		return
	visible = model.is_visible_in_tree()
	var pose := _skel.get_bone_global_pose(_hand)
	var hb := (_skel.global_basis * pose.basis).orthonormalized()
	var at := _skel.global_transform * pose.origin
	var t: Transform3D
	var pivot := Vector3.ZERO
	if _in_fist():
		# The middle of the handle in the middle of the fist.
		var b := hb * _hold
		pivot = MODELS[weapon_id]["fist"]
		t = Transform3D(b, at + hb * model.hand_rig.grip_point("Right") - b * pivot)
	else:
		var grip := model.hand_rig.grip_point("Right") if model.hand_rig else PALM
		t = Transform3D(hb * Basis(_rot), at + hb * grip)
	if _kick > 0.0:
		# Recoil turns the weapon about the hand.
		var kick := Transform3D(Basis(Vector3.RIGHT, _kick * 0.22), Vector3(0, 0, _kick * 0.035))
		t = t * Transform3D(Basis.IDENTITY, pivot) * kick * Transform3D(Basis.IDENTITY, -pivot)
	global_transform = t

## How much of the wrist's turn along the hand the forearm takes.
const FOREARM_TWIST := 0.5
## The most the forearm and wrist turn along the hand (radians, together),
## and the most the wrist bends.
const TWIST_MAX := 1.05
const SWING_MAX := 0.5

## The clip-based hold (_rot) points the weapon where it should go: a gun
## straight ahead, a knife tip up where it shows. With the handle in the
## fist that takes a turn of the wrist, H * C * grip = H * rot, so the
## wrist turns to meet the handle: the twist along the hand is shared with
## the forearm so the wrist doesn't wring, and the hand bends the rest,
## each within what a real arm does. Whatever turn is left over, a gun takes
## in the hand (it stays aimed) and a blade or grenade doesn't (it stays
## in the fist). Only called from _process, after the clip has posed the
## skeleton this frame (never from the skeleton's update signal: changing
## bones there would update the skeleton again).
func _turn_wrist() -> void:
	if _skel == null or not is_instance_valid(_skel):
		return
	# Put back what the clip set if it hasn't posed these bones since.
	for b in _turned:
		if _skel.get_bone_pose_rotation(b).is_equal_approx(_turned[b][0]):
			_skel.set_bone_pose_rotation(b, _turned[b][1])
	_turned.clear()
	_hold = _grip
	var fa := _skel.get_bone_parent(_hand) if _hand >= 0 else -1
	if fa < 0 or _gun == null or not _in_fist():
		return
	var c := (Basis(_rot) * _grip.inverse()).get_rotation_quaternion()
	if c.w < 0.0:
		c = -c
	var twist := Quaternion(0.0, c.y, 0.0, c.w).normalized()
	var angle := clampf(wrapf(2.0 * atan2(twist.y, twist.w), -PI, PI), -TWIST_MAX, TWIST_MAX)
	var swing := c * twist.inverse()
	if swing.w < 0.0:
		swing = -swing
	var bend := swing.get_angle()
	if bend > SWING_MAX:
		swing = Quaternion(swing.get_axis(), SWING_MAX)
	var turn := swing * Quaternion(Vector3.UP, angle)
	if hold == "gun":
		_hold = Basis(turn.inverse() * c) * _grip
	var target := _skel.get_bone_global_pose(_hand).basis.get_rotation_quaternion() * turn
	var fa_clip := _skel.get_bone_pose_rotation(fa)
	var hand_clip := _skel.get_bone_pose_rotation(_hand)
	var fa_now := (fa_clip * Quaternion(Vector3.UP, angle * FOREARM_TWIST)).normalized()
	_skel.set_bone_pose_rotation(fa, fa_now)
	var parent := _skel.get_bone_global_pose(fa).basis.get_rotation_quaternion()
	var hand_now := (parent.inverse() * target).normalized()
	_skel.set_bone_pose_rotation(_hand, hand_now)
	_turned[fa] = [fa_now, fa_clip]
	_turned[_hand] = [hand_now, hand_clip]

## Hand-to-weapon turn that runs the handle through the fist (thumb side to
## little finger) with the barrel or the edge toward the front of the fist.
func _fist_basis(def: Dictionary) -> Basis:
	var thumb: float = model.hand_rig.hands["Right"].get("thumb", -1.0) if model.hand_rig else -1.0
	var e1 := Vector3(-thumb, 0, 0)   # toward the little finger
	var e2 := Vector3.UP              # out of the front of the fist
	var w1: Vector3
	var front: Vector3
	if def.has("rake"):
		var r := deg_to_rad(def["rake"])
		w1 = Vector3(0, -cos(r), sin(r))   # down the handle
		front = Vector3.FORWARD             # the barrel
	else:
		w1 = Vector3.BACK                  # from the blade to the butt
		front = def.get("edge", Vector3.UP)
	var w2 := (front - w1 * front.dot(w1)).normalized()
	return Basis(e1, e2, e1.cross(e2)) * Basis(w1, w2, w1.cross(w2)).transposed()

## Closes the right hand around what it holds (a fist on a grip or a
## handle, a cupped palm under a grenade) and brings the left hand onto the
## gun while it's raised.
func _set_fingers() -> void:
	var rig: HandRig = model.hand_rig
	if rig == null:
		return
	var holding := _gun != null and hold != ""
	var cup: bool = hold == "palm" and not MODELS.get(weapon_id, {}).has("fist")
	rig.pose["Right"] = ("cup" if cup else "fist") if holding else "relaxed"
	rig.pose["Left"] = "support" if holding and hold == "gun" and _raised() else "relaxed"

## Whether the weapon is up and working: aimed, guarding or swinging.
func _raised() -> bool:
	if model._anim == null:
		return true
	var cur := String(model._anim.current_animation)
	return cur.begins_with("combat/") or cur.begins_with("stance/") or cur in RAISED_ANIMS

## The hold for what the body is doing: aimed or guarding (the solved pose
## for this weapon), else lowered at her side.
func _target_align() -> Basis:
	var raised := _raised()
	if not raised:
		var low: String = ("long_low" if _long else "gun_low") if hold == "gun" else hold + "_low"
		if _align.has(low):
			return _align[low]
	return _align.get(weapon_id, _align.get(hold, Basis.IDENTITY))

func _bind(sk: Skeleton3D) -> void:
	if is_instance_valid(_skel) and _skel.skeleton_updated.is_connected(_follow):
		_skel.skeleton_updated.disconnect(_follow)
	_skel = sk
	_turned.clear()
	if sk:
		sk.skeleton_updated.connect(_follow, CONNECT_DEFERRED)
	_hand = sk.find_bone("RightHand") if sk else -1
	_align.clear()
	if _hand < 0:
		return
	# Forward and up of the body, seen from the skeleton.
	var root: Node3D = model._anim.get_node(model._anim.root_node)
	var to_root := (root.global_transform.affine_inverse() * sk.global_transform).basis.orthonormalized()
	# Meshy bodies face +Z inside their own root; the weapon's -Z must point there.
	var ahead := Basis(Vector3.UP, PI)
	_align["gun"] = _solve("stance/aim", 0.5, ahead, to_root)
	_align["blade"] = _solve("combat/guard", 0.3, ahead * Basis(Vector3.RIGHT, 0.35), to_root)
	_align["palm"] = _solve("combat/guard", 0.3, ahead * Basis(Vector3.RIGHT, -0.6), to_root)
	# Lowered at her side while standing, walking or running: the muzzle ahead
	# and down (a long gun steeper, so its stock clears the hip), the knife tip
	# down. Pointing along the leg, as the aim hold does, hides them.
	_align["gun_low"] = _solve("idle", 0.5, ahead * Basis(Vector3.RIGHT, LOW_PITCH[0]), to_root)
	_align["long_low"] = _solve("idle", 0.5, ahead * Basis(Vector3.RIGHT, LOW_PITCH[1]), to_root)
	_align["blade_low"] = _solve("idle", 0.5, ahead * Basis(Vector3.RIGHT, LOW_PITCH[2]), to_root)
	_snap = true
	# Weapons that sit better lined up with their own swing.
	for id in MODELS:
		if MODELS[id].has("align"):
			var al: Array = MODELS[id]["align"]
			var yaw: float = al[3] if al.size() > 3 else 0.0
			_align[id] = _solve(al[0], al[1], ahead * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, al[2]), to_root)

## Pitch of the lowered holds (radians below level): pistol, long gun, blade.
const LOW_PITCH := [-0.75, -1.2, -1.0]

## Hand-to-weapon rotation that makes the weapon face `want` (in the model
## root's space) when the clip is at time t.
func _solve(clip: String, t: float, want: Basis, to_root: Basis) -> Basis:
	if not model._anim.has_animation(clip):
		return Basis.IDENTITY
	var hand := to_root * _pose_in_clip(model._anim.get_animation(clip), t)
	return (hand.inverse() * want).orthonormalized()

## The hand bone's rotation in skeleton space at time t of a clip, from its
## tracks (bones without a track keep their rest).
func _pose_in_clip(a: Animation, t: float) -> Basis:
	var prefix := ""
	for i in a.get_track_count():
		var p := a.track_get_path(i)
		if p.get_subname_count() > 0:
			prefix = str(p).split(":")[0]
			break
	var chain: Array[int] = []
	var b := _hand
	while b >= 0:
		chain.push_front(b)
		b = _skel.get_bone_parent(b)
	var g := Basis.IDENTITY
	for bone in chain:
		var q := _skel.get_bone_rest(bone).basis.get_rotation_quaternion()
		var tr := a.find_track(NodePath("%s:%s" % [prefix, _skel.get_bone_name(bone)]), Animation.TYPE_ROTATION_3D)
		if tr >= 0:
			q = a.rotation_track_interpolate(tr, t)
		g = g * Basis(q)
	return g.orthonormalized()

# ---------- Models ----------


## A weapon model in weapon space (grip at the origin, pointing -Z), with
## metadata "muzzle" (Vector3) and "aabb" (AABB). Null when there is none.
static func build_model(id: String) -> Node3D:
	var def: Dictionary = MODELS.get(id, {})
	if def.is_empty():
		return null
	var path := ""
	if def.has("ph"):
		path = "res://assets/polyhaven/models/%s/%s.gltf" % [def["ph"], def["ph"]]
	else:
		path = "res://assets/weapons/%s/%s.glb" % [id, id]
	if not ResourceLoader.exists(path):
		return null
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if def.has("show") and not def["show"].any(func(s): return n.ends_with(s)):
			mi.queue_free()
			mi.get_parent().remove_child(mi)
			continue
		if def.has("hide") and def["hide"].any(func(s): return n.ends_with(s) or n.contains("_" + s)):
			mi.queue_free()
			mi.get_parent().remove_child(mi)
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var box := _aabb(scene, Transform3D.IDENTITY)
	var up: bool = def.get("up", false)
	var s := 1.0
	if def.has("len"):
		s = def["len"] / maxf(box.size.y if up else box.size.x, 0.001)
	# Long axis to -Z: Meshy tips sit at -X, Poly Haven muzzles at +X,
	# standing models point +Y.
	var rot: Basis
	if up:
		rot = Basis(Vector3.RIGHT, -PI / 2.0)
	elif def.has("ph"):
		rot = Basis(Vector3.UP, PI / 2.0)
	else:
		rot = Basis(Vector3.UP, -PI / 2.0)
	var g: Vector2 = def["grip"]
	var grip := Vector3(g.x, g.y, 0.0) * s
	var holder := Node3D.new()
	holder.name = "Weapon_" + id
	scene.transform = Transform3D(rot * Basis.from_scale(Vector3.ONE * s), -(rot * grip))
	holder.add_child(scene)
	var wbox := scene.transform * box
	holder.set_meta("aabb", wbox)
	holder.set_meta("muzzle", Vector3(wbox.get_center().x, wbox.end.y - wbox.size.y * 0.3, wbox.position.z))
	return holder

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and n.mesh:
		out = here * n.mesh.get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D and not c.is_queued_for_deletion():
			var b := _aabb(c, here)
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out
