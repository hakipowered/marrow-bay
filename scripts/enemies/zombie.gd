class_name Zombie
extends CharacterBody3D
## Every infected enemy. Behavior comes from EnemyDB flags (see enemy_db.gd).
## Host simulates; partner interpolates through the synchronizer.
## Hit zones: head (x3, can pop), torso, arms, legs (cripple -> crawls).

enum S { IDLE, WANDER, CHASE, ATTACK, STAGGER, CRAWL, DEAD, FEED, PLAY_DEAD, HIDDEN, PINNING, CHARGE }

@export var variant := "shambler"
@export var look := ""
@export var start_asleep := false
@export var state: S = S.IDLE
@export var crippled := false
@export var head_gone := false

var data: Dictionary
var hp := 120.0
var max_hp := 120.0
var drop_table := "zombie"
var target: Node3D = null
var noise_pos := Vector3.INF
var legs_hp := 60.0
var head_hp := 90.0
var _attack_cd := 0.0
var _stagger_t := 0.0
var _groan_t := 0.0
var _repath_t := 0.0
var _special_cd := 0.0
var _pinned: Node3D = null
var _charge_dir := Vector3.ZERO
var _charge_t := 0.0
var _rng := RandomNumberGenerator.new()
var agent: NavigationAgent3D
var model: ZombieModel
var _hitboxes: Array = []

func _ready() -> void:
	add_to_group("zombies")
	data = EnemyDB.get_type(variant)
	_rng.seed = hash(name)
	if look == "":
		look = data["looks"][_rng.randi() % data["looks"].size()]
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	max_hp = data["hp"] * _rng.randf_range(0.9, 1.15)
	hp = max_hp
	drop_table = data["drop"]
	var h: float = data.get("height", 1.0) * (0.35 if data.get("tiny") else 1.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * data.get("bulk", 1.0) * (0.6 if data.get("tiny") else 1.0)
	cap.height = max(1.75 * h, cap.radius * 2.0 + 0.05)
	if data.get("quadruped"):
		cap.height = 0.9
	shape.shape = cap
	shape.position.y = cap.height / 2
	add_child(shape)
	model = ZombieModel.new()
	model.variant = variant
	model.look = look
	model.data = data
	add_child(model)
	_build_hitboxes(h)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 1.0
	agent.radius = 0.35
	add_child(agent)
	_groan_t = _rng.randf_range(2.0, 7.0)
	if start_asleep:
		state = S.FEED
	if data.get("plays_dead"):
		state = S.PLAY_DEAD
	if data.get("ceiling_drop"):
		state = S.HIDDEN
	if data.get("crawl"):
		crippled = true
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":state", ":crippled", ":head_gone"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)

