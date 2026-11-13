class_name Chapter2Story
extends Node3D
## Story for chapter 2, "The Count": the Undercroft (scripts/levels/undercroft.gd).
##
## The lift stops at the service level and its doors grind open ("c2_arrival").
## In the engine hall they find the way on, the flood door, dead on its motor,
## and the generator that runs it, dry, without its fuse or its starting
## handle ("c2_hall"). The diesel is in the coal yard's fuel shed. The fuse
## is locked in the master clock in the clock gallery; its winding key is in
## the survey room. Taking the fuse wakes the Tallyman, who comes down the
## back stair and hunts them through the tunnels ("c2_hunt"). With the diesel
## and the fuse in, Warden Hardass comes on the tannoy: the starting handle
## is on his belt, he's in the muster room, he's unbarred the door
## ("c2_intercom"). He has turned by the time they get there ("c2_warden", the
## boss fight, WardenBoss). With the handle off his body they crank the
## generator under attack; it catches, the lights come on, the flood door
## goes up, and in the deep stacks behind it they find Nasri's staff card and
## his chalk on the wall ("c2_end").
##
## Like Chapter1Story: Cutscenes asks cutscene(id) for a scene's steps and
## calls on_cutscene_end(id) on every phone when it ends or is skipped, and
## everything a scene changes for good happens there, so skipping is safe.
## The world calls back on every phone: generator_changed(part),
## clock_opened(), warden_died(pos); and on the host: warden_phase_two(),
## warden_kneels().

const SFX := "res://assets/audio/sfx/%s.ogg"
const VOICE := "res://assets/audio/voice/story/%s.ogg"

const OBJ_OUT := "Find a way out of the service tunnels"
const OBJ_HANDLE := "Get the generator's starting handle from Hardass in the muster room, off the service tunnel"
const OBJ_WARDEN := "The Warden has turned: take the starting handle off his belt"
const OBJ_FIT := "Fit the starting handle to the generator in the engine hall"
const OBJ_CRANK := "Crank the generator. Keep the infected off whoever is cranking"
const OBJ_FLOOD := "The flood door is up: go through to the deep stacks"
const OBJ_END := "End of chapter 2. Chapter 3 is coming in a later build"

const HUNT_FROM := Vector3(32.9, 0.0, -8.3)

## Story triggers, checked by the host: a scene starts when a player walks
## into its box, the flag it waits for is set, and nobody is in a fight.
const TRIGGERS := [
	{"id": "c2_hall", "box": [Vector3(39.3, 0.0, 1.5), Vector3(2.8, 3.0, 3.0)], "after": "story_c2_arrival"},
	{"id": "c2_warden", "box": [Vector3(24.2, 0.0, 4.95), Vector3(3.8, 3.0, 2.8)], "after": "story_c2_intercom"},
	{"id": "c2_end", "box": [Vector3(43.8, 0.0, 13.0), Vector3(6.4, 3.0, 5.0)], "after": "c2_flood_open"},
]

var _fired := {}
var _stand_in: CharacterModel
var _scene_bits: Array[Node] = []
var _tally: StoryActor
var _boss: WardenBoss
var _kneel_barked := false
var _bark_player: AudioStreamPlayer

func _ready() -> void:
	add_to_group("story")
	_bark_player = AudioStreamPlayer.new()
	_bark_player.bus = "Voice"
	add_child(_bark_player)
	Cutscenes.all_peers_ready.connect(_on_all_ready)
	if not GameState.has_flag("story_c2_arrival"):
		# They are still in the dark car: black until the scene starts.
		Cutscenes.cover(true)
		get_tree().create_timer(8.0).timeout.connect(func():
			if not Cutscenes.active and not GameState.has_flag("story_c2_arrival"):
				Cutscenes.cover(false))
	_restore.call_deferred()

## A game loaded part way through: the boss back in his room, the handle
## where he dropped it, the objective on the banner.
func _restore() -> void:
	if GameState.has_flag("story_c2_warden") and not GameState.has_flag("c2_warden_dead"):
		_spawn_boss(true)
		_lock_muster(true)
	if GameState.has_flag("c2_warden_dead"):
		_drop_handle(_handle_spot())
	if GameState.has_flag("story_c2_arrival"):
		# A load at the lift checkpoint puts them in the car: the doors were
		# already open when they saved.
		var lift := get_tree().get_first_node_in_group("vault_elevator")
		if lift and not lift.is_open:
			lift.open_on_arrival(false)
		Cutscenes.show_objective()

