class_name Zombie
extends CharacterBody3D
## Shambler. Host-simulated; clients interpolate via synchronizer.
## Hit zones: head (x3, can pop), torso, left/right arm (can sever),
## legs (crippled -> crawls). Groans on a randomized timer plus reactive sounds.

enum S { IDLE, WANDER, CHASE, ATTACK, STAGGER, CRAWL, DEAD, FEED }

@export var variant := "civilian"  # civilian, officer, bloated, brute
@export var max_hp := 120.0
@export var drop_table := "zombie"
@export var start_asleep := false

var hp := 120.0
@export var state: S = S.IDLE
var target: Node3D = null
var noise_pos := Vector3.INF
var legs_hp := 60.0
var head_hp := 90.0
@export var crippled := false
@export var head_gone := false
var _attack_cd := 0.0
var _stagger_t := 0.0
var _groan_t := 0.0
var _repath_t := 0.0
var _rng := RandomNumberGenerator.new()
var agent: NavigationAgent3D
var model: Node3D
var _hitboxes: Array = []

const ZONE_MULT := {"head": 3.0, "torso": 1.0, "arm": 0.6, "leg": 0.8}

func _ready() -> void:
	add_to_group("zombies")
	_rng.randomize()
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	hp = max_hp * (1.6 if variant == "brute" else 1.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.88
	add_child(shape)
	model = ZombieModel.new()
	model.variant = variant
	add_child(model)
	_build_hitboxes()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 1.0
	agent.radius = 0.35
	add_child(agent)
	_groan_t = _rng.randf_range(2.0, 7.0)
	if start_asleep:
		state = S.FEED
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":state", ":crippled", ":head_gone"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)

