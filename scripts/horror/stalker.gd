class_name Stalker
extends CharacterBody3D
## The Tallyman: a towering figure in a sealed black rubber coat and a riveted
## respirator mask, dragging a hooked iron archive pole. He was the Archive's
## night keeper; now he walks the building counting the living.
## He cannot be killed: enough damage drops him to one knee for a few seconds.
## Heavy footsteps carry through walls. He does not run; he does not need to.
## He follows them through an open door. A shut one keeps him out: he waits
## outside it, breathing, then loses the scent and walks back to where he
## came in, and picks the hunt up again once someone is out where he can get
## at them. Host-simulated.

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
## How long he waits outside a door someone shut themselves in behind.
const LINGER := 9.0

var _home := Vector3.ZERO
var _lost_t := 0.0
var _reach_t := 0.0
var _reach: Dictionary = {}   # player -> can he walk to them (every 0.5 s)

## He mutters while he hunts. Breathing and speech never overlap: the breath
## loop stops while he talks and comes back after a short pause.
const LINES := [
	{"id": "tally_count", "text": "...forty-one... forty-two..."},
	{"id": "tally_ledger", "text": "Another one for the ledger."},
	{"id": "tally_number", "text": "Every name gets a number."},
	{"id": "tally_closed", "text": "The Archive is closed. You are late."},
	{"id": "tally_found", "text": "There you are."},
]
var _breath: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _talk_cd := 10.0
var _speaking := false

func _ready() -> void:
	add_to_group("stalker")
	collision_layer = 4
	collision_mask = 1 | 2 | Door.BARS_LAYER
	# His body is shorter than he is (2.45 m): at 2.5 m he couldn't get under
	# a 2.3-2.4 m door head and stood stuck in the clock gallery's doorway.
	# He stoops under them instead (_stoop).
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.2
	cs.shape = cap
	cs.position.y = 1.1
	add_child(cs)
	_model = _build_model()
	add_child(_model)
	_breath = AudioStreamPlayer3D.new()
	_breath.bus = "SFX"
	_breath.unit_size = 5.0
	_breath.max_distance = 16.0
	_breath.position.y = 2.2
	if ResourceLoader.exists("res://assets/audio/sfx/stalker_breath.ogg"):
		var st: AudioStream = load("res://assets/audio/sfx/stalker_breath.ogg").duplicate()
		if st is AudioStreamOggVorbis:
			st.loop = true
		_breath.stream = st
	add_child(_breath)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "Voice"
	_voice.unit_size = 9.0
	_voice.max_distance = 26.0
	_voice.position.y = 2.2
	_voice.finished.connect(_voice_done)
	add_child(_voice)
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
	# Close to each corner of the path: cutting one a metre early walked him
	# into the jamb of a doorway and he stood there pushing.
	_agent.path_desired_distance = 0.35
	_agent.target_desired_distance = 0.6
	_agent.link_reached.connect(_on_link_reached)
	add_child(_agent)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":active"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	add_child(sync)
	visible = active
	_home = position

func _build_model() -> Node3D:
	var path := "res://assets/characters/tallyman/tallyman.glb"
	if ResourceLoader.exists(path):
		# Rigged model with his clips and the hooked pole (scripts/story/story_actor.gd).
		return StoryActor.new("tallyman")
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
	leaving = false
	visible = true
	global_position = at
	_home = at
	_lost_t = 0.0
	_link_exit = Vector3.INF
	if _breath.stream:
		_breath.play()

## Done hunting for now (host): he turns his back on them and walks off to
## `to`; the story puts him away once nobody can see him (Chapter2Story).
var leaving := false
var _leave_to := Vector3.ZERO

func leave(to: Vector3) -> void:
	leaving = true
	_leave_to = to

## Gone for now (chapter 2 after the Warden scene): every phone runs this
## itself from the story, so it needs no RPC.
func deactivate() -> void:
	active = false
	leaving = false
	visible = false
	velocity = Vector3.ZERO
	if _breath:
		_breath.stop()
	if _voice:
		_voice.stop()

