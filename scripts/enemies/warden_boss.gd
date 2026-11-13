class_name WardenBoss
extends CharacterBody3D
## Chapter 2's boss, "The Last Warden": Warden Jackson Hardass, bitten in the
## Archive, turned on the way down, still in his shelter riot gear with the
## generator's starting handle on his belt. He fights in the muster room.
##
## Phase one: he walks them down behind a riot shield that stops everything
## from the front but the legs, with a steel truncheon (swing, slash, a
## three-hit combo, a shield shove) and a charge across the room that leaves
## him dazed if it ends in a wall. Half his health gone, he roars, tears the
## shield off and runs: faster combos, an overhead slam, a ground slam that
## knocks both of them back, a stomp.
##
## The way to hurt him is the bite on his back, swollen into a glowing
## growth: hits there count triple, and enough of them drop him to his knees,
## holding his head, for a few seconds of free damage. In co-op one survivor
## draws him while the other gets behind him.
##
## Duck-types the infected for everything else in the game (group "zombies",
## state, data, variant, take_hit, hear_noise, flashed): bullets, blades,
## blasts and fire hurt him; the HorrorDirector plays the boss music. The
## host runs him; every phone sees the same moves (RPC) and where he is
## (MultiplayerSynchronizer).

signal died

const HP := 1500.0
const SHIELD_HP := 260.0
## Damage to the growth on his back that drops him to his knees.
const WOUND_KNEEL := 170.0
const ZONE_MULT := {"head": 2.0, "torso": 1.0, "arm": 0.6, "leg": 0.8, "wound": 3.0}
const WALK := 1.5
const RUN := 3.1
const CHARGE_SPEED := 7.0

## Each move: clip, hits [seconds into the clip, damage, reach in metres,
## cone (dot of his facing; -1 is all round)], and extras. Strike times come
## from the clips themselves (the hand's fastest moment).
const MOVES := {
	"swing": {"hits": [[1.11, 30.0, 2.7, 0.3]]},
	"slash": {"hits": [[0.87, 22.0, 2.5, 0.3]]},
	"combo": {"hits": [[0.8, 15.0, 2.4, 0.3], [1.57, 15.0, 2.4, 0.3], [2.27, 18.0, 2.5, 0.3]]},
	"combo2": {"hits": [[0.67, 18.0, 2.4, 0.3], [1.23, 20.0, 2.5, 0.3]]},
	"shield_push": {"hits": [[1.13, 16.0, 2.1, 0.4]]},
	"slam": {"hits": [[1.5, 32.0, 3.0, 0.2]], "quake": 1.0},
	"ground_slam": {"hits": [[1.67, 26.0, 4.0, -1.0]], "quake": 1.6},
	"stomp": {"hits": [[0.7, 16.0, 2.9, -1.0]], "quake": 0.7},
	"roar": {"hits": [[1.17, 0.0, 4.5, -1.0]], "len": 4.2},
}
## The kneel clip goes down and straight back up: he stays at its lowest
## point, heaving, until he's had enough.
const KNEEL_AT := 0.5
## No second blow on the same survivor for this long (milliseconds).
const HIT_GRACE_MS := 1100
## The overhead swing takes both hands, so it waits for the shield to go.
const PHASE1 := [["slash", 3.0], ["combo", 2.5], ["shield_push", 1.5]]
const PHASE2 := [["combo2", 3.0], ["combo", 2.0], ["swing", 1.5], ["slam", 2.0], ["ground_slam", 1.5], ["stomp", 1.0]]

var variant := "warden"
var data := {"boss": true, "bulk": 1.5, "charge": true, "hp": HP, "reach": 2.4, "drop": "none", "dmg": 30}
@export var state: Zombie.S = Zombie.S.IDLE
@export var phase := 1
var crippled := false
var head_gone := false
var hp := HP
var max_hp := HP
## Set when the fight starts (the story's scene ends); until then he stands.
var awake := false
var target: Node3D
var actor: StoryActor
var agent: NavigationAgent3D
var _hitboxes: Array = []
var _shield_hp := SHIELD_HP
var _wound := 0.0
var _act := ""
var _act_t := 0.0
var _act_len := 0.0
var _act_speed := 1.0
var _hits: Array = []
var _cd := 1.0
var _charge_cd := 8.0
var _charge_dir := Vector3.ZERO
var _poise := 0.0
var _kneel_t := 0.0
var _rng := RandomNumberGenerator.new()
var _shield: Node3D
var _crack_mat: StandardMaterial3D
var _growth_mat: StandardMaterial3D
var _growth_t := 0.0
var _groan_t := 4.0
var _hit_struck := {}
var _k := 1.0

