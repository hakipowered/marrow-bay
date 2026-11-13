class_name HorrorDirector
extends Node
## Runs the dread: layered ambience, distant city sounds, scripted scares,
## lights failing, and tension that rises while zombies or the stalker are close.
## Sounds are looked up by id under res://assets/audio/sfx and music/ (missing = silent).

var post_fx: Node
var _amb: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _distant_t := 12.0
var _rng := RandomNumberGenerator.new()
var tension := 0.0
var _boss := ""
var _boss_t := 0.0

const DISTANT := ["distant_scream", "distant_siren", "distant_gunfire", "metal_bang", "glass_far", "dog_howl", "building_creak"]

func _ready() -> void:
	add_to_group("horror")
	_rng.randomize()
	post_fx = preload("res://scripts/horror/post_fx.gd").new()
	add_child(post_fx)
	_amb = _music("ambience_dread")
	_tension = _music("tension_strings")
	if _amb:
		_amb.play()
	if _tension:
		_tension.volume_db = -60.0
		_tension.play()

func _music(id: String) -> AudioStreamPlayer:
	var path := "res://assets/audio/music/%s.ogg" % id
	if not ResourceLoader.exists(path):
		return null
	var a := AudioStreamPlayer.new()
	a.stream = load(path)
	a.bus = "Music"
	add_child(a)
	return a

func _process(delta: float) -> void:
	var me: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			me = p
	if me == null:
		return
	var target := 0.0
	var threat := 0.0
	var boss := ""
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.state in [Zombie.S.DEAD, Zombie.S.HIDDEN, Zombie.S.PLAY_DEAD, Zombie.S.IDLE]:
			continue
		var d := me.global_position.distance_to(z.global_position)
		if d > 35.0:
			continue
		# Music only for danger she can meet: in sight, or right on her. An
		# infected clawing at the other side of a shut gate or a wall isn't a
		# fight yet, and playing one made her look for a threat that wasn't
		# there.
		var near := d < 4.0 or _in_sight(me, z)
		if z.data.get("boss", false) and near:
			boss = z.variant
		if z.state in [Zombie.S.CHASE, Zombie.S.ATTACK, Zombie.S.CHARGE, Zombie.S.PINNING] and near:
			# Ordinary infected only stir the strings a little; the big ones
			# bring them up fully.
			var cap := 1.0 if _threat_weight(z) >= 2.0 else 0.45
			target = max(target, minf(1.0 - d / 14.0, cap))
			if d < 18.0:
				threat += _threat_weight(z)
	for s in get_tree().get_nodes_in_group("stalker"):
		# The Tallyman waits, unseen and asleep, behind the reading-room glass
		# until the story wakes him: only the hunting Tallyman counts.
		if not s.get("active"):
			continue
		var d := me.global_position.distance_to(s.global_position)
		target = max(target, 1.2 - d / 20.0)
		if d < 12.0:
			threat += 6.0   # the Tallyman on you is always a fight
	Music.threat = threat
	# A boss ducking behind a pillar keeps its theme for a few seconds.
	if boss != "":
		_boss = boss
		_boss_t = 6.0
	else:
		_boss_t -= delta
		if _boss_t <= 0.0:
			_boss = ""
	Music.boss = _boss
	tension = move_toward(tension, clamp(target, 0.0, 1.0), delta * 0.4)
	if _tension:
		# The strings step aside once the action or boss music takes over.
		var duck := 0.25 if Music.current_track() in [Music.FIGHT_TRACK, "boss_1", "boss_2"] and Music.current_track() != "" else 1.0
		_tension.volume_db = linear_to_db(max(tension * duck, 0.001)) - 8.0
	# Distant city: something terrible is always happening somewhere else.
	_distant_t -= delta
	if _distant_t <= 0.0:
		_distant_t = _rng.randf_range(14.0, 35.0)
		var dir := Vector3(_rng.randf_range(-1, 1), 0.2, _rng.randf_range(-1, 1)).normalized()
		Sfx.play_at(DISTANT[_rng.randi() % DISTANT.size()], me.global_position + dir * 25.0, "", -6.0, 30.0)