## Precise hitboxes sized to the body parts, not one big capsule.
func _build_hitboxes() -> void:
	var zones := [
		["head", Vector3(0, 1.62, 0.04), Vector3(0.24, 0.27, 0.26)],
		["torso", Vector3(0, 1.2, 0), Vector3(0.44, 0.6, 0.26)],
		["arm", Vector3(-0.3, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["arm", Vector3(0.3, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["leg", Vector3(-0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
		["leg", Vector3(0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
	]
	for z in zones:
		var a := Area3D.new()
		a.collision_layer = 8
		a.collision_mask = 0
		a.monitoring = false
		a.set_meta("hit_zone", z[0])
		a.set_meta("enemy", self)
		a.set_meta("owner_path", str(get_path()))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = z[2]
		cs.shape = box
		a.position = z[1]
		a.add_child(cs)
		model.attach_hitbox(z[0], a)
		_hitboxes.append(a)

func _physics_process(delta: float) -> void:
	model.animate(state, velocity.length(), crippled, head_gone)
	_groan_t -= delta
	if _groan_t <= 0 and state != S.DEAD:
		_groan_t = _rng.randf_range(3.5, 9.0) if state != S.CHASE else _rng.randf_range(1.8, 4.0)
		_groan.rpc("zombie_chase" if state == S.CHASE else "zombie_idle")
	if not multiplayer.is_server() or state == S.DEAD:
		return
	_attack_cd -= delta
	var speed_mult := 0.5 if Cheats.on("slow_zombies") else 1.0
	match state:
		S.FEED, S.IDLE:
			_look_for_players(9.0 if state == S.IDLE else 4.5)
			velocity = Vector3.ZERO
		S.WANDER:
			_look_for_players(9.0)
		S.STAGGER:
			_stagger_t -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 8 * delta)
			if _stagger_t <= 0:
				state = S.CRAWL if crippled else S.CHASE
		S.CHASE, S.CRAWL:
			target = _nearest_player()
			if target == null:
				state = S.IDLE
			else:
				var dist := global_position.distance_to(target.global_position)
				if dist < (1.2 if not crippled else 0.9) and _attack_cd <= 0:
					state = S.ATTACK
					_attack_cd = 1.6
					_attack()
				else:
					_move_to(target.global_position, (0.35 if crippled else _chase_speed()) * speed_mult, delta)
		S.ATTACK:
			velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()

func _chase_speed() -> float:
	return {"civilian": 0.9, "officer": 1.05, "bloated": 0.6, "brute": 1.3}.get(variant, 0.9) * _rng.randf_range(0.95, 1.1)

func _move_to(pos: Vector3, speed: float, delta: float) -> void:
	_repath_t -= delta
	if _repath_t <= 0:
		agent.target_position = pos
		_repath_t = 0.4
	var next := agent.get_next_path_position() if not agent.is_navigation_finished() else pos
	var dir := (next - global_position)
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 4 * delta)

func _nearest_player() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = p
	return best

func _look_for_players(radius: float) -> void:
	var p := _nearest_player()
	if p and global_position.distance_to(p.global_position) < radius:
		state = S.CHASE
		_groan.rpc("zombie_alert")
	elif noise_pos != Vector3.INF:
		state = S.WANDER
		_move_to(noise_pos, 0.7, get_physics_process_delta_time())
		if global_position.distance_to(noise_pos) < 1.5:
			noise_pos = Vector3.INF
			state = S.IDLE

func hear_noise(pos: Vector3) -> void:
	if state in [S.IDLE, S.FEED, S.WANDER]:
		noise_pos = pos
		if state != S.WANDER:
			state = S.WANDER

func _attack() -> void:
	_groan.rpc("zombie_attack")
	await get_tree().create_timer(0.55).timeout
	if state == S.DEAD or target == null:
		return
	if global_position.distance_to(target.global_position) < 1.5:
		_rpc_hurt_player.rpc(target.get_path(), {"civilian": 20.0, "officer": 22.0, "bloated": 30.0, "brute": 35.0}.get(variant, 20.0))
	if state == S.ATTACK:
		state = S.CRAWL if crippled else S.CHASE

@rpc("authority", "reliable", "call_local")
func _rpc_hurt_player(path: NodePath, dmg: float) -> void:
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority():
		p.apply_damage(dmg, self)

## Host only.
func take_hit(dmg: float, weapon_id: String, zone: String, dir: Vector3) -> void:
	if state == S.DEAD:
		return
	var total: float = dmg * ZONE_MULT.get(zone, 1.0)
	hp -= total
	if state in [S.IDLE, S.FEED, S.WANDER]:
		state = S.CHASE
	var w: Dictionary = WeaponDB.WEAPONS.get(weapon_id, {})
	match zone:
		"head":
			head_hp -= dmg
			if head_hp <= 0 and not head_gone and (dmg >= 60 or w.get("kind") == "pellets"):
				head_gone = true
				hp = 0
		"leg":
			legs_hp -= dmg
			if legs_hp <= 0 and not crippled:
				crippled = true
				_set_stagger(1.2)
	if w.get("stagger", 0.0) > 0 or total > 50:
		_set_stagger(0.6 + w.get("stagger", 0.0) * 0.6)
		velocity = dir * 1.5
	_rpc_hit_fx.rpc(zone)
	if hp <= 0:
		_die()

func _set_stagger(t: float) -> void:
	state = S.STAGGER
	_stagger_t = t

func _die() -> void:
	state = S.DEAD
	collision_layer = 0
	for h in _hitboxes:
		h.collision_layer = 0
	_rpc_die.rpc()
	var drop := WeaponDB.roll_drop(drop_table, _rng)
	if drop != "none":
		get_tree().current_scene.spawn_pickup.rpc(drop, global_position + Vector3(0, 0.05, 0), -1)

@rpc("authority", "reliable", "call_local")
func _rpc_die() -> void:
	state = S.DEAD
	model.die(head_gone)
	Sfx.play_at("zombie_death", global_position, "", 0.0, 9.0)

@rpc("authority", "unreliable", "call_local")
func _rpc_hit_fx(zone: String) -> void:
	model.hit_react(zone)
	Sfx.play_at("flesh_hit", global_position + Vector3.UP, "", -4.0, 6.0)

@rpc("authority", "unreliable", "call_local")
func _groan(kind: String) -> void:
	Sfx.attach(kind, self, 2.0 if kind == "zombie_alert" else 0.0, 7.0)