func _ready() -> void:
	add_to_group("zombies")
	add_to_group("boss")
	_rng.seed = 1891
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.95
	shape.shape = cap
	shape.position.y = cap.height / 2
	add_child(shape)
	actor = StoryActor.new("hardass_boss")
	actor.name = "Body"
	add_child(actor)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.2
	agent.radius = 0.5
	add_child(agent)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":state", ":phase"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)
	_dress.call_deferred()

## The turned look, the truncheon, the shield, the growth and the hitboxes,
## once the model has its skeleton.
func _dress() -> void:
	var sk := actor._skel
	if sk == null:
		return
	var n: Node = sk
	while n != null and n != actor:
		if n is Node3D:
			_k *= (n as Node3D).scale.x
		n = n.get_parent()
	for mi in actor.find_children("*", "MeshInstance3D", true, false):
		_infect(mi)
	_baton(sk)
	_strap_shield(sk)
	_growth(sk)
	for z in [["head", "Head", Vector3(0, 0.1, 0), Vector3(0.3, 0.32, 0.3)],
			["torso", "Spine01", Vector3(0, 0.14, 0), Vector3(0.56, 0.62, 0.36)],
			["arm", "LeftForeArm", Vector3(0, 0.13, 0), Vector3(0.15, 0.32, 0.15)],
			["arm", "RightForeArm", Vector3(0, 0.13, 0), Vector3(0.15, 0.32, 0.15)],
			["leg", "LeftUpLeg", Vector3(0, 0.22, 0), Vector3(0.22, 0.48, 0.22)],
			["leg", "RightUpLeg", Vector3(0, 0.22, 0), Vector3(0.22, 0.48, 0.22)],
			["leg", "LeftLeg", Vector3(0, 0.22, 0), Vector3(0.17, 0.46, 0.17)],
			["leg", "RightLeg", Vector3(0, 0.22, 0), Vector3(0.17, 0.46, 0.17)]]:
		_zone(sk, z[0], z[1], z[2], z[3])
	# The growth: on the upper back, sticking out behind the torso box.
	_zone(sk, "wound", "Spine02", _back_offset(sk, "Spine02", 0.2, 0.06), Vector3(0.34, 0.32, 0.16))

## A node riding a bone, in metres (Meshy armatures are scaled 0.01).
func _on_bone(sk: Skeleton3D, bone: String) -> Node3D:
	var att: BoneAttachment3D = sk.get_node_or_null("Att_" + bone)
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "Att_" + bone
		att.bone_name = bone
		sk.add_child(att)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / _k
	att.add_child(holder)
	return holder

## A point `back` metres behind the bone (toward his back) and `up` along it,
## in the bone's own frame, from the rest pose.
func _back_offset(sk: Skeleton3D, bone: String, back: float, up: float) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	var gb := (sk.global_basis * sk.get_bone_global_rest(i).basis).orthonormalized()
	var world_back := global_basis.z.normalized()   # he faces -Z
	return gb.inverse() * world_back * back + Vector3(0, up, 0)

func _zone(sk: Skeleton3D, zone: String, bone: String, offset: Vector3, size: Vector3) -> void:
	if sk.find_bone(bone) < 0:
		push_warning("WardenBoss: no bone " + bone)
		return
	var h := _on_bone(sk, bone)
	h.position = offset / _k
	var a := Area3D.new()
	a.collision_layer = 8
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("hit_zone", zone)
	a.set_meta("enemy", self)
	a.set_meta("owner_path", str(name))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	a.add_child(cs)
	h.add_child(a)
	_hitboxes.append(a)