func _on_all_ready() -> void:
	if multiplayer.is_server() and not GameState.has_flag("story_c2_arrival") and not _fired.has("c2_arrival"):
		_fired["c2_arrival"] = true
		Cutscenes.play("c2_arrival")

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or Cutscenes.active or not Cutscenes.all_ready():
		return
	# The fuse out of the clock: the Tallyman comes.
	if GameState.has_flag("taken:" + MasterClock.FUSE_ID) and not _done("c2_hunt"):
		if _quiet_all():
			_fire("c2_hunt")
		return
	# Diesel and fuse in: Hardass on the tannoy.
	if GeneratorSet.fitted("fuel") and GeneratorSet.fitted("fuse") and not _done("c2_intercom"):
		if _quiet_all("c2_intercom"):
			_fire("c2_intercom")
		return
	for t in TRIGGERS:
		var id: String = t["id"]
		if _done(id) or not GameState.has_flag(t["after"]):
			continue
		var box := AABB(t["box"][0], t["box"][1])
		for p in _players():
			if box.has_point(p.global_position + Vector3.UP * 0.5) and _quiet(p.global_position, id):
				_fire(id)
				return

func _done(id: String) -> bool:
	return _fired.has(id) or GameState.has_flag("story_" + id)

func _fire(id: String) -> void:
	_fired[id] = true
	Cutscenes.play(id)

func _quiet_all(id := "") -> bool:
	for p in _players():
		if not _quiet(p.global_position, id):
			return false
	return true

## Scenes that go ahead with the Tallyman on their heels: he freezes for
## the scene like everything else, and the Warden's scene ends his hunt.
const PAST_STALKER := ["c2_intercom", "c2_warden"]

## No scene while someone is fighting for their life (Chapter1Story._quiet).
func _quiet(at: Vector3, id := "") -> bool:
	for p in _players():
		if p.downed or p.pinned or p.working != "":
			return false
	var space := get_world_3d().direct_space_state
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(at) < 12.0 and z.get("state") in [Zombie.S.CHASE, Zombie.S.ATTACK, Zombie.S.CHARGE, Zombie.S.PINNING]:
			var q := PhysicsRayQueryParameters3D.create(z.global_position + Vector3.UP * 1.2, at + Vector3.UP * 1.2, 1, [z.get_rid()])
			if not space.intersect_ray(q).is_empty():
				continue
			return false
	if id in PAST_STALKER:
		return true
	for s in get_tree().get_nodes_in_group("stalker"):
		if s.active and s.global_position.distance_to(at) < 10.0:
			return false
	return true

# ================================================================== objectives

## What the generator still needs, in words, with where to look once they
## know.
static func gen_objective() -> String:
	var need: Array = []
	if not GeneratorSet.fitted("fuel"):
		need.append("diesel (the coal yard)")
	if not GeneratorSet.fitted("fuse"):
		need.append("its field fuse")
	if not GeneratorSet.fitted("crank"):
		need.append("the starting handle")
	if need.is_empty():
		return OBJ_CRANK
	var list: String = need[0] if need.size() == 1 else ", ".join(need.slice(0, need.size() - 1)) + " and " + need[-1]
	return "Start the generator in the engine hall: it still needs " + list

## generator_changed from GeneratorSet, on every phone.
func generator_changed(part: String) -> void:
	match part:
		"running":
			GameState.set_flag("c2_hunt_over")
			Cutscenes.set_objective(OBJ_FLOOD)
			if multiplayer.is_server():
				_rpc_bark.rpc("obcera", "o_g_lights", "Lights! We've got lights!")
		"crank":
			Cutscenes.set_objective(OBJ_CRANK)
		_:
			# The tannoy scene follows once the second part is in; until
			# then, say what's still missing.
			if not (GeneratorSet.fitted("fuel") and GeneratorSet.fitted("fuse")) or GameState.has_flag("story_c2_intercom"):
				Cutscenes.set_objective(gen_objective())

## The master clock struck and the drawer sprang open (every phone).
func clock_opened() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("The drawer in the clock's plinth sprang open.")

