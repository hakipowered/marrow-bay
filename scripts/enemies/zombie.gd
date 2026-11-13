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
var _speed_f := 1.0       # this one's pace, picked once (no twitchy per-frame speed)
var _atk := {}            # the current attack's timing (attack_timing)
var _attack_t := 0.0
var _struck := false
var _poise_t := 0.0       # after a flinch, a moment before the next hit can break its stride
var _flinch_t := 0.0      # rocked by a hit: barely moves and can't start a swing
var _shield_hp := 0.0     # riot shield: cracks under fire, then breaks off
var _last_hit := {}       # the blow that killed it: weapon, body part, direction (host)
## The last few deaths picked across the horde, so kills in a row don't all
## go down the same way.
static var _recent_deaths: Array = []

## Meshy punch clip: the arms are fully out at 1.5 s of clip time.
const ATTACK_STRIKE := 1.5
const POISE := 1.4
## After a blow lands on a survivor, no infected can land another on her for
## this long (milliseconds), so a crowd, or one zombie with her back to a
## wall, can't chain hits into a stun lock. Kept on the host, which runs
## every strike.
const GRACE_MS := 1300
## The one who landed the blow steps back from her, so a survivor pinned
## against a wall or a crate gets room to move.
var _recoil_t := 0.0
## Voices: a groan, then a pause before the next. Across the whole horde only
## one groan starts at a time, so a crowd murmurs instead of droning.
static var _last_groan_ms := 0
## Dropping in through a hole in the ceiling (HorrorDirector body_drop):
## 1 falling limp, 2 crumpled on the floor until _drop_t runs out, then it
## gets up like a possum does.
var _drop_phase := 0
var _drop_t := 0.0
var agent: NavigationAgent3D
var model: ZombieModel
var _hitboxes: Array = []
## The partner's phone only receives positions; it measures the pace from them
## so the walk, run and gallop clips play there too.
var _anim_pos := Vector3.INF
var _anim_speed := 0.0

## The hound's hitboxes ride on its bones: zone, bone, centre along the bone
## (m), box size. The ribcage comes first (aim assist aims at the first torso
## box). Cross-sections are square so the boxes fit whatever the bone's roll.
const HOUND_ZONES := [
	["torso", "spine2", 0.06, Vector3(0.33, 0.30, 0.33)],
	["torso", "chest", 0.05, Vector3(0.32, 0.16, 0.32)],
	["torso", "spine1", 0.07, Vector3(0.31, 0.17, 0.31)],
	["torso", "pelvis", 0.12, Vector3(0.30, 0.28, 0.30)],
	["torso", "neck1", 0.06, Vector3(0.21, 0.16, 0.21)],
	["head", "neck2", 0.06, Vector3(0.18, 0.12, 0.18)],
	["head", "head", 0.11, Vector3(0.20, 0.27, 0.20)],
	["leg", "upperarm_L", 0.08, Vector3(0.1, 0.18, 0.1)],
	["leg", "upperarm_R", 0.08, Vector3(0.1, 0.18, 0.1)],
	["leg", "forearm_L", 0.13, Vector3(0.08, 0.27, 0.08)],
	["leg", "forearm_R", 0.13, Vector3(0.08, 0.27, 0.08)],
	["leg", "thigh_L", 0.09, Vector3(0.13, 0.2, 0.13)],
	["leg", "thigh_R", 0.09, Vector3(0.13, 0.2, 0.13)],
	["leg", "shin_L", 0.13, Vector3(0.08, 0.27, 0.08)],
	["leg", "shin_R", 0.13, Vector3(0.08, 0.27, 0.08)],
]