## Host picks a line; every peer plays it with the breath loop muted.
@rpc("authority", "reliable", "call_local")
func say(index: int) -> void:
	var line: Dictionary = LINES[index % LINES.size()]
	var path := "res://assets/audio/voice/tallyman/%s.ogg" % line["id"]
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_subtitle("The Tallyman", line["text"], 3.0)
	if not ResourceLoader.exists(path):
		return
	_speaking = true
	var t := create_tween()
	t.tween_property(_breath, "volume_db", -60.0, 0.25)
	t.tween_callback(_breath.stop)
	t.tween_callback(func():
		_voice.stream = load(path)
		_voice.play())

func _voice_done() -> void:
	_speaking = false
	await get_tree().create_timer(0.6).timeout
	if active and not _speaking and _breath.stream:
		_breath.volume_db = 0.0
		_breath.play()

var _last_pos := Vector3.ZERO
var _anim_state := ""

## Walk or stand, from how far he actually moved (the same on every phone).
func _animate(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos) / maxf(delta, 0.001)
	_last_pos = global_position
	if not (_model is StoryActor) or _anim_state in ["attack", "hit"]:
		return
	var want := "stalk" if moved > 0.3 else "idle"
	if want != _anim_state:
		_anim_state = want
		_model.play(want, 0.35)

func _physics_process(delta: float) -> void:
	visible = active
	if not active:
		return
	_animate(delta)
	_stoop(delta)
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
	if leaving:
		_walk_to(_leave_to, delta)
		return
	_reach_t -= delta
	if _reach_t <= 0.0:
		_reach_t = 0.5
		_reach.clear()
		for p in get_tree().get_nodes_in_group("players"):
			_reach[p] = _can_reach(p)
	var hunted := _nearest()
	target = null
	if hunted and _reach.get(hunted, true):
		target = hunted
	else:
		# Whoever he's after is shut in behind a door: someone he can get to
		# instead, or wait outside a while and then give up.
		for p in _reach:
			if is_instance_valid(p) and _reach[p] and _huntable(p) and (target == null or global_position.distance_to(p.global_position) < global_position.distance_to(target.global_position)):
				target = p
	if target == null:
		_lost_t += delta
		if hunted and _lost_t < LINGER:
			_walk_to(hunted.global_position, delta)
		elif global_position.distance_to(_home) > 0.8:
			_walk_to(_home, delta)
		else:
			velocity = Vector3(0, velocity.y - 18.0 * delta, 0)
			move_and_slide()
		return
	_lost_t = 0.0
	var d := global_position.distance_to(target.global_position)
	_talk_cd -= delta
	if _talk_cd <= 0.0 and not _speaking and d < 22.0:
		_talk_cd = randf_range(14.0, 26.0)
		say.rpc(4 if d < 6.0 else randi() % 4)
	if d < 1.8 and _attack_cd <= 0:
		_attack_cd = 2.2
		_swing.rpc(target.get_path())
	_walk_to(target.global_position, delta)

## Ducks his head under a door head or a low pipe (every phone, from where he
## is): the model shrinks a touch towards the floor so his feet stay put.
var _stoop_k := 1.0

func _stoop(delta: float) -> void:
	if _model == null:
		return
	var want := 1.0
	var fwd := -global_transform.basis.z
	var space := get_world_3d().direct_space_state
	for ahead: float in [0.0, 0.35]:
		var from: Vector3 = global_position + fwd * ahead + Vector3.UP * 1.4
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 1.15, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var room: float = hit["position"].y - global_position.y
			want = minf(want, clampf((room - 0.05) / 2.45, 0.86, 1.0))
	_stoop_k = move_toward(_stoop_k, want, delta * 0.8)
	_model.scale = Vector3.ONE * _stoop_k