## The generator's first wave (GeneratorSet, host).
func generator_wave(i: int) -> void:
	if i == 0 and multiplayer.is_server():
		_rpc_bark.rpc("zegan", "z_g_come", "Here they come! Keep it turning!")

# ================================================================== the Warden

## Host, from WardenBoss.
func warden_phase_two() -> void:
	_rpc_bark.rpc("zegan", "z_w_shield", "His shield's gone! Get behind him!")

## Host, from WardenBoss.
func warden_kneels() -> void:
	if not _kneel_barked:
		_kneel_barked = true
		_rpc_bark.rpc("obcera", "o_w_down", "He's down! Hit the growth on his back!")

## Every phone, from WardenBoss when he dies: the handle drops off his
## belt, the door unbars.
func warden_died(pos: Vector3) -> void:
	GameState.set_flag("c2_warden_dead")
	var at := pos + Vector3(0.0, 0.05, 0.0)
	GameState.set_flag("c2_handle_at", [at.x, at.y, at.z])
	_drop_handle(at)
	_lock_muster(false)
	Cutscenes.set_objective(OBJ_FIT)
	if multiplayer.is_server():
		_bark_pair()

func _bark_pair() -> void:
	await get_tree().create_timer(2.6).timeout
	_rpc_bark.rpc("zegan", "z_w_rest", "Rest, Warden.")
	await get_tree().create_timer(2.2).timeout
	_rpc_bark.rpc("obcera", "o_w_count", "We'll count ourselves out.")

func _handle_spot() -> Vector3:
	var a = GameState.world_flags.get("c2_handle_at", null)
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Undercroft.WARDEN_SEAT + Vector3(0.0, 0.05, -1.2)

func _drop_handle(at: Vector3) -> void:
	if GameState.has_flag("taken:c2_crank") or GeneratorSet.fitted("crank"):
		return
	var level := get_tree().get_first_node_in_group("level")
	if level and not level.has_node("Pickup_c2_crank"):
		level.place_pickup("key:crank_handle", at, "c2_crank")

func _spawn_boss(awake: bool) -> WardenBoss:
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		return null
	var b: WardenBoss = level.get_node_or_null("Warden")
	if b == null:
		b = WardenBoss.new()
		b.name = "Warden"
		level.add_child(b)
		b.global_position = Undercroft.WARDEN_STAND if awake else Undercroft.WARDEN_SEAT
		b.rotation.y = 0.0
	_boss = b
	if awake:
		if not b.is_in_group("zombies"):
			b.add_to_group("zombies")
		b.awake = true
	return b

## The muster room door: shut and barred for the fight, open after.
func _lock_muster(lock: bool) -> void:
	GameState.set_flag("unlocked:muster_door", not lock)
	for d in get_tree().get_nodes_in_group("doors"):
		if d.door_id == "muster_door":
			if lock and d.is_open:
				d._set_open(false, Vector3.ZERO, true)
			elif not lock and not d.is_open:
				d._set_open(true, Vector3(0, 0, -1), true)

# ================================================================== barks

## A line said in play (no scene): the voice and a subtitle on every phone.
@rpc("authority", "reliable", "call_local")
func _rpc_bark(who: String, line: String, text: String) -> void:
	var path := VOICE % line
	var dur := 2.5
	if ResourceLoader.exists(path):
		_bark_player.stream = load(path)
		_bark_player.play()
		dur = _bark_player.stream.get_length()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_subtitle(who.capitalize(), text, dur + 0.4)

# ================================================================== scenes

func cutscene(id: String) -> Array:
	match id:
		"c2_arrival": return _arrival()
		"c2_hall": return _hall()
		"c2_hunt": return _hunt()
		"c2_intercom": return _intercom()
		"c2_warden": return _warden()
		"c2_end": return _end_scene()
	return []