## Turned: grey skin, black veins, blood down the uniform.
func _infect(mi: MeshInstance3D) -> void:
	var std := mi.get_active_material(0) as StandardMaterial3D
	mi.mesh = ZombieModel._with_rest_colors(mi.mesh)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/infected_body.gdshader")
	if std:
		m.set_shader_parameter("albedo_tex", std.albedo_texture)
		m.set_shader_parameter("has_normal", std.normal_enabled and std.normal_texture != null)
		m.set_shader_parameter("normal_tex", std.normal_texture)
		m.set_shader_parameter("normal_scale", std.normal_scale)
		m.set_shader_parameter("orm_tex", std.roughness_texture if std.roughness_texture else std.metallic_texture)
		var chans := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
		m.set_shader_parameter("rough_ch", chans[std.roughness_texture_channel] if std.roughness_texture else Vector4.ZERO)
		m.set_shader_parameter("metal_ch", chans[std.metallic_texture_channel] if std.metallic_texture else Vector4.ZERO)
		m.set_shader_parameter("roughness", std.roughness)
		m.set_shader_parameter("metallic", std.metallic)
	m.set_shader_parameter("seed", 0.37)
	m.set_shader_parameter("pallor", 0.85)
	m.set_shader_parameter("veins", 1.0)
	m.set_shader_parameter("blood", 1.0)
	m.set_shader_parameter("bite", 1.0)
	m.set_shader_parameter("grime", 0.5)
	m.set_shader_parameter("flesh", Color(0.58, 0.56, 0.52))
	mi.material_override = m

## A steel truncheon in his right fist.
func _baton(sk: Skeleton3D) -> void:
	if sk.find_bone("RightHand") < 0:
		return
	var h := _on_bone(sk, "RightHand")
	h.position = BATON_AT / _k
	h.rotation_degrees = BATON_ROT
	var steel := Mats.trim(Color(0.06, 0.06, 0.065), 0.35, 0.8)
	var grip := Mats.trim(Color(0.03, 0.03, 0.03), 0.85, 0.0)
	UndercroftKit.bar(h, Vector3(0, 0.28, 0), 0.024, 0.62, steel)
	UndercroftKit.bar(h, Vector3(0, -0.02, 0), 0.027, 0.2, grip)
	UndercroftKit.bar(h, Vector3(0, -0.13, 0), 0.032, 0.025, steel)
	UndercroftKit.bar(h, Vector3(0, 0.6, 0), 0.028, 0.03, steel)
## In the fist: the hand bone's Y runs to the fingers, its X out of the back
## of the hand, its Z along the knuckles to the thumb, which is the way the
## truncheon points.
const BATON_AT := Vector3(-0.03, 0.08, 0.0)
const BATON_ROT := Vector3(90, 0, 0)

## The shelter's riot shield on his left forearm, "WARDEN" across it.
func _strap_shield(sk: Skeleton3D) -> void:
	if sk.find_bone("LeftForeArm") < 0:
		return
	var h := _on_bone(sk, "LeftForeArm")
	# Strapped across the forearm: upright and facing the way he faces in
	# his guard (the idle clip), worked out in the bone's own frame so it
	# then follows the arm through every move.
	var fore := sk.find_bone("LeftForeArm")
	var hand := sk.find_bone("LeftHand")
	if actor._anim and actor._anim.has_animation("idle"):
		actor._anim.play("idle", 0.0)
		actor._anim.seek(SHIELD_POSE_T, true)
	var bw := sk.global_transform * sk.get_bone_global_pose(fore)
	var hw := sk.global_transform * sk.get_bone_global_pose(hand)
	var fwd := -global_basis.z.normalized()
	var up := global_basis.y.normalized()
	var want := Basis(up.cross(fwd), up, fwd)
	h.quaternion = (bw.basis.orthonormalized().inverse() * want).get_rotation_quaternion()
	var mid := bw.origin.lerp(hw.origin, 0.55) + fwd * SHIELD_OUT - up * SHIELD_DROP
	h.position = bw.affine_inverse() * mid
	_shield = h
	var clear := StandardMaterial3D.new()
	clear.albedo_color = Color(0.5, 0.56, 0.6, 0.35)
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.roughness = 0.12
	clear.metallic_specular = 0.8
	clear.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pane := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.62, 1.05, 0.014)
	pane.mesh = pm
	pane.material_override = clear
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(pane)
	var rim := Mats.trim(Color(0.05, 0.05, 0.05), 0.7, 0.2)
	for y in [-0.52, 0.52]:
		RoomBuilder._box(h, Vector3(0, y, 0), Vector3(0.64, 0.025, 0.03), rim, false)
	for x in [-0.31, 0.31]:
		RoomBuilder._box(h, Vector3(x, 0, 0), Vector3(0.025, 1.06, 0.03), rim, false)
	var l := UndercroftKit.label(h, "WARDEN", Vector3(0, 0.3, 0.012), 64, Color(0.92, 0.92, 0.9), 0.0, 0.0018)
	l.double_sided = true
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_texture = ZombieModel._crack_texture()
	_crack_mat.albedo_color = Color(0.92, 0.95, 0.97, 0.0)
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cracks := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 1.0)
	cracks.mesh = q
	cracks.material_override = _crack_mat
	cracks.position.z = 0.009
	h.add_child(cracks)