## A clear line from her chest to the infected's (world geometry and the
## gate's bars block it; other bodies don't).
func _in_sight(me: Node3D, z: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3.UP * 1.4, z.global_position + Vector3.UP * 1.3, 1 | Door.BARS_LAYER)
	q.exclude = [me.get_rid(), z.get_rid()]
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## How much one chasing infected counts toward the action music
## (Music.ACTION_ON = 6: a brute and two more, or six ordinary ones).
func _threat_weight(z: Node) -> float:
	var d: Dictionary = z.data
	if d.get("charge") or d.get("bulk", 1.0) >= 1.5:
		return 4.0
	if d.get("pins"):
		return 2.5
	if d.get("lunge") or d.get("ceiling_drop"):
		return 1.5
	if d.get("tiny"):
		return 0.4
	return 1.0

func run_scare(t: ScareTrigger) -> void:
	match t.kind:
		"stinger":
			_stinger()
		"lights_out":
			_lights_out(t.room, t.duration)
		"body_drop":
			_body_drop(t.target)
		"window_break":
			_window_break(t)
		"door_bang":
			_door_bang(t.target)
		"whisper":
			Sfx.play_at("whisper", t.target, "", -2.0, 6.0)
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and t.text != "":
				hud.show_subtitle("", t.text, 3.0)
			post_fx.spike(0.4)
		"wake_dead":
			for z in get_tree().get_nodes_in_group("zombies"):
				if z.is_in_group(t.group) and multiplayer.is_server():
					z.wake_from_dead()

func _stinger() -> void:
	var path := "res://assets/audio/music/stinger_%d.ogg" % (_rng.randi_range(1, 4))
	if ResourceLoader.exists(path):
		var a := AudioStreamPlayer.new()
		a.stream = load(path)
		a.bus = "Music"
		add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	post_fx.spike(0.9)

func _lights_out(room: String, duration: float) -> void:
	var r := get_parent().get_node_or_null(room)
	if r == null:
		return
	var lights: Array = r.find_children("*", "Light3D", true, false)
	Sfx.play_at("power_down", r.global_position + Vector3(3, 2, 3), "", 0.0, 20.0)
	var saved := {}
	for l in lights:
		saved[l] = l.light_energy
		l.light_energy = 0.0
		l.set_process(false)
	post_fx.spike(0.6)
	await get_tree().create_timer(duration).timeout
	# Sputter back on.
	for i in 5:
		for l in lights:
			if is_instance_valid(l):
				l.light_energy = saved[l] * (1.0 if i % 2 == 0 else 0.1)
		await get_tree().create_timer(_rng.randf_range(0.05, 0.25)).timeout
	for l in lights:
		if is_instance_valid(l):
			l.light_energy = saved[l]
			l.set_process(true)

func _body_drop(at: Vector3) -> void:
	var body := ZombieModel.new()
	body.variant = "civilian"
	get_parent().add_child(body)
	body.global_position = at + Vector3(0, 2.6, 0)
	Sfx.play_at("body_fall", at, "", 4.0, 10.0)
	var t := body.create_tween()
	t.tween_property(body, "global_position:y", at.y + 0.1, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(body, "rotation:x", -PI / 2, 0.35)
	_stinger()

func _window_break(t: ScareTrigger) -> void:
	Sfx.play_at("glass_break", t.target, "", 6.0, 14.0)
	Effects.impact(t.target, Vector3.UP, null)
	post_fx.spike(0.8)
	if t.spawn_count >= 5:   # a real horde, not two or three through a window
		Music.force_action(20.0 + t.spawn_count * 4.0)
	if multiplayer.is_server():
		var level := get_parent()
		for i in t.spawn_count:
			await get_tree().create_timer(0.8 + i * 1.2).timeout
			level.spawn_zombie_synced.rpc("%s_w%d" % [t.scare_id, i], t.target + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5)))

func _door_bang(at: Vector3) -> void:
	for i in 6:
		Sfx.play_at("door_bang", at, "metal_bang", 4.0, 14.0)
		post_fx.spike(0.15)
		await get_tree().create_timer(_rng.randf_range(0.3, 0.9)).timeout