## Through an open doorway (Door's navmesh link) he keeps on to the far side:
## re-pathing from inside the doorway, which isn't navmesh, snapped him back
## to the near side and he stood in it (as the infected did, Zombie).
var _link_exit := Vector3.INF
var _link_t := 0.0

func _on_link_reached(details: Dictionary) -> void:
	_link_exit = details.get("link_exit_position", Vector3.INF)
	_link_t = 3.0

func _walk_to(goal: Vector3, delta: float) -> void:
	var next: Vector3
	if _link_exit != Vector3.INF:
		_link_t -= delta
		var left := Vector2(_link_exit.x - global_position.x, _link_exit.z - global_position.z).length()
		if _link_t <= 0.0 or left < 0.3:
			_link_exit = Vector3.INF
	if _link_exit != Vector3.INF:
		next = _link_exit
	else:
		_agent.target_position = goal
		next = _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity = Vector3(dir.x * SPEED, velocity.y - 18.0 * delta, dir.z * SPEED)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 3 * delta)
	else:
		velocity = Vector3(0, velocity.y - 18.0 * delta, 0)
	move_and_slide()

## Whether the navmesh takes him to `p`: an open door's link takes him
## through it (Door.NAV_REACH), a shut one cuts him off from whoever is on
## the far side.
func _can_reach(p: Node3D) -> bool:
	var to := p.global_position
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, to, true)
	if path.is_empty():
		return false
	var end: Vector3 = path[path.size() - 1]
	return Vector2(end.x - to.x, end.z - to.z).length() < 1.2 and absf(end.y - to.y) < 1.2

func _huntable(p: Node) -> bool:
	return not p.downed and not _in_safe_room(p)

func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("players"):
		var dd := global_position.distance_to(p.global_position)
		if dd < bd and _huntable(p):
			bd = dd
			best = p
	return best

## Safe rooms stop him (docs/lore.md): whoever is inside one isn't hunted.
func _in_safe_room(p: Node) -> bool:
	for c in get_tree().get_nodes_in_group("checkpoints"):
		if c.is_safe_room and c.holds(p):
			return true
	return false

@rpc("authority", "reliable", "call_local")
func _swing(path: NodePath) -> void:
	Sfx.play_at("stalker_swing", global_position + Vector3.UP * 1.5, "", 4.0, 12.0)
	_one_shot("attack", 1.6)
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

var _kneel_tw: Tween

@rpc("authority", "reliable", "call_local")
func _kneel() -> void:
	Sfx.play_at("stalker_kneel", global_position, "", 4.0, 14.0)
	_one_shot("hit", 4.0)
	# Down on his knee he's no wall: a survivor he backed into a corner (the
	# fuel shed's front corner, against its gas bottle, left no way past his
	# shoulders) can get out past him. He's solid again as he rises.
	_pass_survivors(true)
	if _kneel_tw:
		_kneel_tw.kill()
	_kneel_tw = create_tween()
	_kneel_tw.tween_property(_model, "position:y", -0.5, 0.4)
	_kneel_tw.tween_interval(3.4)
	_kneel_tw.tween_callback(_pass_survivors.bind(false))
	_kneel_tw.tween_property(_model, "position:y", 0.0, 0.6)

## Survivors walk through him (on), or bump into him again (off). Both
## bodies get the exception: each one's own move checks its own list.
func _pass_survivors(on: bool) -> void:
	for b in get_collision_exceptions():
		remove_collision_exception_with(b)
	for p in get_tree().get_nodes_in_group("players"):
		if on:
			add_collision_exception_with(p)
			p.add_collision_exception_with(self)
		else:
			p.remove_collision_exception_with(self)

func hear_noise(_pos: Vector3) -> void:
	pass

func _one_shot(clip: String, hold: float) -> void:
	if not (_model is StoryActor):
		return
	_anim_state = clip
	_model.play(clip, 0.15)
	get_tree().create_timer(hold).timeout.connect(func(): _anim_state = "")