const SHIELD_POSE_T := 0.5
const SHIELD_OUT := 0.12
const SHIELD_DROP := 0.12

## The bite between his shoulder blades, swollen into a pulsing growth.
func _growth(sk: Skeleton3D) -> void:
	if sk.find_bone("Spine02") < 0:
		return
	var h := _on_bone(sk, "Spine02")
	h.position = _back_offset(sk, "Spine02", 0.15, 0.05) / _k
	_growth_mat = StandardMaterial3D.new()
	_growth_mat.albedo_color = Color(0.35, 0.05, 0.04)
	_growth_mat.roughness = 0.25
	_growth_mat.emission_enabled = true
	_growth_mat.emission = Color(1.0, 0.32, 0.08)
	_growth_mat.emission_energy_multiplier = 1.0
	var back := _back_offset(sk, "Spine02", 1.0, 0.0).normalized()
	var r := RandomNumberGenerator.new()
	r.seed = 44
	for i in 9:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rad := r.randf_range(0.035, 0.075)
		sm.radius = rad
		sm.height = rad * 1.6
		sm.radial_segments = 12
		sm.rings = 6
		s.mesh = sm
		s.material_override = _growth_mat
		s.position = Vector3(r.randf_range(-0.09, 0.09), r.randf_range(-0.08, 0.1), r.randf_range(-0.09, 0.09)) + back * r.randf_range(0.0, 0.04)
		h.add_child(s)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.35, 0.1)
	glow.omni_range = 1.2
	glow.light_energy = 0.5
	glow.position = back * 0.15
	h.add_child(glow)

# ------------------------------------------------------------------ thinking (host)

func _physics_process(delta: float) -> void:
	_tick_look(delta)
	if not multiplayer.is_server() or state == Zombie.S.DEAD:
		return
	if not awake:
		velocity = Vector3.ZERO
		return
	_cd = maxf(_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_poise = maxf(_poise - delta, 0.0)
	_groan_t -= delta
	if _groan_t <= 0.0:
		_groan_t = _rng.randf_range(4.0, 8.0)
		_rpc_voice.rpc("warden_growl")
	if _act != "":
		_tick_act(delta)
		return
	target = _pick_target()
	if target == null:
		state = Zombie.S.IDLE
		_play("idle")
		velocity = Vector3.ZERO
		return
	state = Zombie.S.CHASE
	if phase == 1 and hp <= max_hp * 0.5:
		_phase_two()
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	_turn_to(to, delta, 3.0 if phase == 1 else 4.5)
	var facing := (-global_basis.z).dot(to.normalized()) > 0.8
	if d > 7.0 and _charge_cd <= 0.0 and facing and _clear(target):
		_start_charge(to.normalized())
		return
	if d < 2.5 and _cd <= 0.0 and facing:
		_start(_choose(d))
		return
	agent.target_position = target.global_position
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05 or d < 1.8:
		dir = to
	var sp := WALK if phase == 1 else RUN
	velocity = dir.normalized() * sp if d > 1.8 else Vector3.ZERO
	velocity.y = -4.0
	move_and_slide()
	_play(("advance" if phase == 1 else "run") if d > 1.8 else "idle", sp / (1.5 if phase == 1 else 3.6))

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed or p.get("dead"):
			continue
		var d := global_position.distance_to(p.global_position)
		# Stay on whoever he's after unless the other is much closer.
		if p == target:
			d -= 2.5
		if d < best_d:
			best_d = d
			best = p
	return best

func _turn_to(to: Vector3, delta: float, rate: float) -> void:
	if to.length() < 0.05:
		return
	var want := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, want, rate * delta)

