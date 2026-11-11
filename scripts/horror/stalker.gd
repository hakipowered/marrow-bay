class_name Stalker
extends CharacterBody3D
## The Tallyman: a towering figure in a sealed black rubber coat and a riveted
## respirator mask, dragging a hooked iron archive pole. He was the Archive's
## night keeper; now he walks the building counting the living.
## He cannot be killed: enough damage drops him to one knee for a few seconds.
## Heavy footsteps carry through walls. He opens normal doors. He does not run;
## he does not need to. Host-simulated.

@export var active := false
var target: Node3D
var _agent: NavigationAgent3D
var _step_t := 0.0
var _stagger := 0.0
var _hurt := 0.0
var _attack_cd := 0.0
var _model: Node3D
var _hitboxes: Array = []

const SPEED := 1.55
const STAGGER_DAMAGE := 260.0

func _ready() -> void:
	add_to_group("stalker")
	collision_layer = 4
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.5
	cs.shape = cap
	cs.position.y = 1.25
	add_child(cs)
	_model = _build_model()
	add_child(_model)
	for z in [["head", Vector3(0, 2.3, 0), Vector3(0.3, 0.32, 0.3)], ["torso", Vector3(0, 1.55, 0), Vector3(0.62, 0.9, 0.38)], ["leg", Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.3)]]:
		var a := Area3D.new()
		a.collision_layer = 8
		a.monitoring = false
		a.set_meta("hit_zone", z[0])
		a.set_meta("enemy", self)
		a.set_meta("owner_path", "stalker")
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = z[2]
		c.shape = b
		a.add_child(c)
		a.position = z[1]
		add_child(a)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	add_child(_agent)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":active"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	add_child(sync)
	visible = active

func _build_model() -> Node3D:
	var path := "res://assets/characters/tallyman/tallyman.glb"
	if ResourceLoader.exists(path):
		return load(path).instantiate()
	var root := Node3D.new()
	var coat := Mats.trim(Color(0.04, 0.04, 0.045), 0.15)  # wet rubber
	var brass := Mats.trim(Color(0.45, 0.33, 0.15), 0.35, 0.9)
	var parts := [
		[CapsuleMesh, Vector3(0, 1.3, 0), Vector2(0.36, 2.2), coat],
		[SphereMesh, Vector3(0, 2.32, 0.04), Vector2(0.16, 0.34), coat],
		[CylinderMesh, Vector3(0, 2.28, -0.14), Vector2(0.07, 0.12), brass],  # respirator canister
		[BoxMesh, Vector3(0.55, 1.2, -0.3), Vector2(0.04, 2.6), Mats.trim(Color(0.2, 0.18, 0.16), 0.6, 0.8)],  # iron pole
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var m: PrimitiveMesh = p[0].new()
		if m is CapsuleMesh:
			m.radius = p[2].x; m.height = p[2].y
		elif m is SphereMesh:
			m.radius = p[2].x; m.height = p[2].y
		elif m is CylinderMesh:
			m.top_radius = p[2].x; m.bottom_radius = p[2].x; m.height = p[2].y
			mi.rotation_degrees.x = 90
		else:
			m.size = Vector3(p[2].x, p[2].y, p[2].x)
		mi.mesh = m
		mi.material_override = p[3]
		mi.position = p[1]
		root.add_child(mi)
	# Two dim lenses in the mask.
	for x in [-0.06, 0.06]:
		var eye := OmniLight3D.new()
		eye.light_color = Color(1.0, 0.55, 0.2)
		eye.light_energy = 0.4
		eye.omni_range = 0.6
		eye.position = Vector3(x, 2.36, -0.16)
		root.add_child(eye)
	return root

@rpc("authority", "reliable", "call_local")
func activate(at: Vector3) -> void:
	active = true
	visible = true
	global_position = at

func _physics_process(delta: float) -> void:
	visible = active
	if not active:
		return
	_step_t -= delta * (velocity.length() / SPEED)
	if _step_t <= 0 and velocity.length() > 0.2:
		_step_t = 0.85
		Sfx.play_at("stalker_step", global_position, "", 3.0, 18.0)
	if not multiplayer.is_server():
		return
	_attack_cd -= delta
	if _stagger > 0:
		_stagger -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		return
	target = _nearest()
	if target == null:
		return
	var d := global_position.distance_to(target.global_position)
	if d < 1.8 and _attack_cd <= 0:
		_attack_cd = 2.2
		_swing.rpc(target.get_path())
	_agent.target_position = target.global_position
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity = Vector3(dir.x * SPEED, velocity.y - 18.0 * delta, dir.z * SPEED)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 3 * delta)
	move_and_slide()
	# Opens ordinary doors in his way. Locked and co-op doors still stop him.
	for door in get_tree().get_nodes_in_group("doors"):
		if door.kind == Door.Kind.MANUAL and not door.is_open and door.global_position.distance_to(global_position) < 1.6:
			door._rpc_set_open.rpc(true, -global_transform.basis.z)

func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("players"):
		var dd := global_position.distance_to(p.global_position)
		if not p.downed and dd < bd:
			bd = dd
			best = p
	return best

@rpc("authority", "reliable", "call_local")
func _swing(path: NodePath) -> void:
	Sfx.play_at("stalker_swing", global_position + Vector3.UP * 1.5, "", 4.0, 12.0)
	await get_tree().create_timer(0.6).timeout
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 2.2:
		p.apply_damage(45.0, self)

## Host only, from Combat.
func take_hit(dmg: float, _weapon_id: String, zone: String, _dir: Vector3) -> void:
	_hurt += dmg * (1.5 if zone == "head" else 1.0)
	if _hurt >= STAGGER_DAMAGE:
		_hurt = 0.0
		_stagger = 4.0
		_kneel.rpc()

@rpc("authority", "reliable", "call_local")
func _kneel() -> void:
	Sfx.play_at("stalker_kneel", global_position, "", 4.0, 14.0)
	var t := create_tween()
	t.tween_property(_model, "position:y", -0.5, 0.4)
	t.tween_interval(3.4)
	t.tween_property(_model, "position:y", 0.0, 0.6)

func hear_noise(_pos: Vector3) -> void:
	pass