## Precise hitboxes sized to the body parts, not one big capsule.
func _build_hitboxes(h: float) -> void:
	var b: float = data.get("bulk", 1.0)
	var zones := [
		["head", Vector3(0, 1.62, 0.04), Vector3(0.24, 0.27, 0.26)],
		["torso", Vector3(0, 1.2, 0), Vector3(0.44 * b, 0.6, 0.26 * b)],
		["arm", Vector3(-0.3 * b, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["arm", Vector3(0.3 * b, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["leg", Vector3(-0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
		["leg", Vector3(0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
	]
	if data.get("quadruped"):
		zones = [["head", Vector3(0, 0.6, -0.55), Vector3(0.22, 0.22, 0.3)], ["torso", Vector3(0, 0.55, 0), Vector3(0.3, 0.32, 0.8)], ["leg", Vector3(0, 0.22, 0), Vector3(0.3, 0.44, 0.7)]]
	elif data.get("crawl"):
		zones = [["head", Vector3(0, 0.3 * h, -0.7 * h), Vector3(0.24, 0.24, 0.26) * h], ["torso", Vector3(0, 0.25 * h, -0.2 * h), Vector3(0.44, 0.3, 0.7) * h], ["arm", Vector3(0, 0.15 * h, -0.8 * h), Vector3(0.6, 0.15, 0.3) * h]]
	for z in zones:
		var a := Area3D.new()
		a.collision_layer = 8
		a.collision_mask = 0
		a.monitoring = false
		a.set_meta("hit_zone", z[0])
		a.set_meta("enemy", self)
		a.set_meta("owner_path", str(name))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = z[2] if (data.get("quadruped") or data.get("crawl")) else z[2] * Vector3(1, h, 1)
		cs.shape = box
		a.position = z[1] if (data.get("quadruped") or data.get("crawl")) else z[1] * Vector3(1, h, 1)
		a.add_child(cs)
		add_child(a)
		_hitboxes.append(a)

func _physics_process(delta: float) -> void:
	model.animate(state, velocity.length(), crippled, head_gone)
	_groan_t -= delta
	if _groan_t <= 0 and state not in [S.DEAD, S.PLAY_DEAD, S.HIDDEN]:
		_groan_t = _rng.randf_range(3.5, 9.0) if state != S.CHASE else _rng.randf_range(1.8, 4.0)
		_groan.rpc(_sound_id("chase" if state == S.CHASE else "idle"))
	if not multiplayer.is_server() or state == S.DEAD:
		return
	_attack_cd -= delta
	_special_cd -= delta
	var speed_mult := 0.5 if Cheats.on("slow_zombies") else 1.0
	match state:
		S.FEED, S.IDLE:
			_look_for_players(9.0 if state == S.IDLE else 4.5)
			velocity = Vector3.ZERO
		S.PLAY_DEAD:
			velocity = Vector3.ZERO
			var p := _nearest_player()
			# Waits until someone walks past, then gets up behind them.
			if p and global_position.distance_to(p.global_position) < 2.2:
				wake_from_dead()
		S.HIDDEN:
			velocity = Vector3.ZERO
			var p2 := _nearest_player()
			if p2 and Vector2(global_position.x, global_position.z).distance_to(Vector2(p2.global_position.x, p2.global_position.z)) < 2.5:
				_drop_from_ceiling.rpc()
		S.WANDER:
			_look_for_players(9.0)
		S.STAGGER:
			_stagger_t -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 8 * delta)
			if _stagger_t <= 0:
				state = S.CRAWL if crippled else S.CHASE
		S.PINNING:
			velocity = Vector3.ZERO
			if not is_instance_valid(_pinned) or _pinned.downed:
				_release_pin()
			elif _attack_cd <= 0:
				_attack_cd = 1.0
				_rpc_hurt_player.rpc(_pinned.get_path(), data["dmg"])
		S.CHARGE:
			_charge_t -= delta
			velocity = _charge_dir * 6.5
			for p in get_tree().get_nodes_in_group("players"):
				if p.global_position.distance_to(global_position) < 1.3:
					_rpc_hurt_player.rpc(p.get_path(), data["dmg"] * 1.3)
					_charge_t = 0
			if _charge_t <= 0 or get_slide_collision_count() > 0:
				if get_slide_collision_count() > 0:
					_set_stagger(1.6)   # slammed into a wall: a window to punish him
					_groan.rpc("brute_slam")
				else:
					state = S.CHASE
		S.CHASE, S.CRAWL:
			target = _nearest_player()
			if target == null:
				state = S.IDLE
			else:
				_chase(delta, speed_mult)
		S.ATTACK:
			velocity = Vector3.ZERO
	if data.get("spawner") and state != S.DEAD and _special_cd <= 0 and _nearest_player() and global_position.distance_to(_nearest_player().global_position) < 18.0:
		_special_cd = data["spawn_every"]
		get_parent().spawn_zombie_synced.rpc("%s_spawn%d" % [name, _rng.randi() % 100000], global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0, 1.5), data["spawner"])
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()

func _chase(delta: float, speed_mult: float) -> void:
	var dist := global_position.distance_to(target.global_position)
	if data.get("screams") and _special_cd <= 0 and dist < 12.0:
		_special_cd = 14.0
		_scream()
	if data.has("ranged") and dist < data["range"] and dist > 3.0 and _special_cd <= 0:
		_special_cd = 3.5
		_spit.rpc(target.global_position + Vector3.UP)
		velocity = Vector3.ZERO
		return
	if data.get("charge") and dist > 4.0 and dist < 12.0 and _special_cd <= 0:
		_special_cd = 8.0
		_charge_dir = (target.global_position - global_position) * Vector3(1, 0, 1)
		_charge_dir = _charge_dir.normalized()
		_charge_t = 1.6
		state = S.CHARGE
		_groan.rpc("brute_roar")
		return
	var reach: float = data["reach"] * (0.8 if crippled and not data.get("crawl") else 1.0)
	if dist < reach and _attack_cd <= 0:
		state = S.ATTACK
		_attack_cd = 1.6 if not data.get("lunge") else 1.0
		_attack()
		return
	var spd: float = (0.35 if crippled and not data.get("crawl") else data["speed"]) * speed_mult * _rng.randf_range(0.95, 1.08)
	if data.get("lunge") and dist < 3.5 and _special_cd <= 0:
		_special_cd = 2.5
		spd *= 2.0
	_move_to(target.global_position, spd, delta)

func _sound_id(kind: String) -> String:
	var family := "zombie"
	if data.get("quadruped"):
		family = "hound"
	elif data.get("mutant"):
		family = "mutant"
	elif variant == "brute":
		family = "brute"
	return "%s_%s" % [family, kind]

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
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 5 * delta)

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
		state = S.CRAWL if crippled else S.CHASE
		_groan.rpc(_sound_id("alert"))
	elif noise_pos != Vector3.INF:
		state = S.WANDER
		_move_to(noise_pos, data["speed"] * 0.7, get_physics_process_delta_time())
		if global_position.distance_to(noise_pos) < 1.5:
			noise_pos = Vector3.INF
			state = S.IDLE

func hear_noise(pos: Vector3) -> void:
	if state in [S.IDLE, S.FEED, S.WANDER]:
		noise_pos = pos
		state = S.WANDER

func wake_from_dead() -> void:
	if state in [S.PLAY_DEAD, S.FEED, S.IDLE]:
		state = S.CHASE
		_rise.rpc()

@rpc("authority", "reliable", "call_local")
func _rise() -> void:
	model.rise()
	Sfx.play_at(_sound_id("alert"), global_position, "", 4.0, 9.0)
	var d := get_tree().get_first_node_in_group("horror")
	if d:
		d.post_fx.spike(0.7)

@rpc("authority", "reliable", "call_local")
func _drop_from_ceiling() -> void:
	state = S.CHASE
	model.drop_from_ceiling()
	Sfx.play_at("vent_burst", global_position + Vector3.UP * 3.0, "metal_bang", 6.0, 12.0)
	var d := get_tree().get_first_node_in_group("horror")
	if d:
		d.post_fx.spike(0.9)

func _scream() -> void:
	_groan.rpc("screamer_shriek")
	for z in get_tree().get_nodes_in_group("zombies"):
		if z != self and z.global_position.distance_to(global_position) < 30.0:
			z.hear_noise(target.global_position if target else global_position)
			if z.state == S.WANDER:
				z.state = S.CHASE

@rpc("authority", "reliable", "call_local")
func _spit(at: Vector3) -> void:
	Sfx.play_at("spitter_spit", global_position + Vector3.UP * 1.5, "", 2.0, 9.0)
	var glob := Projectile.new()
	glob.weapon_id = "acid_glob"
	glob.direction = (at - (global_position + Vector3.UP * 1.6)).normalized()
	glob.authoritative = multiplayer.is_server()
	glob.hostile = true
	get_parent().add_child(glob)
	glob.global_position = global_position + Vector3.UP * 1.6 - global_transform.basis.z * 0.4

func _attack() -> void:
	_groan.rpc(_sound_id("attack"))
	await get_tree().create_timer(0.5 if not data.get("lunge") else 0.3).timeout
	if state == S.DEAD or target == null:
		return
	if global_position.distance_to(target.global_position) < data["reach"] + 0.3:
		if data.get("pins") and not target.pinned:
			_pinned = target
			state = S.PINNING
			_set_pinned.rpc(target.get_path(), true)
			return
		_rpc_hurt_player.rpc(target.get_path(), data["dmg"])
		if data.get("ignites"):
			_ignite.rpc(target.get_path())
		if data.get("ankle_grab"):
			_slow_player.rpc(target.get_path(), 1.5)
	if state == S.ATTACK:
		state = S.CRAWL if crippled else S.CHASE

@rpc("authority", "reliable", "call_local")
func _set_pinned(path: NodePath, on: bool) -> void:
	var p := get_node_or_null(path)
	if p:
		p.set_pinned(on, self)

func _release_pin() -> void:
	if is_instance_valid(_pinned):
		_set_pinned.rpc(_pinned.get_path(), false)
	_pinned = null
	_set_stagger(1.2)

## A partner (or struggling enough) frees a pinned player.
func break_pin() -> void:
	if multiplayer.is_server() and state == S.PINNING:
		_release_pin()

@rpc("authority", "reliable", "call_local")
func _rpc_hurt_player(path: NodePath, dmg: float) -> void:
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority():
		p.apply_damage(dmg, self)

@rpc("authority", "reliable", "call_local")
func _ignite(path: NodePath) -> void:
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority():
		p.set_burning(4.0)

@rpc("authority", "reliable", "call_local")
func _slow_player(path: NodePath, secs: float) -> void:
	var p := get_node_or_null(path)
	if p and p.is_multiplayer_authority():
		p.slowed_for = secs

## Host only.
func take_hit(dmg: float, weapon_id: String, zone: String, dir: Vector3) -> void:
	if state == S.DEAD:
		return
	var w: Dictionary = WeaponDB.WEAPONS.get(weapon_id, {})
	if data.get("fire_immune") and w.get("kind") == "flame":
		return
	# Riot shield blocks hits from the front, except the legs.
	if data.get("shield") and zone != "leg" and (-global_transform.basis.z).dot(-dir) > 0.35 and not Cheats.on("one_hit_kills"):
		_shield_block.rpc()
		return
	var total: float = dmg * EnemyDB.ZONE_MULT.get(zone, 1.0)
	hp -= total
	if state in [S.IDLE, S.FEED, S.WANDER, S.PLAY_DEAD, S.HIDDEN]:
		state = S.CRAWL if crippled else S.CHASE
	if state == S.PINNING and total > 25:
		_release_pin()
	match zone:
		"head":
			head_hp -= dmg
			if head_hp <= 0 and not head_gone and (dmg >= 60 or w.get("kind") == "pellets"):
				head_gone = true
				hp = 0
		"leg":
			legs_hp -= dmg
			if legs_hp <= 0 and not crippled and not data.get("quadruped"):
				crippled = true
				_set_stagger(1.2)
	if (w.get("stagger", 0.0) > 0 or total > 50) and variant not in ["brute", "brood_mother"]:
		_set_stagger(0.6 + w.get("stagger", 0.0) * 0.6)
		velocity = dir * 1.5
	_rpc_hit_fx.rpc(zone)
	if hp <= 0:
		_die()

func _set_stagger(t: float) -> void:
	if variant == "brood_mother":
		return
	state = S.STAGGER
	_stagger_t = t

func _die() -> void:
	if _pinned:
		_release_pin()
	state = S.DEAD
	collision_layer = 0
	for h in _hitboxes:
		h.collision_layer = 0
	GameState.set_flag("dead:" + str(name))
	_rpc_die.rpc()
	var drop := WeaponDB.roll_drop(drop_table, _rng)
	if drop != "none":
		get_parent().spawn_pickup.rpc(drop, global_position + Vector3(0, 0.05, 0), -1)
	if data.get("death_gas"):
		get_parent().spawn_hazard.rpc("acid_gas", global_position, 3.2, 6.0)

@rpc("authority", "reliable", "call_local")
func _rpc_die() -> void:
	state = S.DEAD
	model.die(head_gone)
	Sfx.play_at(_sound_id("death"), global_position, "zombie_death", 0.0, 9.0)
	if data.get("death_gas"):
		Sfx.play_at("bloater_burst", global_position, "", 6.0, 12.0)

@rpc("authority", "unreliable", "call_local")
func _rpc_hit_fx(zone: String) -> void:
	model.hit_react(zone)
	Sfx.play_at("flesh_hit", global_position + Vector3.UP, "", -4.0, 6.0)

@rpc("authority", "unreliable", "call_local")
func _shield_block() -> void:
	Sfx.play_at("shield_ricochet", global_position + Vector3.UP * 1.2, "", 0.0, 10.0)
	Effects.impact(global_position + Vector3.UP * 1.2 - global_transform.basis.z * 0.4, -global_transform.basis.z, null)

@rpc("authority", "unreliable", "call_local")
func _groan(kind: String) -> void:
	Sfx.attach(kind, self, 2.0 if kind.ends_with("alert") else 0.0, 7.0)