func on_cutscene_end(id: String) -> void:
	GameState.set_flag("story_" + id)
	_clear_scene_bits()
	match id:
		"c2_arrival":
			GameState.set_flag("c2_arrival")
			var lift := get_tree().get_first_node_in_group("vault_elevator")
			if lift and not lift.is_open:
				lift.open_on_arrival(false)
			_face_players(Vector3(7.0, 0.0, 3.0))
			Cutscenes.set_objective(OBJ_OUT)
		"c2_hall":
			Cutscenes.set_objective(gen_objective())
		"c2_hunt":
			GameState.set_flag("c2_hunt")
			for s in get_tree().get_nodes_in_group("stalker"):
				if not GameState.has_flag("c2_hunt_over"):
					s.activate(HUNT_FROM)
			var door := _door("stair_door")
			if door and not door.is_open:
				door._set_open(true, Vector3(0, 0, 1), false)
			Cutscenes.set_objective(gen_objective())
		"c2_intercom":
			GameState.set_flag("unlocked:muster_door")
			Cutscenes.set_objective(OBJ_HANDLE)
		"c2_warden":
			# The Tallyman lost them down here; the Warden is enough.
			GameState.set_flag("c2_hunt_over")
			for s in get_tree().get_nodes_in_group("stalker"):
				s.deactivate()
			var b := _spawn_boss(false)
			if b:
				b.global_position = Undercroft.WARDEN_STAND
				b.rotation.y = 0.0
				if b.actor and b.actor._anim:
					b.actor._anim.speed_scale = 1.0
					b.actor.play("idle", 0.2)
				_spawn_boss(true)
			_lock_muster(true)
			for p in _players():
				if p.global_position.z < 5.0 and p.global_position.x > 24.0 and p.global_position.x < 28.0:
					p.global_position.z = 5.6
			Cutscenes.set_objective(OBJ_WARDEN)
		"c2_end":
			GameState.set_flag("c2_complete")
			Cutscenes.set_objective(OBJ_END)

func _door(id: String) -> Node:
	for d in get_tree().get_nodes_in_group("doors"):
		if d.door_id == id:
			return d
	return null

## The car stops at B2 in the dark; the doors grind open on the service level.
func _arrival() -> Array:
	var lift := get_tree().get_first_node_in_group("vault_elevator")
	if lift == null:
		return []
	var L := func(x: float, y: float, z: float) -> Vector3: return lift.car_point(Vector3(x, y, z))
	return [
		{"do": "fade", "to": 1.0, "t": 0.0},
		{"do": "call", "fn": "_arrival_stage"},
		{"do": "bars", "on": true, "t": 0.0},
		{"do": "cam", "pos": L.call(-1.45, 1.72, -2.55), "look": L.call(0.25, 1.2, 0.5), "fov": 54.0},
		{"do": "cam", "pos": L.call(-1.35, 1.66, -2.45), "look": L.call(0.2, 1.25, 0.4), "t": 5.0, "block": false},
		{"do": "fade", "to": 0.0, "t": 1.8},
		{"do": "sfx", "file": SFX % "metal_bang_1", "vol": -14.0},
		{"do": "say", "who": "zegan", "line": "z_c2_dead", "text": "Everything's dead down here. Even the lights."},
		{"do": "call", "fn": "_arrival_open"},
		{"do": "shake", "amount": 0.01, "t": 1.6},
		{"do": "wait", "t": 1.4},
		# From the lift pit: the two of them in the red battery light.
		{"do": "cam", "pos": Vector3(4.6, 1.55, 4.7), "look": L.call(0.0, 1.35, -1.2), "fov": 50.0},
		{"do": "cam", "pos": Vector3(4.0, 1.6, 4.3), "look": L.call(0.0, 1.4, -1.2), "fov": 46.0, "t": 5.0, "block": false},
		{"do": "say", "who": "obcera", "line": "o_c2_nasri", "text": "Nasri came down here. Two days ago."},
		{"do": "call", "fn": "_gesture", "args": ["zegan", "call"]},
		{"do": "say", "who": "zegan", "line": "z_c2_trail", "text": "Then he left a trail. Let's find it.", "gap": 0.5},
		# Down the tunnel: red lamps, the dark between them.
		{"do": "cam", "pos": Vector3(6.4, 1.75, 3.0), "look": Vector3(20.0, 1.4, 3.0), "fov": 52.0},
		{"do": "cam", "pos": Vector3(7.6, 1.7, 3.0), "look": Vector3(20.0, 1.35, 3.0), "fov": 48.0, "t": 6.0, "block": false},
		{"do": "chapter", "num": "CHAPTER 2", "name": "THE COUNT", "t": 4.4},
		{"do": "fade", "to": 1.0, "t": 0.7},
	]