func _ready() -> void:
	add_to_group("zombies")
	data = EnemyDB.get_type(variant)
	_rng.seed = hash(name)
	if look == "":
		look = data["looks"][_rng.randi() % data["looks"].size()]
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | Door.BARS_LAYER
	max_hp = data["hp"] * _rng.randf_range(0.94, 1.04)
	_shield_hp = data.get("shield_hp", 0.0)
	_speed_f = _rng.randf_range(0.9, 1.06)
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
	if data.get("quadruped") and model.has_bones():
		for z in HOUND_ZONES:
			var a := _zone_area(z[0], z[3])
			a.position = Vector3(0, z[2], 0)
			if model.attach_hitbox(z[1], a):
				_hitboxes.append(a)
			else:
				a.free()
		return
	var b: float = data.get("bulk", 1.0)
	var zones := [
		["head", Vector3(0, 1.62, 0.04), Vector3(0.24, 0.27, 0.26)],
		["torso", Vector3(0, 1.2, 0), Vector3(0.44 * b, 0.6, 0.26 * b)],
		["arm", Vector3(-0.3 * b, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["arm", Vector3(0.3 * b, 1.2, -0.15), Vector3(0.12, 0.6, 0.12)],
		["leg", Vector3(-0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
		["leg", Vector3(0.12, 0.45, 0), Vector3(0.16, 0.9, 0.16)],
	]
	if data.get("crawl"):
		zones = [["head", Vector3(0, 0.3 * h, -0.7 * h), Vector3(0.24, 0.24, 0.26) * h], ["torso", Vector3(0, 0.25 * h, -0.2 * h), Vector3(0.44, 0.3, 0.7) * h], ["arm", Vector3(0, 0.15 * h, -0.8 * h), Vector3(0.6, 0.15, 0.3) * h]]
	for z in zones:
		var a := _zone_area(z[0], z[2] if data.get("crawl") else z[2] * Vector3(1, h, 1))
		a.position = z[1] if data.get("crawl") else z[1] * Vector3(1, h, 1)
		add_child(a)
		_hitboxes.append(a)

func _zone_area(zone: String, size: Vector3) -> Area3D:
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
	return a

func _physics_process(delta: float) -> void:
	var pace := velocity.length()
	if not multiplayer.is_server():
		if _anim_pos != Vector3.INF and delta > 0.0:
			var moved := (global_position - _anim_pos) * Vector3(1, 0, 1)
			_anim_speed = lerpf(_anim_speed, moved.length() / delta, 0.15)
		_anim_pos = global_position
		pace = _anim_speed
	model.animate(state, pace, crippled, head_gone)
	_groan_t -= delta
	# Only the host voices groans; the RPC plays them on every phone. Each
	# one is followed by a pause, and only one of the horde starts at a time.
	if _groan_t <= 0 and is_multiplayer_authority() and state not in [S.DEAD, S.PLAY_DEAD, S.HIDDEN, S.ATTACK]:
		var now := Time.get_ticks_msec()
		var p := _nearest_player()
		var near := p != null and global_position.distance_to(p.global_position) < 22.0
		if not near or now - _last_groan_ms < (1600 if state == S.CHASE else 2800):
			_groan_t = _rng.randf_range(0.8, 2.0)   # someone else is talking, or nobody to hear
		else:
			_last_groan_ms = now
			_groan_t = _rng.randf_range(4.5, 9.0) if state == S.CHASE else _rng.randf_range(8.0, 16.0)
			_groan.rpc(_sound_id("chase" if state == S.CHASE else "idle"))
	if not multiplayer.is_server():
		return
	if state == S.DEAD:
		if not is_on_floor():   # killed in mid-air (falling through a hole): it still comes down
			velocity.x = 0.0
			velocity.z = 0.0
			_fall_and_slide(delta)
		return
	_attack_cd -= delta
	_special_cd -= delta
	_poise_t -= delta
	_flinch_t -= delta
	var speed_mult := 0.5 if Cheats.on("slow_zombies") else 1.0
	match state:
		S.FEED, S.IDLE:
			_look_for_players(9.0 if state == S.IDLE else 4.5)
			velocity = Vector3.ZERO
		S.PLAY_DEAD:
			if _drop_phase > 0:
				_tick_drop(delta)
				_fall_and_slide(delta)
				return
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
			velocity = _charge_dir * 5.4
			for p in get_tree().get_nodes_in_group("players"):
				if p.global_position.distance_to(global_position) < 1.3 and _clear_line(p) and _can_strike(p):
					_mark_struck(p)
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
			_tick_attack(delta)
	if data.get("spawner") and state != S.DEAD and _special_cd <= 0 and _nearest_player() and global_position.distance_to(_nearest_player().global_position) < 18.0:
		_special_cd = data["spawn_every"]
		get_parent().spawn_zombie_synced.rpc("%s_spawn%d" % [name, _rng.randi() % 100000], global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0, 1.5), data["spawner"])
	_fall_and_slide(delta)

func _fall_and_slide(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()

## Every phone, right after the spawn: it starts falling from where it was
## put (inside the hole). Until it lands it passes through survivors, so it
## never ends up standing on someone's head.
func drop_in() -> void:
	_drop_phase = 1
	state = S.PLAY_DEAD
	collision_mask = 1 | Door.BARS_LAYER
	var p := _nearest_player()
	if p and multiplayer.is_server():
		# Facing her: it crumples away from her and gets up looking at her.
		var to := p.global_position - global_position
		rotation.y = atan2(-to.x, -to.z)
	model.fall()

func _tick_drop(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _drop_phase == 1:
		if is_on_floor():
			_drop_phase = 2
			_drop_t = 2.6
			collision_mask = DROP_LYING_MASK
			_landed.rpc()
	else:
		_drop_t -= delta
		if _drop_t <= 0.0:
			_drop_phase = 0
			collision_mask = 1 | 2 | 4 | Door.BARS_LAYER
			wake_from_dead()

## Crumpled where it landed: not pushed about by other infected yet. One
## dropping down the same hole lands on top of it, and two overlapping
## bodies pushed it through the floor (the coal chute in chapter 2).
const DROP_LYING_MASK := 1 | 2 | Door.BARS_LAYER

@rpc("authority", "reliable", "call_local")
func _landed() -> void:
	_drop_phase = maxi(_drop_phase, 2)
	collision_mask = DROP_LYING_MASK
	model.land()
	Sfx.play_at("body_fall", global_position + Vector3.UP * 0.3, "", 8.0, 12.0)
	Effects.dust_puff(global_position + Vector3.UP * 0.05, 1.0)
	var d := get_tree().get_first_node_in_group("horror")
	if d:
		d.post_fx.spike(0.5)

func _chase(delta: float, speed_mult: float) -> void:
	var dist := global_position.distance_to(target.global_position)
	if data.get("screams") and _special_cd <= 0 and dist < 12.0:
		_special_cd = 14.0
		_scream()
	if data.has("ranged") and dist < data["range"] and dist > 3.0 and _special_cd <= 0 and _clear_line(target):
		_special_cd = 3.5
		_spit.rpc(target.global_position + Vector3.UP)
		velocity = Vector3.ZERO
		return
	if data.get("charge") and dist > 4.0 and dist < 12.0 and _special_cd <= 0 and _clear_line(target):
		_special_cd = 8.0
		_charge_dir = (target.global_position - global_position) * Vector3(1, 0, 1)
		_charge_dir = _charge_dir.normalized()
		_charge_t = 1.6
		state = S.CHARGE
		_groan.rpc("brute_roar")
		return
	var reach: float = data["reach"] * (0.8 if crippled and not data.get("crawl") else 1.0)
	# Only swings at someone it can actually reach: not through a wall, a
	# door or a shelf (it keeps walking round instead).
	if dist < reach and _attack_cd <= 0 and _flinch_t <= 0 and _clear_line(target):
		_begin_attack()
		return
	var spd: float = (0.35 if crippled and not data.get("crawl") else data["speed"]) * speed_mult * _speed_f
	if _flinch_t > 0:
		spd *= 0.15
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
		_flinch_t = 1.4   # still getting up
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
	_flinch_t = 1.6   # no swinging mid-shriek
	_groan.rpc("screamer_shriek")
	_rpc_scream.rpc()
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

## How a type's swing plays out. The punch clip starts at `from` and runs at
## `speed`, so the arms land exactly at `windup` seconds: that wind-up (with
## the snarl) is the warning, and the blow only counts at the strike frame.
## The zombie then hangs in the follow-through for `recover`, a window to back
## off or punish it. The model reads the same numbers so every phone matches.
static func attack_timing(d: Dictionary) -> Dictionary:
	var windup := 0.75
	if d.get("lunge"):
		windup = 0.5
	if d.get("quadruped"):
		windup = 0.42
	if d.get("bulk", 1.0) >= 1.4:
		windup = 0.95
	windup = d.get("windup", windup)
	var from := 0.45 if windup >= 0.6 else 1.0
	return {"windup": windup, "from": from, "speed": (ATTACK_STRIKE - from) / windup, "recover": 0.6}

func _begin_attack() -> void:
	state = S.ATTACK
	_atk = attack_timing(data)
	_attack_t = 0.0
	_struck = false
	_attack_cd = _atk["windup"] + _atk["recover"] + (0.5 if data.get("lunge") else 0.9)
	_groan.rpc(_sound_id("attack"))

func _tick_attack(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_t += delta
	if _struck:
		if _recoil_t > 0.0:
			_recoil_t -= delta
			var back := global_transform.basis.z
			velocity.x = back.x * 1.8
			velocity.z = back.z * 1.8
		if _attack_t >= _atk["windup"] + _atk["recover"]:
			state = S.CRAWL if crippled else S.CHASE
		return
	if target and is_instance_valid(target):
		# Turns with the target through most of the wind-up, then commits.
		var to := target.global_position - global_position
		var turn := 4.0 if _attack_t < _atk["windup"] * 0.7 else 0.8
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), turn * delta)
		if data.get("lunge"):
			var fwd := -global_transform.basis.z
			velocity.x = fwd.x * 1.4
			velocity.z = fwd.z * 1.4
	if _attack_t >= _atk["windup"]:
		_struck = true
		_strike()

## The strike frame: lands only if the target is still in reach and in front,
## so stepping back or sideways during the wind-up dodges it.
func _strike() -> void:
	var hit: Node3D = null
	if target and is_instance_valid(target) and not target.downed:
		var to := target.global_position - global_position
		to.y = 0.0
		var in_front := to.length() < 0.5 or (-global_transform.basis.z).dot(to.normalized()) > 0.3
		if to.length() < data["reach"] + 0.35 and in_front and _clear_line(target) and _can_strike(target):
			hit = target
	_rpc_swipe.rpc()
	if hit == null:
		return
	_mark_struck(hit)
	_recoil_t = 0.35
	if data.get("pins") and not hit.pinned:
		_pinned = hit
		state = S.PINNING
		_set_pinned.rpc(hit.get_path(), true)
		return
	_rpc_hurt_player.rpc(hit.get_path(), data["dmg"])
	if data.get("ignites"):
		_ignite.rpc(hit.get_path())
	if data.get("ankle_grab"):
		_slow_player.rpc(hit.get_path(), 1.5)

## Nothing solid between this one and the survivor: a wall, a door, a
## shelf. Two lines, at the knees and the chest, so a counter or a low crate
## doesn't stop a swing over it, and a crawler still reaches her legs.
func _clear_line(to: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	for h in [0.5, 1.3]:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * h, to.global_position + Vector3.UP * h, 1 | Door.BARS_LAYER)
		q.exclude = [get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false

func _can_strike(p: Node) -> bool:
	return Time.get_ticks_msec() - int(p.get_meta("struck_ms", -100000)) >= GRACE_MS and not p.get("dodging")

func _mark_struck(p: Node) -> void:
	p.set_meta("struck_ms", Time.get_ticks_msec())

@rpc("authority", "unreliable", "call_local")
func _rpc_swipe() -> void:
	if data.get("quadruped"):
		return   # the snap is in its attack snarl
	Sfx.play_at("brute_slam" if variant == "brute" else "zombie_swipe", global_position + Vector3.UP * 1.2 - global_transform.basis.z * 0.5, "", 0.0, 3.5)

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
	# Riot shield: blocks hits from the front (not the legs, and not while
	# he's reeling). Every blocked hit cracks it; it breaks off after about
	# four pistol rounds, one or two shotgun blasts or two hatchet blows.
	if _shield_hp > 0.0 and zone != "leg" and state != S.STAGGER and (-global_transform.basis.z).dot(-dir) > 0.35 and not Cheats.on("one_hit_kills"):
		var sdmg := dmg * (1.6 if w.get("kind") == "melee" else 1.0)
		_shield_hp -= sdmg
		if _shield_hp <= 0.0:
			_shield_hp = 0.0
			_shield_break.rpc()
			_set_stagger(1.3)
			_poise_t = POISE
		else:
			_shield_block.rpc(1.0 - _shield_hp / float(data.get("shield_hp", 100.0)))
			if w.get("stagger", 0.0) > 0 and state == S.ATTACK:
				_set_stagger(0.5)   # a heavy blow on the shield knocks his swing off
		return
	var total: float = dmg * EnemyDB.ZONE_MULT.get(zone, 1.0)
	hp -= total
	var flat_v := Vector3(velocity.x, 0.0, velocity.z)
	var lying := state == S.PLAY_DEAD   # lying there, or still falling in limp
	_last_hit = {"w": weapon_id, "zone": zone, "dir": dir, "dmg": total, "down": lying,
		"rush": flat_v if state in [S.CHASE, S.CHARGE] and flat_v.length() > 2.3 else Vector3.ZERO}
	if lying and hp > 0.0 and _drop_phase != 1:
		_drop_phase = 0
		wake_from_dead()   # shot where it lay and still alive: it gets up (rise)
	if state in [S.IDLE, S.FEED, S.WANDER, S.HIDDEN]:
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
	# Any real hit rocks it: a swing in progress is broken off, a lurch toward
	# you stalls for a beat. Then it shrugs off hits for a moment (POISE), so a
	# knife can buy space but can't pin one in place forever.
	var flinch := false
	if lying:
		pass   # no standing flinch for a body getting up off the floor or still falling
	elif (w.get("stagger", 0.0) > 0 or total > 50) and variant not in ["brute", "brood_mother"]:
		_set_stagger(0.6 + w.get("stagger", 0.0) * 0.6)
		velocity = dir * 1.5
		flinch = true
		_poise_t = POISE
	elif _poise_t <= 0.0 and state != S.STAGGER and _can_flinch(total):
		flinch = true
		_poise_t = POISE
		if state == S.ATTACK:
			_set_stagger(0.5)
		elif state in [S.CHASE, S.CRAWL, S.WANDER]:
			_flinch_t = 0.55
	_rpc_hit_fx.rpc(zone, flinch and hp > 0)
	if hp <= 0:
		_die()

## Flash grenade: blinded and reeling.
func _can_flinch(total: float) -> bool:
	match variant:
		"brood_mother":
			return false
		"brute":
			return total >= 40.0
	return total > 0.0

func flashed(secs: float) -> void:
	if state in [S.DEAD, S.HIDDEN]:
		return
	if state == S.PINNING:
		_release_pin()
	_set_stagger(secs)

func _set_stagger(t: float) -> void:
	if variant == "brood_mother":
		return
	state = S.STAGGER
	_stagger_t = t

func _die() -> void:
	if _pinned:
		_release_pin()
	state = S.DEAD
	_drop_phase = 0
	collision_layer = 0
	for h in _hitboxes:
		h.collision_layer = 0
	GameState.set_flag("dead:" + str(name))
	_rpc_die.rpc(_death_plan())
	var drop := WeaponDB.roll_drop(drop_table, _rng)
	if drop != "none":
		get_parent().spawn_pickup.rpc(drop, global_position + Vector3(0, 0.05, 0), -1)
	if data.get("death_gas"):
		get_parent().spawn_hazard.rpc("acid_gas", global_position, 3.2, 6.0)

# ---------------------------------------------------------------- dying

## Clip speed per death (the choke and the writhing are long as authored).
const DEATH_SPEED := {"choke": 1.7, "convulse": 1.4, "slow_back": 1.25, "back_shot": 1.25, "headshot": 1.25}
## Deaths that go where they're pushed: twisted so the body falls along the
## shot. The rest fold up where they stand.
const DEATH_PUSHED := ["fall_back", "slow_back", "sit_back", "blown_back", "flip", "back_shot", "sweep"]

## How this one goes down (host). The killing blow picks the kind of death:
## where the round came from, the weapon, the body part, what it was doing
## and what it is. The body twists toward the push (a side hit spins it), and
## the fall is checked against the walls and the floor: a fall that would put
## its head through a wall or off a ledge is turned, shortened, or swapped for
## one that folds up on the spot. Both phones play the same plan
## (ZombieModel.die).
func _death_plan() -> Dictionary:
	if data.get("quadruped"):
		# The hound: cut down at a gallop its legs fold under it; otherwise
		# it rolls onto one side or the other.
		var rushing_dog: bool = _last_hit.get("rush", Vector3.ZERO) != Vector3.ZERO
		return {"c": "death_collapse" if rushing_dog else ("death" if _rng.randf() < 0.5 else "death_left"),
			"s": _rng.randf_range(0.95, 1.1)}
	var clips := model.death_clips()
	if clips.is_empty():
		return {"y": _rng.randf_range(-1.0, 1.0)}
	var h := _last_hit
	var wid: String = h.get("w", "")
	var w: Dictionary = WeaponDB.WEAPONS.get(wid, {})
	var kind: String = w.get("kind", "")
	var zone: String = h.get("zone", "torso")
	var dir: Vector3 = h.get("dir", Vector3.ZERO)
	dir.y = 0.0
	var push_dir := (global_transform.basis.inverse() * dir).normalized() if dir.length() > 0.01 else Vector3.ZERO
	push_dir.y = 0.0
	# The round travels toward +Z (local) when it comes from in front of it.
	var from_back := push_dir.z < -0.35
	var blast: bool = w.has("radius") or wid == "frag" or (wid != "" and not WeaponDB.WEAPONS.has(wid))
	var burning := has_node("Burning") or kind == "flame"
	var shooter := _nearest_player()
	var near := global_position.distance_to(shooter.global_position) if shooter else 99.0
	var rush: Vector3 = h.get("rush", Vector3.ZERO)   # how fast it was coming on when it died
	var rushing := rush != Vector3.ZERO
	var heavy := variant in ["brute", "bloater", "brood_mother"]
	# Already lying there (playing dead): it just stays down.
	if h.get("down", false):
		var lying := model.lying_clip()
		if lying != "":
			return {"c": lying, "from": maxf(model.death_length(lying) - 0.05, 0.0), "k": 1.0}
	# On its belly (crawler, or legs shot out): it slumps flat where it is.
	if crippled or data.get("crawl"):
		return {"c": "knees_face", "from": maxf(model.death_land("knees_face") - 0.35, 0.0), "k": 0.0,
			"y": _rng.randf_range(-0.25, 0.25), "s": 0.9}
	# (fall_back is not in any of these: its arms fly out level with the
	# shoulders as it topples, which reads as a T-pose. It is kept only as a
	# pose for infected lying in wait.)
	var pool := {}
	if blast:
		pool = {"flip": 3.0, "blown_back": 3.0, "sweep": 1.0}
	elif burning:
		pool = {"convulse": 4.0, "knees_face": 1.0, "gut": 1.0}
	elif kind == "pellets" and near < 6.0 and not from_back:
		pool = {"blown_back": 3.0, "flip": 1.0, "sit_back": 1.0, "sweep": 1.0}
	elif from_back:
		pool = {"back_shot": 3.0, "knees_face": 2.0, "headshot": 1.5 if zone == "head" else 0.0}
	elif rushing:
		# Shot dead mid-lunge: its own momentum carries it down onto its face.
		pool = {"knees_face": 3.0, "headshot": 2.0 if zone == "head" else 0.0, "sweep": 1.0}
	elif zone == "head":
		pool = {"headshot": 4.0, "slow_back": 1.0, "sit_back": 1.0, "knees_face": 1.0}
	elif zone == "leg":
		pool = {"sweep": 3.0, "knees_face": 2.0, "gut": 1.0}
	elif kind == "melee":
		# A knife opens the throat or the gut; a hatchet chops it down.
		pool = {"gut": 2.0, "knees_face": 2.0, "choke": 1.0 if wid == "knife" else 0.0, "sit_back": 1.0, "sweep": 1.0 if wid == "hatchet" else 0.0}
	else:
		pool = {"slow_back": 2.0, "sit_back": 2.0, "gut": 2.0, "knees_face": 2.0, "headshot": 1.0, "choke": 0.6}
	# The big ones don't somersault; a screamer grabs at its throat; a
	# spitter folds over its swollen gut.
	if heavy and not (blast and float(h.get("dmg", 0.0)) >= 300.0):
		for c in ["flip", "blown_back", "sweep"]:
			pool.erase(c)
		pool["knees_face"] = pool.get("knees_face", 0.0) + 2.0
		pool["gut"] = pool.get("gut", 0.0) + 1.0
	if variant == "screamer" and not blast:
		pool["choke"] = pool.get("choke", 0.0) + 3.0
	if variant == "spitter" and not blast:
		pool["gut"] = pool.get("gut", 0.0) + 2.0
	# Hit from the side: it spins as it goes down (the deaths that follow
	# the push turn it toward where the round was going).
	if absf(push_dir.x) > 0.7 and not blast:
		for c in pool:
			if c in DEATH_PUSHED:
				pool[c] *= 2.5
	for c in pool.keys():
		if not c in clips or pool[c] <= 0.0:
			pool.erase(c)
		elif c in _recent_deaths:
			pool[c] *= 0.2
	if pool.is_empty():
		pool = {"knees_face": 1.0}
	# A blast throws it, a shotgun at arm's length shoves it, a runner's own
	# speed carries it on.
	var push := Vector3.ZERO
	if blast and push_dir != Vector3.ZERO:
		push = push_dir * clampf(float(h.get("dmg", 100.0)) / 140.0, 0.4, 1.6)
	elif kind == "pellets" and near < 4.0 and push_dir != Vector3.ZERO:
		push = push_dir * 0.3
	elif rushing:
		push = (global_transform.basis.inverse() * rush).normalized() * 0.6
		push.y = 0.0
	push = _room_along(push)
	var speed_k := (0.85 if variant == "brute" else 0.92 if variant == "bloater" else 1.0) * _rng.randf_range(0.92, 1.1)
	var order := _weighted_order(pool)
	var yaw0 := {}
	for c in order:
		yaw0[c] = _rng.randf_range(-0.35, 0.35)
		var fall := model.death_fall(c)
		var toward := push_dir if push_dir != Vector3.ZERO else push.normalized()
		if c in DEATH_PUSHED and fall != Vector3.ZERO and toward != Vector3.ZERO:
			var ang := fall.signed_angle_to(toward, Vector3.UP)
			if absf(ang) < 2.4:
				yaw0[c] = clampf(ang, -1.25, 1.25) + _rng.randf_range(-0.15, 0.15)
	# Any of the deaths that fit, as it falls naturally; then turned a little
	# more, or cut short; a big twist only as a last resort. (Never spun
	# right round: a wall at its back makes it fold up toward you instead.)
	var best := {}
	var best_blocked := 1 << 20
	var tries := 0
	for turn in [[0.0], [0.55, -0.55], [1.1, -1.1]]:
		for c in order:
			var fall := model.death_fall(c)
			for dy in turn:
				for k in ([1.0, 0.65, 0.35] if fall != Vector3.ZERO else [1.0]):
					# A few dozen looks at most (a grenade in a corridor kills
					# five at once on a phone).
					tries += 1
					if tries > 30:
						break
					var plan := {"c": c, "y": clampf(yaw0[c] + dy, -1.7, 1.7), "k": k, "p": push,
						"s": DEATH_SPEED.get(c, 1.0) * speed_k}
					var blocked := _death_blocked(plan)
					if blocked == 0:
						_remember_death(c)
						return plan
					if blocked < best_blocked:
						best_blocked = blocked
						best = plan
	# Nothing lies fully clear (a cupboard of a room): fold up on the spot.
	var tight := {"c": "gut" if "gut" in clips else best.get("c", "knees_face"), "y": _rng.randf_range(-0.4, 0.4), "k": 0.4, "p": Vector3.ZERO, "s": speed_k}
	if _death_blocked(tight) <= best_blocked:
		best = tight
	_remember_death(best.get("c", ""))
	return best

## How many of the body's resting points (head, hands, feet, hips, chest)
## would end up in a wall, a car or a shelf, or over a drop, for a plan. Also
## sets the plan's floor step ("f") from the floor under the hips.
func _death_blocked(plan: Dictionary) -> int:
	var pts := model.death_points(plan["c"], plan.get("y", 0.0), plan.get("k", 1.0), plan.get("p", Vector3.ZERO))
	if pts.is_empty():
		return 0
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3.UP * 0.9
	var blocked := 0
	var floor_dy := 0.0
	for i in pts.size():
		var at: Vector3 = global_transform * pts[i]
		var q := PhysicsRayQueryParameters3D.create(chest, at + Vector3.UP * 0.22, 1 | Door.BARS_LAYER)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			blocked += 1
			continue
		if i < 2:   # head and hips: is there floor under them, not a drop?
			var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 1.2, 1)
			down.exclude = [get_rid()]
			var hit := space.intersect_ray(down)
			if hit.is_empty() or (hit.position as Vector3).y < global_position.y - 0.55:
				blocked += 2
			elif i == 1:
				floor_dy = clampf((hit.position as Vector3).y - global_position.y, -0.5, 0.5)
	plan["f"] = floor_dy
	return blocked

## A push shortened so it stops short of a wall.
func _room_along(push: Vector3) -> Vector3:
	if push.length() < 0.01:
		return Vector3.ZERO
	var world_dir := global_transform.basis * push.normalized()
	var from := global_position + Vector3.UP * 0.8
	var q := PhysicsRayQueryParameters3D.create(from, from + world_dir * (push.length() + 0.7), 1 | Door.BARS_LAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return push
	return push.normalized() * maxf(from.distance_to(hit.position) - 0.7, 0.0)

## The pool's clips, most likely first (a weighted shuffle).
func _weighted_order(pool: Dictionary) -> Array:
	var keyed := []
	for c in pool:
		# Exponential race: smaller key wins, more weight means smaller keys.
		keyed.append([-log(maxf(_rng.randf(), 0.0001)) / float(pool[c]), c])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for e in keyed:
		out.append(e[1])
	return out

static func _remember_death(c: String) -> void:
	_recent_deaths.append(c)
	while _recent_deaths.size() > 3:
		_recent_deaths.pop_front()

@rpc("authority", "reliable", "call_local")
func _rpc_scream() -> void:
	model.play_once("scream", 0.1)

@rpc("authority", "reliable", "call_local")
func _rpc_die(plan := {}) -> void:
	state = S.DEAD
	model.die(head_gone, plan)
	if Sfx.voice(_sound_id("death"), self, 0.0, 3.0, 26.0) == null:
		Sfx.voice("zombie_death", self, 0.0, 3.0, 26.0)
	if data.get("death_gas"):
		Sfx.play_at("bloater_burst", global_position, "", 6.0, 12.0)

@rpc("authority", "unreliable", "call_local")
func _rpc_hit_fx(zone: String, flinch := false) -> void:
	model.hit_react(zone, flinch)
	Sfx.play_at("flesh_hit", global_position + Vector3.UP * (0.55 if data.get("quadruped") else 1.0), "", -4.0, 6.0)
	if flinch and data.get("quadruped") and state != S.DEAD:
		Sfx.voice("hound_hurt", self, 2.0, 3.0, 24.0)

@rpc("authority", "unreliable", "call_local")
func _shield_block(cracked: float) -> void:
	Sfx.play_at("shield_ricochet", global_position + Vector3.UP * 1.2, "", 0.0, 10.0)
	Effects.impact(global_position + Vector3.UP * 1.2 - global_transform.basis.z * 0.4, -global_transform.basis.z, null)
	model.crack_shield(cracked)
	if not GameState.has_flag("tip:riot_shield"):
		GameState.set_flag("tip:riot_shield")
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("The shield is cracking. Keep shooting it, or aim for his legs.")

@rpc("authority", "reliable", "call_local")
func _shield_break() -> void:
	_shield_hp = 0.0
	Sfx.play_at("glass_break", global_position + Vector3.UP * 1.2, "shield_ricochet", 4.0, 12.0)
	model.drop_shield()

@rpc("authority", "unreliable", "call_local")
func _groan(kind: String) -> void:
	Sfx.voice(kind, self, 3.0 if kind.ends_with("alert") or kind.ends_with("attack") else 0.0, 3.5 if kind.ends_with("alert") or kind.ends_with("attack") else 2.5, 30.0 if variant == "brute" else 24.0)
