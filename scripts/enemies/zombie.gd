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
	if not multiplayer.is_server() or state == S.DEAD:
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
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()

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
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * h, to.global_position + Vector3.UP * h, 1)
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
	# Any real hit rocks it: a swing in progress is broken off, a lurch toward
	# you stalls for a beat. Then it shrugs off hits for a moment (POISE), so a
	# knife can buy space but can't pin one in place forever.
	var flinch := false
	if (w.get("stagger", 0.0) > 0 or total > 50) and variant not in ["brute", "brood_mother"]:
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
	_rpc_hit_fx.rpc(zone, flinch)
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
func _rpc_scream() -> void:
	model.play_once("scream", 0.1)

@rpc("authority", "reliable", "call_local")
func _rpc_die() -> void:
	state = S.DEAD
	model.die(head_gone)
	if Sfx.voice(_sound_id("death"), self, 0.0, 3.0, 26.0) == null:
		Sfx.voice("zombie_death", self, 0.0, 3.0, 26.0)
	if data.get("death_gas"):
		Sfx.play_at("bloater_burst", global_position, "", 6.0, 12.0)

@rpc("authority", "unreliable", "call_local")
func _rpc_hit_fx(zone: String, flinch := false) -> void:
	model.hit_react(zone, flinch)
	Sfx.play_at("flesh_hit", global_position + Vector3.UP, "", -4.0, 6.0)

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