func _clear(to: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, to.global_position + Vector3.UP * 1.0, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _choose(d: float) -> String:
	var pool: Array = PHASE1 if phase == 1 else PHASE2
	var total := 0.0
	for m in pool:
		if m[0] == "shield_push" and (d > 1.8 or _shield_hp <= 0.0):
			continue
		total += m[1]
	var r := _rng.randf() * total
	for m in pool:
		if m[0] == "shield_push" and (d > 1.8 or _shield_hp <= 0.0):
			continue
		r -= m[1]
		if r <= 0.0:
			return m[0]
	return pool[0][0]

## Starts a move: every phone plays the clip; the host times its hits.
func _start(move: String, speed := 0.0) -> void:
	_act = move
	_act_t = 0.0
	_act_speed = speed if speed > 0.0 else (1.0 if phase == 1 else 1.15)
	_act_len = minf(_clip_len(move), MOVES.get(move, {}).get("len", INF))
	_hits = (MOVES.get(move, {}).get("hits", []) as Array).duplicate()
	_hit_struck.clear()
	state = Zombie.S.ATTACK
	velocity = Vector3.ZERO
	_rpc_act.rpc(move, _act_speed)

func _clip_len(clip: String) -> float:
	if actor and actor._anim and actor._anim.has_animation(clip):
		return actor._anim.get_animation(clip).length
	return 2.0

func _tick_act(delta: float) -> void:
	_act_t += delta * _act_speed
	match _act:
		"charge":
			_tick_charge(delta)
			return
		"kneel":
			state = Zombie.S.STAGGER
			_kneel_t -= delta
			if _kneel_t <= 0.0:
				_act = "rise"
				_act_t = 0.0
				_act_speed = 1.2
				_act_len = maxf(_clip_len("kneel") - KNEEL_AT, 0.5)
				_rpc_act.rpc("rise", 1.2)
			return
	# Wind-up: still turning to follow them until just before the blow.
	if target and is_instance_valid(target) and not _hits.is_empty() and _act_t < float(_hits[0][0]) - 0.3:
		var to := target.global_position - global_position
		to.y = 0.0
		_turn_to(to, delta, 2.2)
	while not _hits.is_empty() and _act_t >= float(_hits[0][0]):
		_land(_hits.pop_front())
	if _act_t >= _act_len:
		_act = ""
		state = Zombie.S.CHASE
		_cd = _rng.randf_range(0.6, 1.4) if phase == 1 else _rng.randf_range(0.2, 0.8)
		if phase == 2 and _shield_hp > 0.0:
			_shield_hp = 0.0
			_rpc_shield_break.rpc()

## A blow lands: everyone in reach and in front of him (or all round) gets
## hit, unless they rolled through it or there's a wall in between.
func _land(hit: Array) -> void:
	var dmg: float = hit[1]
	var reach: float = hit[2]
	var cone: float = hit[3]
	var quake: float = MOVES.get(_act, {}).get("quake", 0.0)
	_rpc_blow.rpc(_act, quake)
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed:
			continue
		var to: Vector3 = p.global_position - global_position
		to.y = 0.0
		if to.length() > reach:
			continue
		if cone > -1.0 and to.length() > 0.6 and (-global_basis.z).dot(to.normalized()) < cone:
			continue
		if not _clear(p) or p.get("dodging"):
			continue
		if dmg > 0.0:
			# The infected's grace (Zombie.GRACE_MS), shorter: a combo lands
			# two of its three blows on someone who stands there, but a
			# survivor with her back to the lockers isn't hit-locked.
			if Time.get_ticks_msec() - int(p.get_meta("struck_ms", -100000)) < HIT_GRACE_MS:
				continue
			p.set_meta("struck_ms", Time.get_ticks_msec())
			_rpc_hurt.rpc(p.get_path(), dmg)
		else:
			_rpc_shove.rpc(p.get_path())

# ------------------------------------------------------------------ the charge

func _start_charge(dir: Vector3) -> void:
	_charge_dir = dir
	_charge_cd = _rng.randf_range(9.0, 13.0) if phase == 1 else _rng.randf_range(5.0, 8.0)
	_act = "charge"
	_act_t = 0.0
	_act_len = 2.4
	_hit_struck.clear()
	state = Zombie.S.CHARGE
	_rpc_act.rpc("charge", 1.0)
	_rpc_voice.rpc("warden_roar")

func _tick_charge(delta: float) -> void:
	# A beat to lower his head, then he goes; he steers only a little.
	if _act_t < 0.45:
		velocity = Vector3.ZERO
		if target and is_instance_valid(target):
			var to := target.global_position - global_position
			to.y = 0.0
			_charge_dir = to.normalized()
			_turn_to(to, delta, 6.0)
		return
	if target and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		_charge_dir = _charge_dir.slerp(to.normalized(), 0.6 * delta).normalized()
	_turn_to(_charge_dir, delta, 8.0)
	velocity = _charge_dir * CHARGE_SPEED
	velocity.y = -4.0
	move_and_slide()
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed or _hit_struck.has(p):
			continue
		var to: Vector3 = p.global_position - global_position
		to.y = 0.0
		if to.length() < 1.3 and not p.get("dodging"):
			_hit_struck[p] = true
			_rpc_hurt.rpc(p.get_path(), 30.0)
	# Into a wall: he's dazed for a moment.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(-_charge_dir) > 0.6 and not (c.get_collider() is Player):
			_rpc_blow.rpc("crash", 0.9)
			_act = "dazed"
			_act_t = 0.0
			_act_len = 2.6
			_hits = []
			state = Zombie.S.STAGGER
			_rpc_act.rpc("head_hold", 1.2)
			return
	if _act_t >= _act_len:
		_act = ""
		state = Zombie.S.CHASE
		_cd = 0.4

# ------------------------------------------------------------------ phase two

func _phase_two() -> void:
	phase = 2
	_start("roar", 1.3)
	if _shield_hp > 0.0:
		_shield_hp = 0.0
		_rpc_shield_break.rpc()
	get_tree().call_group("story", "warden_phase_two")

# ------------------------------------------------------------------ getting hurt (host)

func take_hit(dmg: float, weapon_id: String, zone: String, dir: Vector3) -> void:
	if state == Zombie.S.DEAD or not awake:
		return
	var w: Dictionary = WeaponDB.WEAPONS.get(weapon_id, {})
	var kneeling := _act == "kneel"
	var dazed := _act == "dazed"
	# The shield: everything from the front but the legs and the growth.
	if _shield_hp > 0.0 and zone in ["head", "torso", "arm"] and not kneeling and not dazed \
			and (-global_basis.z).dot(-dir) > 0.3 and not Cheats.on("one_hit_kills"):
		_shield_hp -= dmg * (1.6 if w.get("kind") == "melee" else 1.0)
		if _shield_hp <= 0.0:
			_shield_hp = 0.0
			_rpc_shield_break.rpc()
			_stagger("hit")
		else:
			_rpc_shield_block.rpc(1.0 - _shield_hp / SHIELD_HP)
		return
	var total: float = dmg * ZONE_MULT.get(zone, 1.0) * (1.5 if kneeling or dazed else 1.0)
	hp -= total
	if zone == "wound" and not kneeling:
		_wound += total
		if _wound >= WOUND_KNEEL and _act not in ["roar", "charge"]:
			_wound = 0.0
			_kneel()
	elif _poise <= 0.0 and (w.get("stagger", 0.0) > 0.0 or total >= 90.0) and _act in ["", "swing", "slash", "combo", "combo2", "stomp"]:
		_stagger("hit_back" if (-global_basis.z).dot(-dir) < 0.0 else "hit")
	_rpc_hit_fx.rpc(zone)
	if hp <= 0.0:
		_die()

func _stagger(clip: String) -> void:
	_poise = 5.0
	_act = "dazed"
	_act_t = 0.0
	_act_len = 1.0
	_hits = []
	state = Zombie.S.STAGGER
	_rpc_act.rpc(clip, 1.3)

func _kneel() -> void:
	_act = "kneel"
	_act_t = 0.0
	_act_speed = 1.0
	_act_len = INF
	_kneel_t = 4.5
	_hits = []
	state = Zombie.S.STAGGER
	_rpc_act.rpc("kneel", 1.0)
	_rpc_voice.rpc("warden_pain")
	get_tree().call_group("story", "warden_kneels")

func hear_noise(_pos: Vector3) -> void:
	pass

func wake_from_dead() -> void:
	pass

## A flash grenade: he reels, clutching his head.
func flashed(secs: float) -> void:
	if state == Zombie.S.DEAD or not awake or _act in ["kneel", "roar"]:
		return
	_act = "dazed"
	_act_t = 0.0
	_act_len = minf(secs, 2.5)
	_hits = []
	state = Zombie.S.STAGGER
	_rpc_act.rpc("head_hold", 1.0)

func _die() -> void:
	state = Zombie.S.DEAD
	_act = ""
	collision_layer = 0
	for h in _hitboxes:
		h.collision_layer = 0
	GameState.set_flag("c2_warden_dead")
	_rpc_die.rpc()

# ------------------------------------------------------------------ every phone

var _clip := ""
var _look_hold := 0.0

func _play(clip: String, speed := 1.0) -> void:
	if actor == null or actor._anim == null:
		return
	if clip == _clip:
		actor._anim.speed_scale = speed
		return
	_clip = clip
	if actor._anim.has_animation(clip):
		actor._anim.play(clip, 0.25)
		actor._anim.speed_scale = speed

## The partner's phone has no brain for him: the walk follows the synced
## position, the moves come by RPC.
func _tick_look(delta: float) -> void:
	_growth_t += delta
	if _growth_mat:
		_growth_mat.emission_energy_multiplier = 1.0 + sin(_growth_t * (3.0 if phase == 1 else 5.0)) * 0.6 + (1.2 if _wound > WOUND_KNEEL * 0.6 else 0.0)
	# Down on one knee: held at the clip's lowest point, heaving.
	if _clip == "kneel" and actor and actor._anim and actor._anim.current_animation == "kneel":
		var a: AnimationPlayer = actor._anim
		if a.speed_scale > 0.0 and a.current_animation_position >= KNEEL_AT:
			a.speed_scale = 0.0
		if a.speed_scale == 0.0:
			a.seek(KNEEL_AT - 0.04 + sin(_growth_t * 2.4) * 0.04, true)
	if multiplayer.is_server() or state == Zombie.S.DEAD:
		return
	_look_hold -= delta
	if _look_hold > 0.0:
		return
	if state in [Zombie.S.CHASE]:
		_play("advance" if phase == 1 else "run", 1.0 if phase == 1 else 0.86)
	elif state == Zombie.S.IDLE:
		_play("idle")

@rpc("authority", "reliable", "call_local")
func _rpc_act(clip: String, speed: float) -> void:
	if actor == null or actor._anim == null:
		return
	_clip = clip
	var a: AnimationPlayer = actor._anim
	match clip:
		"rise":
			# Back up off the knee: the rest of the kneel clip.
			if a.current_animation != "kneel":
				a.play("kneel", 0.15)
				a.seek(KNEEL_AT, true)
			a.speed_scale = speed
		_:
			if a.has_animation(clip):
				a.play(clip, 0.12)
				a.speed_scale = speed
	_look_hold = 2.6
	if clip in ["swing", "slash", "combo", "combo2", "slam", "ground_slam", "shield_push"]:
		Sfx.voice("warden_attack", self, 2.0, 4.0, 30.0)
	elif clip == "roar":
		Sfx.voice("warden_roar", self, 6.0, 6.0, 40.0)

@rpc("authority", "unreliable", "call_local")
func _rpc_voice(id: String) -> void:
	Sfx.voice(id, self, 2.0, 4.0, 30.0)

## A blow: the truncheon's whoosh, or the floor taking a slam (dust, a jolt
## for whoever is near).
@rpc("authority", "reliable", "call_local")
func _rpc_blow(move: String, quake: float) -> void:
	var front := global_position - global_basis.z * 1.2
	if quake > 0.0:
		Sfx.play_at("warden_slam", front, "brute_slam", 4.0, 14.0)
		Effects.dust_puff(front + Vector3.UP * 0.1, 1.0 + quake)
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 9.0:
				p.shake(0.35 + quake * 0.3)
	elif move != "roar":
		Sfx.play_at("baton_whoosh", global_position + Vector3.UP * 1.3 - global_basis.z * 0.8, "zombie_swipe", 2.0, 5.0)

@rpc("authority", "reliable", "call_local")
func _rpc_hurt(path: NodePath, dmg: float) -> void:
	var p := get_node_or_null(path)
	if p:
		Sfx.play_at("baton_hit", p.global_position + Vector3.UP * 1.2, "melee_hit", 2.0, 8.0)
		if p.is_multiplayer_authority():
			p.apply_damage(dmg, self)

## The roar's blast of air: no harm, but it shoves them back.
@rpc("authority", "reliable", "call_local")
func _rpc_shove(path: NodePath) -> void:
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority():
		var away: Vector3 = p.global_position - global_position
		away.y = 0.0
		p.set("_knock", away.normalized() * 6.0)
		p.shake(0.6)

@rpc("authority", "unreliable", "call_local")
func _rpc_hit_fx(zone: String) -> void:
	var at := global_position + Vector3.UP * (1.7 if zone == "head" else 1.3 if zone in ["torso", "wound", "arm"] else 0.5)
	Sfx.play_at("flesh_hit", at, "", -2.0, 7.0)
	if zone == "wound":
		Effects.blood(at + global_basis.z * 0.25, global_basis.z, global_basis.z, 1.4)

@rpc("authority", "unreliable", "call_local")
func _rpc_shield_block(cracked: float) -> void:
	Sfx.play_at("shield_ricochet", global_position + Vector3.UP * 1.3, "", 0.0, 10.0)
	Effects.impact(global_position + Vector3.UP * 1.3 - global_basis.z * 0.5, -global_basis.z, null)
	if _crack_mat:
		_crack_mat.albedo_color.a = clampf(0.25 + cracked * 0.85, 0.0, 1.0)
	if not GameState.has_flag("tip:warden_back"):
		GameState.set_flag("tip:warden_back")
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("The shield stops it. Get behind him: the growth on his back.")

@rpc("authority", "reliable", "call_local")
func _rpc_shield_break() -> void:
	_shield_hp = 0.0
	if _shield == null or not is_instance_valid(_shield):
		return
	Sfx.play_at("glass_break", global_position + Vector3.UP * 1.3, "shield_ricochet", 4.0, 12.0)
	var xf := _shield.global_transform
	var level := get_tree().current_scene
	_shield.get_parent().remove_child(_shield)
	level.add_child(_shield)
	_shield.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	_shield.scale = Vector3.ONE
	if _crack_mat:
		_crack_mat.albedo_color.a = 1.0
	var t := _shield.create_tween()
	t.set_parallel(true)
	t.tween_property(_shield, "global_position", Vector3(xf.origin.x, global_position.y + 0.03, xf.origin.z) - global_basis.z * 0.5 + global_basis.x * 0.4, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_shield, "rotation", Vector3(-PI / 2, _shield.rotation.y + 0.4, 0.0), 0.55)
	_shield = null

@rpc("authority", "reliable", "call_local")
func _rpc_die() -> void:
	state = Zombie.S.DEAD
	remove_from_group("zombies")
	collision_layer = 0
	for h in _hitboxes:
		h.collision_layer = 0
	if actor and actor._anim and actor._anim.has_animation("death"):
		actor._anim.play("death", 0.2)
		actor._anim.speed_scale = 1.0
	Sfx.voice("warden_death", self, 6.0, 5.0, 40.0)
	if _growth_mat:
		var t := create_tween()
		t.tween_property(_growth_mat, "emission_energy_multiplier", 0.0, 2.5)
	died.emit()
	get_tree().call_group("story", "warden_died", global_position)