func _arrival_stage() -> void:
	var lift := get_tree().get_first_node_in_group("vault_elevator")
	if lift == null:
		return
	var out: Vector3 = lift.car_point(Vector3(0, 0, 2.0))
	_place("zegan", lift.ride_spot(0), out)
	_place("obcera", lift.ride_spot(1), out)

func _arrival_open() -> void:
	var lift := get_tree().get_first_node_in_group("vault_elevator")
	if lift and not lift.is_open:
		lift.open_on_arrival(true)

## The engine hall: the flood door, the generator, what it needs.
func _hall() -> Array:
	return [
		{"do": "call", "fn": "_hall_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		{"do": "cam", "pos": Vector3(41.2, 1.3, 9.8), "look": Vector3(47.5, 1.3, -1.0), "fov": 56.0},
		{"do": "cam", "pos": Vector3(42.0, 1.5, 9.4), "look": Vector3(47.5, 1.4, -1.0), "fov": 52.0, "t": 5.0, "block": false},
		{"do": "say", "who": "zegan", "line": "z_c2_gen", "text": "A generator. Older than both of us."},
		{"do": "cam", "pos": Vector3(46.0, 1.7, 5.6), "look": Vector3(46.0, 2.1, 12.0), "fov": 54.0},
		{"do": "cam", "pos": Vector3(46.0, 1.7, 6.4), "look": Vector3(46.0, 2.3, 12.0), "fov": 50.0, "t": 4.0, "block": false},
		{"do": "say", "who": "obcera", "line": "o_c2_door", "text": "That door's the way on. And it runs on a motor."},
		{"do": "cam", "pos": Vector3(49.6, 1.35, 2.1), "look": Vector3(48.2, 1.05, 0.3), "fov": 44.0},
		{"do": "say", "who": "zegan", "line": "z_c2_needs", "text": "Then we start this. Dry tank, no fuse, no starting handle."},
		{"do": "cam", "pos": Vector3(43.0, 1.6, 4.6), "look": Vector3(40.6, 1.45, 3.1), "fov": 46.0},
		{"do": "call", "fn": "_gesture", "args": ["obcera", "call"]},
		{"do": "say", "who": "obcera", "line": "o_c2_shopping", "text": "So we go looking. Down here. Great."},
		{"do": "wait", "t": 0.5},
		{"do": "fade", "to": 1.0, "t": 0.6},
	]

func _hall_stage() -> void:
	_place("zegan", Vector3(40.4, 0.0, 2.5), Vector3(47.5, 0.0, -1.0))
	_place("obcera", Vector3(40.6, 0.0, 3.7), Vector3(46.0, 0.0, 12.0))

## The fuse comes out of the clock; something heavy at the stair door.
func _hunt() -> Array:
	return [
		{"do": "call", "fn": "_hunt_stage"},
		{"do": "bars", "on": true, "t": 0.4, "wait": false},
		{"do": "cam", "pos": Vector3(28.4, 1.6, -4.6), "look": Vector3(32.9, 1.5, -9.5), "fov": 50.0},
		{"do": "sfx", "file": SFX % "door_bang_1", "vol": 2.0},
		{"do": "shake", "amount": 0.02, "t": 0.4},
		{"do": "wait", "t": 1.3},
		{"do": "sfx", "file": SFX % "door_bang_2", "vol": 4.0},
		{"do": "shake", "amount": 0.03, "t": 0.4},
		{"do": "wait", "t": 0.9},
		{"do": "call", "fn": "_hunt_door"},
		{"do": "call", "fn": "_tally_in", "wait": false},
		{"do": "cam", "pos": Vector3(29.8, 1.5, -5.8), "look": Vector3(32.9, 1.9, -9.0), "fov": 46.0, "t": 3.6, "block": false},
		{"do": "wait", "t": 3.4},
		{"do": "cam", "pos": Vector3(31.3, 1.75, -6.5), "look": HUNT_FROM + Vector3(0, 2.15, 0), "fov": 40.0},
		{"do": "say", "who": "tallyman", "line": "tally_c2_44", "text": "...forty-three. Forty-four."},
		{"do": "cam", "pos": Vector3(24.2, 1.62, -4.8), "look": Vector3(26.3, 1.5, -6.6), "fov": 46.0},
		{"do": "say", "who": "zegan", "line": "z_c2_followed", "text": "That thing from the Archive. It followed us down."},
		{"do": "say", "who": "obcera", "line": "o_c2_move", "text": "Don't fight it. Just move!"},
		{"do": "fade", "to": 1.0, "t": 0.5},
	]

func _hunt_stage() -> void:
	_place("zegan", Vector3(25.6, 0.0, -6.7), Vector3(32.9, 0.0, -9.5))
	_place("obcera", Vector3(27.0, 0.0, -6.3), Vector3(32.9, 0.0, -9.5))
	_tally = StoryActor.new("tallyman")
	_tally.position = Undercroft.TALLY_IN
	_tally.rotation.y = PI
	add_child(_tally)
	_scene_bits.append(_tally)
	var breath := _audio3d(SFX % "stalker_breath", -2.0, true)
	if breath:
		breath.position.y = 2.2
		_tally.add_child(breath)
		breath.play()

func _hunt_door() -> void:
	var door := _door("stair_door")
	if door and not door.is_open:
		door._set_open(true, Vector3(0, 0, 1), true)

func _tally_in() -> Signal:
	return _tally.walk_to(HUNT_FROM, 0.95, "stalk")

## Hardass on the tannoy: the handle is on his belt, he's in the muster room.
func _intercom() -> Array:
	return [
		{"do": "call", "fn": "_intercom_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		{"do": "cam", "pos": Vector3(42.4, 1.55, 1.2), "look": Undercroft.PA_HORN, "fov": 42.0},
		{"do": "cam", "pos": Vector3(42.0, 1.6, 1.0), "look": Undercroft.PA_HORN, "fov": 36.0, "t": 8.0, "block": false},
		{"do": "sfx", "file": SFX % "pa_crackle", "vol": -2.0},
		{"do": "wait", "t": 0.9},
		{"do": "say", "who": "hardass", "line": "h_pa_1", "text": "...is this on. You two. From upstairs."},
		{"do": "cam", "pos": Vector3(49.4, 1.4, 2.2), "look": Vector3(48.2, 1.1, 0.3), "fov": 42.0},
		{"do": "say", "who": "hardass", "line": "h_pa_2", "text": "Fuel in. Fuse in. You're nearly there."},
		{"do": "cam", "pos": Vector3(44.2, 1.6, 3.4), "look": Undercroft.PA_HORN, "fov": 48.0},
		{"do": "say", "who": "hardass", "line": "h_pa_3", "text": "The starting handle's on my belt. Muster room, off the tunnel. I've unbarred the door."},
		{"do": "cam", "pos": Vector3(47.0, 1.6, 3.6), "look": Vector3(45.3, 1.5, 1.9), "fov": 46.0},
		{"do": "say", "who": "obcera", "line": "o_pa_help", "text": "Warden? You sound hurt. Let us help you."},
		{"do": "cam", "pos": Vector3(42.0, 1.55, 1.0), "look": Undercroft.PA_HORN, "fov": 34.0},
		{"do": "say", "who": "hardass", "line": "h_pa_4", "text": "Come and count yourselves out. Before I forget why I'm waiting.", "gap": 0.6},
		{"do": "sfx", "file": SFX % "pa_crackle", "vol": -6.0},
		{"do": "wait", "t": 0.8},
		{"do": "fade", "to": 1.0, "t": 0.6},
	]

func _intercom_stage() -> void:
	_place("zegan", Vector3(45.0, 0.0, 1.6), Undercroft.PA_HORN)
	_place("obcera", Vector3(45.9, 0.0, 2.6), Undercroft.PA_HORN)

## The muster room: the Warden on the bench by his lantern, and what he
## has become.
func _warden() -> Array:
	var S := Undercroft.WARDEN_SEAT
	return [
		{"do": "call", "fn": "_warden_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		{"do": "cam", "pos": Vector3(25.2, 1.7, 5.5), "look": S + Vector3(0.0, 0.9, 0.0), "fov": 50.0},
		{"do": "cam", "pos": Vector3(25.4, 1.65, 6.4), "look": S + Vector3(0.0, 0.9, 0.0), "fov": 46.0, "t": 5.0, "block": false},
		{"do": "say", "who": "hardass", "line": "h_w_close", "text": "That's close enough."},
		{"do": "cam", "pos": Vector3(24.6, 1.6, 6.3), "look": Vector3(26.1, 1.45, 6.2), "fov": 46.0},
		{"do": "say", "who": "zegan", "line": "z_w_bite", "text": "Warden. Let me look at that bite."},
		{"do": "cam", "pos": S + Vector3(0.7, 1.05, -2.1), "look": S + Vector3(0.0, 1.15, 0.0), "fov": 40.0},
		{"do": "cam", "pos": S + Vector3(0.55, 1.08, -1.8), "look": S + Vector3(0.0, 1.2, 0.0), "fov": 36.0, "t": 9.0, "block": false},
		{"do": "say", "who": "hardass", "line": "h_w_counted", "text": "Forty-one. I counted every one of them in."},
		{"do": "say", "who": "hardass", "line": "h_w_out", "text": "Not one of them went out.", "gap": 0.6},
		{"do": "say", "who": "hardass", "line": "h_w_take", "text": "The handle's on my belt. Take it... if you can."},
		{"do": "call", "fn": "_warden_turn"},
		{"do": "shake", "amount": 0.02, "t": 2.6},
		{"do": "sfx", "file": SFX % "warden_pain_1", "vol": 0.0},
		{"do": "wait", "t": 1.6},
		{"do": "cam", "pos": Vector3(25.0, 1.6, 6.0), "look": Vector3(26.2, 1.5, 6.2), "fov": 48.0},
		{"do": "say", "who": "zegan", "line": "z_w_back", "text": "He's turning. Get back!"},
		{"do": "call", "fn": "_warden_stand"},
		{"do": "cam", "pos": S + Vector3(0.0, 0.55, -4.6), "look": S + Vector3(0.0, 1.5, 0.0), "fov": 54.0},
		{"do": "cam", "pos": S + Vector3(0.0, 0.5, -4.0), "look": S + Vector3(0.0, 1.7, 0.0), "fov": 50.0, "t": 3.4, "block": false},
		{"do": "wait", "t": 2.2},
		{"do": "call", "fn": "_warden_roar"},
		{"do": "shake", "amount": 0.035, "t": 1.4},
		{"do": "title", "text": "THE LAST WARDEN", "sub": "Warden Jackson Hardass", "t": 3.0},
		{"do": "fade", "to": 1.0, "t": 0.4},
	]

func _warden_stage() -> void:
	_place("zegan", Vector3(25.4, 0.0, 6.2), Undercroft.WARDEN_SEAT)
	_place("obcera", Vector3(26.8, 0.0, 6.3), Undercroft.WARDEN_SEAT)
	# The boss himself, still: the scene drives his clips, then he wakes.
	var b := _spawn_boss(false)
	if b == null:
		return
	b.remove_from_group("zombies")
	b.global_position = Undercroft.WARDEN_SEAT
	b.rotation.y = 0.0
	_seat_clip.call_deferred(b)

func _seat_clip(b: WardenBoss) -> void:
	if is_instance_valid(b) and b.actor and b.actor._anim:
		b.actor.play("sit_slump", 0.0)

func _warden_turn() -> void:
	if _boss and _boss.actor:
		_boss.actor.play("convulse", 0.2)

func _warden_stand() -> void:
	if _boss and _boss.actor:
		_boss.actor.play("sit_stand", 0.25, 1.4)

func _warden_roar() -> void:
	if _boss and _boss.actor:
		_boss.actor.play("roar", 0.3, 1.2)
		Sfx.voice("warden_roar", _boss, 6.0, 6.0, 40.0)

## Behind the flood door: Nasri's card on the wet floor, his chalk on the wall.
func _end_scene() -> Array:
	var L := Undercroft.LANYARD_AT
	var C := Undercroft.CHALK_AT
	return [
		{"do": "call", "fn": "_end_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		{"do": "cam", "pos": L + Vector3(-1.2, 1.3, -1.9), "look": L, "fov": 44.0},
		{"do": "cam", "pos": L + Vector3(-0.8, 0.9, -1.3), "look": L, "fov": 38.0, "t": 4.5, "block": false},
		{"do": "say", "who": "obcera", "line": "o_e_card", "text": "That's Nasri's. His staff card."},
		{"do": "cam", "pos": C + Vector3(-2.6, 0.05, -0.8), "look": C, "fov": 50.0},
		{"do": "cam", "pos": C + Vector3(-2.2, 0.05, -0.6), "look": C, "fov": 46.0, "t": 6.0, "block": false},
		{"do": "say", "who": "zegan", "line": "z_e_count", "text": "'The count is wrong.' What does that mean?"},
		{"do": "say", "who": "obcera", "line": "o_e_kids", "text": "He used to say it when we were kids. About everything."},
		{"do": "sfx", "file": VOICE % "tally_c2_44", "vol": -14.0},
		{"do": "wait", "t": 2.4},
		{"do": "cam", "pos": Vector3(49.2, 1.6, 14.2), "look": Vector3(46.6, 1.45, 13.9), "fov": 48.0},
		{"do": "say", "who": "zegan", "line": "z_e_finished", "text": "Whatever's counting down here, it isn't finished."},
		{"do": "call", "fn": "_gesture", "args": ["obcera", "call"]},
		{"do": "say", "who": "obcera", "line": "o_e_neither", "text": "Neither are we. Nasri's still out there."},
		{"do": "cam", "pos": Vector3(47.0, 2.4, 19.2), "look": Vector3(46.4, 1.3, 13.0), "fov": 55.0},
		{"do": "cam", "pos": Vector3(47.0, 2.8, 19.4), "look": Vector3(46.4, 1.6, 12.0), "fov": 58.0, "t": 6.0, "block": false},
		{"do": "chapter", "num": "END OF CHAPTER 2", "name": "TO BE CONTINUED", "t": 4.8},
		{"do": "fade", "to": 1.0, "t": 0.8},
	]

func _end_stage() -> void:
	_place("zegan", Vector3(45.9, 0.0, 13.6), Undercroft.LANYARD_AT)
	_place("obcera", Vector3(47.1, 0.0, 14.4), Undercroft.LANYARD_AT)

# ================================================================== staging

func _players() -> Array:
	return get_tree().get_nodes_in_group("players")

func _player_of(ch: String) -> Node:
	for p in _players():
		if p.character == ch:
			return p
	return null

static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

## Puts a survivor on a mark facing `look`, for the scene. In solo the partner
## is a stand-in body that exists only while the scene plays.
func _place(ch: String, pos: Vector3, look: Vector3) -> CharacterModel:
	var y := _yaw_to(pos, look)
	var p := _player_of(ch)
	if p:
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.body.rotation.y = y
		p.sync_yaw = y
		p.yaw = y
		p.cutscene_pose = true
		p.model.play("idle", false)
		return p.model
	if _stand_in == null:
		_stand_in = CharacterModel.new()
		_stand_in.character = ch
		_stand_in.customization = GameState.default_customization(ch)
		add_child(_stand_in)
		_scene_bits.append(_stand_in)
	_stand_in.global_position = pos
	_stand_in.rotation.y = y
	_stand_in.play("idle", false)
	return _stand_in

func _model_of(ch: String) -> CharacterModel:
	var p := _player_of(ch)
	if p:
		return p.model
	return _stand_in if is_instance_valid(_stand_in) and _stand_in.character == ch else null

func _gesture(ch: String, clip: String) -> void:
	var m := _model_of(ch)
	if m:
		m.play_once(clip, 0.2)

func _face_players(at: Vector3) -> void:
	for p in _players():
		var y := _yaw_to(p.global_position, at)
		p.body.rotation.y = y
		if p.is_multiplayer_authority():
			p.sync_yaw = y
			p.yaw = y

func _clear_scene_bits() -> void:
	for n in _scene_bits:
		if is_instance_valid(n):
			n.queue_free()
	_scene_bits.clear()
	_stand_in = null
	_tally = null

func _audio3d(path: String, vol: float, looped: bool) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(path):
		return null
	var a := AudioStreamPlayer3D.new()
	var st: AudioStream = load(path)
	if looped:
		st = st.duplicate()
		if st is AudioStreamOggVorbis:
			st.loop = true
	a.stream = st
	a.volume_db = vol
	a.unit_size = 5.0
	a.max_distance = 30.0
	a.bus = "SFX"
	return a
