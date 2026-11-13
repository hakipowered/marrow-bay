class_name Chapter1Story
extends Node3D
## Story for the Archive hub: the prologue "Last Call" (the intro film, then the
## burning ambulance on Ashgrove Street) and chapter 1 "Shelter": the gates and
## the shelter banner, Warden Hardass in the archivist's office, the first
## sighting of the Tallyman through the reading room's frosted glass, and the
## ride down in the vault elevator once the power is back (BreakerPanel,
## VaultElevator), where chapter 1 ends and the game goes on to chapter 2,
## the Undercroft (Chapter2Story).
##
## ArchiveHub adds one of these. Cutscenes asks cutscene(id) for a scene's steps
## and calls on_cutscene_end(id) on every phone when it ends or is skipped;
## everything a scene changes for good (flags, the objective, the key card,
## where Hardass stands) happens there, so skipping is always safe.
## See docs/lore.md for the story these scenes belong to.

const VIDEO := "res://assets/story/video/%s.ogv"
const SFX := "res://assets/story/sfx/%s.ogg"

const WRECK := Vector3(-8.0, 0.0, -27.6)
const GATE := Vector3(0.0, 0.0, -14.0)
## Frosted pane in the wall between the west corridor and the reading room.
const PANE := Vector3(-19.4, 1.65, 5.0)
const HARDASS_SPOT := Vector3(17.0, 0.0, 2.7)
const HARDASS_REST := Vector3(18.9, 0.0, 6.0)

## Objectives after Hardass hands over the card. The first replaced "Find a
## way down to the records vault", which never said where the power was.
const OBJ_POWER := "Get the power on: the breaker is in the boiler room, through the vault"
const OBJ_LIFT := "Take the vault elevator down"
## Chapter 2 starts where the elevator stops.
const NEXT_LEVEL := "res://scenes/levels/undercroft.tscn"
const NEXT_CHECKPOINT := "ch2_lift"
const OBJ_OLD_WARDEN := "Find a way down to the records vault"

## Story triggers, checked by the host. A scene starts when a player walks
## into its box, the scene before it has played, and no infected is on them.
const TRIGGERS := [
	{"id": "gates", "box": [Vector3(-3.0, 0.0, -18.0), Vector3(6.0, 3.0, 3.0)], "after": "story_intro"},
	{"id": "warden", "box": [Vector3(12.3, 0.0, 1.3), Vector3(1.9, 3.0, 2.6)], "after": "story_gates"},
	{"id": "glass", "box": [Vector3(-16.8, 0.0, 5.0), Vector3(2.2, 3.0, 3.0)], "after": "story_gates"},
]

var _fired := {}
var _fire_glow: OmniLight3D
var _fire_t := 0.0
var _wreck: Node3D
var _hardass: StoryActor
var _talk: Area3D
var _tally: StoryActor
var _stand_in: CharacterModel
var _scene_bits: Array[Node] = []

func _ready() -> void:
	add_to_group("story")
	_build_wreck()
	_build_banner()
	_build_frosted_pane()
	_build_hardass()
	Cutscenes.all_peers_ready.connect(_on_all_ready)
	if not GameState.has_flag("story_intro"):
		# The intro starts as soon as both phones have the level: keep the
		# screen black until then so nobody sees the street first.
		Cutscenes.cover(true)
		get_tree().create_timer(8.0).timeout.connect(func():
			if not Cutscenes.active and not GameState.has_flag("story_intro"):
				Cutscenes.cover(false))
	_restore_objective.call_deferred()

func _restore_objective() -> void:
	# A save from after the ride (older builds put them back in the vault
	# with nowhere to go): on to chapter 2.
	if GameState.has_flag("story_elevator"):
		_to_chapter2()
		return
	# Saves from before the breaker worked still carry the old, vague goal.
	if GameState.has_flag("story_warden") and GameState.world_flags.get("objective", "") == OBJ_OLD_WARDEN:
		GameState.world_flags["objective"] = OBJ_LIFT if VaultCircuit.is_on() else OBJ_POWER
	if GameState.has_flag("story_intro"):
		Cutscenes.show_objective()

func _on_all_ready() -> void:
	if multiplayer.is_server() and not GameState.has_flag("story_intro") and not _fired.has("intro"):
		_fired["intro"] = true
		Cutscenes.play("intro")

func _process(delta: float) -> void:
	if _fire_glow:
		_fire_t += delta
		_fire_glow.light_energy = 3.0 + sin(_fire_t * 11.0) * 0.35 + sin(_fire_t * 23.7) * 0.25 + randf_range(-0.2, 0.2)

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or Cutscenes.active or not Cutscenes.all_ready():
		return
	for t in TRIGGERS:
		var id: String = t["id"]
		if _fired.has(id) or GameState.has_flag("story_" + id) or not GameState.has_flag(t["after"]):
			continue
		var box := AABB(t["box"][0], t["box"][1])
		for p in _players():
			if box.has_point(p.global_position + Vector3.UP * 0.5) and _quiet(p.global_position):
				_fired[id] = true
				Cutscenes.play(id)
				return

## No scene while someone is fighting for their life.
func _quiet(at: Vector3) -> bool:
	for p in _players():
		if p.downed or p.pinned:
			return false
	var space := get_world_3d().direct_space_state
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(at) < 12.0 and z.get("state") in [Zombie.S.CHASE, Zombie.S.ATTACK, Zombie.S.CHARGE, Zombie.S.PINNING]:
			# One shut out behind a closed gate, door or wall can't reach
			# anyone yet (and the infected freeze during a scene). It used to
			# hold a scene back for good: the nurse pressed against the
			# Archive gates kept the gates scene from playing, and the warden
			# and glass scenes wait for that one.
			var q := PhysicsRayQueryParameters3D.create(z.global_position + Vector3.UP * 1.2, at + Vector3.UP * 1.2, 1, [z.get_rid()])
			if not space.intersect_ray(q).is_empty():
				continue
			return false
	for s in get_tree().get_nodes_in_group("stalker"):
		if s.active and s.global_position.distance_to(at) < 14.0:
			return false
	return true

# ================================================================== scenes

func cutscene(id: String) -> Array:
	match id:
		"intro": return _intro()
		"gates": return _gates()
		"glass": return _glass()
		"warden": return _warden()
		"elevator": return _elevator()
	return []

func on_cutscene_end(id: String) -> void:
	GameState.set_flag("story_" + id)
	_clear_scene_bits()
	match id:
		"intro":
			_face_players(GATE)
			Cutscenes.set_objective("Get through the gates of the Civic Archive")
		"gates":
			Cutscenes.set_objective("Find the survivors inside the Archive")
		"glass":
			if is_instance_valid(_tally):
				_tally.queue_free()
			_tally = null
		"warden":
			_hardass_at_rest()
			for p in _players():
				if p.is_multiplayer_authority() and not p.inventory.key_items.has("vault_card"):
					p.inventory.key_items.append("vault_card")
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("Got: Vault elevator key card")
			Cutscenes.set_objective(OBJ_LIFT if VaultCircuit.is_on() else OBJ_POWER)
		"elevator":
			_to_chapter2()

## Prologue: the narrated film, the crash film, then the street in the engine.
func _intro() -> Array:
	var narr := func(at: float, n: int, text: String) -> Dictionary:
		return {"at": at, "do": "say", "who": "narrator", "line": "n_intro_%d" % n, "text": text}
	return [
		{"do": "fade", "to": 1.0, "t": 0.0},
		{"do": "music", "track": "story_intro"},
		{"do": "loop", "file": SFX % "rain", "vol": -16.0},
		{"do": "video", "file": VIDEO % "intro_a", "cues": [
			{"at": 0.0, "do": "fade", "to": 0.0, "t": 0.2},
			narr.call(1.5, 1, "Every city keeps a ledger. Births. Deaths. Debts."),
			{"at": 11.8, "do": "sfx", "file": SFX % "tunnel", "vol": -9.0},
			narr.call(12.0, 2, "Three weeks ago, the Deep Tunnel crews broke into something the city had buried in 1891."),
			narr.call(22.05, 3, "The men came home with a fever. They slept for two days... and woke up hungry."),
			narr.call(33.0, 4, "City Hall called it the flu. They locked the evidence in the Archive... and kept the river festival going."),
			{"at": 43.3, "do": "sfx", "file": SFX % "blackout", "vol": -6.0},
			narr.call(43.5, 5, "Tonight, the quarantine failed. The lights went out across downtown. And the Archive, the city's storm shelter, stopped answering the radio."),
			{"at": 57.1, "do": "sfx", "file": SFX % "ambulance", "vol": -12.0},
			narr.call(57.35, 6, "That night, RaGoon City stopped counting the living."),
			{"at": 63.45, "do": "sfx", "file": SFX % "title_hit", "vol": -3.0},
			{"at": 63.5, "do": "title", "text": "RAGOON CITY", "t": 3.6},
			narr.call(67.2, 7, "Two strangers drove into it at the same moment. A paramedic, finishing his last call..."),
			narr.call(81.0, 8, "...and a courier, carrying a sealed package addressed to the Archive."),
		]},
		{"do": "video", "file": VIDEO % "intro_b", "hold": true, "cues": [
			{"at": 0.0, "do": "sfx", "file": SFX % "crash", "vol": 0.0},
			{"at": 0.8, "do": "loop", "file": SFX % "fire", "vol": -14.0},
			{"at": 10.92, "do": "say", "who": "obcera", "line": "lc_1", "text": "You alive? Or are you gonna bite me too?"},
			{"at": 14.92, "do": "say", "who": "zegan", "line": "lc_2", "text": "Ask me again in a minute."},
			{"at": 17.95, "do": "sub", "who": "zegan", "text": "My patient... he was dead. He was dead, and he sat up.", "t": 5.4},
			{"at": 23.46, "do": "say", "who": "obcera", "line": "lc_3", "text": "Yeah. The whole street's doing it."},
			{"at": 26.73, "do": "sub", "who": "obcera", "text": "The Archive's at the end of this block. That's where I'm going. Stay close, paramedic.", "t": 5.0},
		]},
		# Into the engine: the wreck burning in the rain, the two of them, the gates.
		{"do": "fade", "to": 1.0, "t": 0.0},
		{"do": "call", "fn": "_intro_stage"},
		{"do": "bars", "on": true, "t": 0.0},
		{"do": "cam", "pos": Vector3(-3.6, 0.45, -24.2), "look": WRECK + Vector3(0.6, 1.0, 0.0), "fov": 50.0},
		{"do": "cam", "pos": Vector3(-3.1, 0.8, -23.4), "look": WRECK + Vector3(0.8, 1.3, 0.2), "t": 5.0, "block": false},
		{"do": "fade", "to": 0.0, "t": 1.6},
		{"do": "shake", "amount": 0.015, "t": 2.5},
		{"do": "wait", "t": 2.6},
		{"do": "cam", "pos": Vector3(1.4, 1.2, -21.2), "look": Vector3(-2.0, 0.7, -23.4), "fov": 46.0},
		{"do": "call", "fn": "_zegan_up"},
		{"do": "cam", "pos": Vector3(1.0, 1.35, -21.6), "look": Vector3(-2.0, 1.1, -23.3), "t": 3.6, "block": false},
		{"do": "wait", "t": 2.4},
		{"do": "call", "fn": "_gesture", "args": ["obcera", "call"]},
		{"do": "wait", "t": 1.6},
		{"do": "cam", "pos": Vector3(-2.6, 1.6, -26.4), "look": Vector3(0.0, 2.4, -14.0), "fov": 55.0},
		{"do": "cam", "pos": Vector3(-1.8, 3.6, -27.4), "look": Vector3(0.0, 3.2, -14.0), "t": 6.0, "block": false},
		{"do": "chapter", "num": "PROLOGUE", "name": "LAST CALL", "t": 4.6},
		{"do": "wait", "t": 0.6},
		{"do": "fade", "to": 1.0, "t": 0.8},
	]

## The Archive's iron gates, the banner, the faces at the windows.
func _gates() -> Array:
	return [
		{"do": "call", "fn": "_gates_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		{"do": "cam", "pos": Vector3(0.4, 1.5, -12.4), "look": Vector3(-0.2, 1.5, -17.2), "fov": 52.0},
		{"do": "cam", "pos": Vector3(0.2, 1.55, -12.8), "look": Vector3(-0.2, 1.55, -17.2), "t": 3.0, "block": false},
		{"do": "say", "who": "obcera", "line": "o_gate_this", "text": "That's it. The Civic Archive."},
		{"do": "cam", "pos": Vector3(-0.6, 1.7, -18.8), "look": Vector3(0.0, 3.8, -14.0), "fov": 50.0},
		{"do": "cam", "pos": Vector3(0.4, 1.6, -18.2), "look": Vector3(0.3, 3.7, -14.0), "t": 4.0, "block": false},
		{"do": "say", "who": "zegan", "line": "z_gate_banner", "text": "All welcome. No one turned away."},
		{"do": "say", "who": "obcera", "line": "o_gate_quiet", "text": "Then why's it so quiet?"},
		{"do": "cam", "pos": Vector3(0.0, 2.6, -15.2), "look": Vector3(7.5, 2.4, -2.0), "fov": 40.0},
		{"do": "call", "fn": "_faces_move"},
		{"do": "cam", "pos": Vector3(0.3, 2.6, -14.6), "look": Vector3(7.5, 2.4, -2.0), "fov": 30.0, "t": 4.2, "block": false},
		{"do": "say", "who": "zegan", "line": "z_gate_windows", "text": "It's not. Look at the windows."},
		{"do": "wait", "t": 1.4},
		{"do": "cam", "pos": Vector3(2.2, 1.62, -18.7), "look": Vector3(0.7, 1.5, -17.0), "fov": 45.0},
		{"do": "say", "who": "obcera", "line": "o_gate_brother", "text": "My brother works in there. This package goes to him tonight."},
		{"do": "cam", "pos": Vector3(-2.3, 1.6, -18.6), "look": Vector3(-0.8, 1.55, -17.1), "fov": 45.0},
		{"do": "call", "fn": "_gesture", "args": ["zegan", "call"]},
		{"do": "say", "who": "zegan", "line": "z_gate_go", "text": "Then let's go find him."},
		{"do": "cam", "pos": Vector3(0.0, 2.0, -21.5), "look": Vector3(0.0, 2.2, -14.0), "fov": 55.0},
		{"do": "cam", "pos": Vector3(0.0, 2.3, -20.0), "look": Vector3(0.0, 2.6, -14.0), "t": 5.0, "block": false},
		{"do": "chapter", "num": "CHAPTER 1", "name": "SHELTER", "t": 4.4},
		{"do": "fade", "to": 1.0, "t": 0.7},
	]

## The first sighting of the Tallyman: a huge shape behind the frosted pane.
func _glass() -> Array:
	return [
		{"do": "call", "fn": "_glass_stage"},
		{"do": "bars", "on": true, "t": 0.4, "wait": false},
		{"do": "cam", "pos": Vector3(-14.4, 1.75, 7.5), "look": Vector3(-19.4, 1.45, 5.2), "fov": 50.0},
		{"do": "call", "fn": "_tally_walk", "wait": false},
		{"do": "wait", "t": 2.2},
		{"do": "cam", "pos": Vector3(-18.4, 1.62, 7.4), "look": PANE + Vector3(0, -0.05, 0), "fov": 46.0, "t": 3.6, "block": false},
		{"do": "wait", "t": 3.6},
		{"do": "call", "fn": "_tally_stare"},
		{"do": "cam", "pos": Vector3(-18.9, 1.65, 6.9), "look": PANE + Vector3(0, 0.15, 0), "fov": 38.0, "t": 2.8, "block": false},
		{"do": "shake", "amount": 0.006, "t": 2.8},
		{"do": "wait", "t": 3.0},
		{"do": "call", "fn": "_tally_leave", "wait": false},
		{"do": "wait", "t": 3.2},
		{"do": "cam", "pos": Vector3(-17.7, 1.6, 7.5), "look": Vector3(-15.9, 1.5, 6.4), "fov": 48.0},
		{"do": "say", "who": "zegan", "line": "z_glass_what", "text": "What the hell was that?"},
		{"do": "say", "who": "obcera", "line": "o_glass_big", "text": "Something big. Don't let it see us."},
		{"do": "wait", "t": 0.8},
		{"do": "fade", "to": 1.0, "t": 0.6},
	]

## Warden Hardass in the archivist's office.
func _warden() -> Array:
	return [
		{"do": "call", "fn": "_warden_stage"},
		{"do": "bars", "on": true, "t": 0.4, "wait": false},
		{"do": "cam", "pos": Vector3(18.3, 1.75, 3.4), "look": Vector3(13.4, 1.35, 2.6), "fov": 50.0},
		{"do": "call", "fn": "_hardass_play", "args": ["alert"]},
		{"do": "say", "who": "hardass", "line": "h_eyes", "text": "Stop. Right there. Let me see your eyes."},
		{"do": "cam", "pos": Vector3(16.1, 1.6, 2.3), "look": Vector3(13.3, 1.5, 2.6), "fov": 48.0},
		{"do": "call", "fn": "_gesture", "args": ["zegan", "call"]},
		{"do": "say", "who": "zegan", "line": "z_h_medic", "text": "Easy. I'm a paramedic. Are you hurt?"},
		{"do": "cam", "pos": Vector3(15.3, 1.62, 3.0), "look": HARDASS_SPOT + Vector3(0, 1.55, 0), "fov": 38.0},
		{"do": "call", "fn": "_hardass_once", "args": ["hit"]},
		{"do": "say", "who": "hardass", "line": "h_scratch", "text": "It's a scratch. Forget it."},
		{"do": "cam", "pos": Vector3(12.5, 1.7, 3.7), "look": HARDASS_SPOT + Vector3(0, 1.45, 0), "fov": 48.0},
		{"do": "say", "who": "obcera", "line": "o_h_nasri", "text": "I'm looking for Nasri. Records clerk. He works here."},
		{"do": "cam", "pos": Vector3(14.9, 1.6, 3.5), "look": HARDASS_SPOT + Vector3(0, 1.5, 0), "fov": 44.0},
		{"do": "cam", "pos": Vector3(15.6, 1.6, 3.2), "look": HARDASS_SPOT + Vector3(0, 1.55, 0), "fov": 36.0, "t": 10.0, "block": false},
		{"do": "say", "who": "hardass", "line": "h_nasri", "text": "Nasri went down to the vault two days ago. He never came back up."},
		{"do": "say", "who": "hardass", "line": "h_count", "text": "Forty-one people came here for shelter. I counted them in. Count yourselves out.", "gap": 0.6},
		{"do": "cam", "pos": Vector3(15.0, 1.3, 1.6), "look": Vector3(16.6, 1.0, 2.3), "fov": 42.0},
		{"do": "call", "fn": "_hardass_once", "args": ["call"]},
		{"do": "say", "who": "hardass", "line": "h_card", "text": "The vault elevator is the only way out of this building. It needs power. Take the card."},
		{"do": "cam", "pos": Vector3(14.6, 1.6, 3.7), "look": Vector3(13.3, 1.55, 3.0), "fov": 44.0},
		{"do": "say", "who": "obcera", "line": "o_h_you", "text": "And you?"},
		{"do": "cam", "pos": Vector3(19.5, 2.3, 7.5), "look": Vector3(16.2, 1.2, 2.8), "fov": 52.0},
		{"do": "call", "fn": "_hardass_walk_off", "wait": false},
		{"do": "say", "who": "hardass", "line": "h_keep", "text": "Somebody has to keep the count.", "gap": 1.4},
		{"do": "wait", "t": 2.0},
		{"do": "fade", "to": 1.0, "t": 0.6},
	]

## The vault elevator: the doors shut on the vault, the car drops, the light
## dies, and the car hits the bottom in the dark. Chapter 2 picks up from
## there, in the Undercroft (on_cutscene_end loads it on both phones).
func _elevator() -> Array:
	var lift := _lift()
	if lift == null:
		return []
	var L := func(x: float, y: float, z: float) -> Vector3: return lift.car_point(Vector3(x, y, z))
	return [
		{"do": "call", "fn": "_lift_stage"},
		{"do": "bars", "on": true, "t": 0.5, "wait": false},
		# From the back corner of the car, past the two of them, out at the vault.
		{"do": "cam", "pos": L.call(-1.45, 1.7, -2.55), "look": L.call(0.25, 1.25, 0.6), "fov": 52.0},
		{"do": "call", "fn": "_lift_close"},
		{"do": "cam", "pos": L.call(-1.3, 1.62, -2.5), "look": L.call(0.2, 1.3, 0.4), "t": 2.6, "block": false},
		{"do": "wait", "t": 2.2},
		{"do": "sfx", "file": "res://assets/audio/sfx/lift_ride_1.ogg", "vol": 0.0},
		{"do": "shake", "amount": 0.02, "t": 0.6},
		{"do": "wait", "t": 0.7},
		# The two of them from the front corner, in the car light, the floor
		# going away under them.
		{"do": "cam", "pos": L.call(1.5, 1.6, -0.42), "look": L.call(-0.25, 1.42, -1.5), "fov": 54.0},
		{"do": "cam", "pos": L.call(1.4, 1.55, -0.5), "look": L.call(-0.2, 1.45, -1.45), "fov": 50.0, "t": 6.0, "block": false},
		{"do": "shake", "amount": 0.004, "t": 7.0},
		{"do": "say", "who": "obcera", "line": "o_lift_down", "text": "Nasri's down there. Somewhere."},
		{"do": "say", "who": "zegan", "line": "z_lift_down", "text": "Then that's where we're going.", "gap": 0.5},
		{"do": "call", "fn": "_lift_flicker"},
		{"do": "wait", "t": 1.9},
		{"do": "sfx", "file": "res://assets/audio/sfx/metal_bang_1.ogg", "vol": -2.0},
		{"do": "shake", "amount": 0.03, "t": 0.5},
		{"do": "wait", "t": 0.7},
		{"do": "fade", "to": 1.0, "t": 0.5},
		{"do": "wait", "t": 1.2},
	]

## Into chapter 2 on every phone. Also for a save made after the ride in an
## older build, which still put them back in the vault.
func _to_chapter2() -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("change_level"):
		level.change_level(NEXT_LEVEL, NEXT_CHECKPOINT)

func _lift() -> Node:
	return get_tree().get_first_node_in_group("vault_elevator")

func _lift_stage() -> void:
	var lift := _lift()
	if lift == null:
		return
	var out: Vector3 = lift.car_point(Vector3(0, 0, 2.0))
	_place("zegan", lift.ride_spot(0), out)
	_place("obcera", lift.ride_spot(1), out)

func _lift_close() -> void:
	var lift := _lift()
	if lift:
		lift.close_for_ride()

func _lift_flicker() -> void:
	var lift := _lift()
	if lift:
		lift.flicker_car()

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

func _intro_stage() -> void:
	var z := _place("zegan", Vector3(-2.4, 0.0, -23.7), Vector3(-1.4, 0.0, -22.8))
	if z:
		z.hold_end("knockdown")
	_place("obcera", Vector3(-1.3, 0.0, -22.9), Vector3(-2.4, 0.0, -23.7))

func _zegan_up() -> void:
	var z := _model_of("zegan")
	if z:
		z.play_once("stand_up", 0.15, 0.9)
	# Then both turn toward the gates.
	get_tree().create_timer(2.4).timeout.connect(func():
		for ch in ["zegan", "obcera"]:
			var m := _model_of(ch)
			if m:
				var tw := create_tween()
				var holder: Node3D = m.get_parent() if _player_of(ch) else m
				tw.tween_property(holder, "rotation:y", _yaw_to(holder.global_position, GATE), 0.8).set_trans(Tween.TRANS_SINE))

func _gates_stage() -> void:
	_place("zegan", Vector3(-0.9, 0.0, -17.3), GATE + Vector3(-0.4, 0, 0))
	_place("obcera", Vector3(0.9, 0.0, -17.0), GATE + Vector3(0.4, 0, 0))
	# Shapes moving behind the boarded Great Hall windows, lit from inside.
	for spot in [Vector3(7.3, 0.0, -1.1), Vector3(8.0, 0.0, -0.7), Vector3(-7.6, 0.0, -1.0)]:
		var f := _silhouette()
		f.position = spot
		f.rotation.y = randf_range(-0.5, 0.5)
		add_child(f)
		_scene_bits.append(f)
	for x in [7.5, -7.5]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.32)
		l.light_energy = 2.2
		l.omni_range = 4.5
		l.position = Vector3(x, 2.3, 1.2)
		add_child(l)
		_scene_bits.append(l)

func _faces_move() -> void:
	for n in _scene_bits:
		if n is Node3D and n.has_meta("figure"):
			var tw: Tween = n.create_tween().set_loops(3)
			tw.tween_property(n, "position:x", n.position.x + randf_range(-0.5, 0.5), randf_range(0.9, 1.6)).set_trans(Tween.TRANS_SINE)
			tw.tween_property(n, "position:x", n.position.x, randf_range(0.9, 1.6)).set_trans(Tween.TRANS_SINE)

## A dark human shape (seen only through boards and dirty glass).
func _silhouette() -> Node3D:
	var root := Node3D.new()
	root.set_meta("figure", true)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.015, 0.012, 0.012)
	mat.roughness = 1.0
	var parts := [[CapsuleMesh, Vector3(0, 1.0, 0), Vector2(0.24, 1.45)], [SphereMesh, Vector3(0.03, 1.78, 0), Vector2(0.12, 0.26)],
		[CapsuleMesh, Vector3(0.3, 1.15, -0.08), Vector2(0.06, 0.75)], [CapsuleMesh, Vector3(-0.3, 1.2, 0.02), Vector2(0.06, 0.75)]]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var m: PrimitiveMesh = pt[0].new()
		m.radius = pt[2].x
		m.height = pt[2].y
		mi.mesh = m
		mi.material_override = mat
		mi.position = pt[1]
		root.add_child(mi)
	root.rotation_degrees.z = randf_range(-8, 8)
	return root

func _glass_stage() -> void:
	_place("zegan", Vector3(-16.3, 0.0, 6.1), PANE)
	_place("obcera", Vector3(-15.4, 0.0, 7.0), PANE)
	_tally = StoryActor.new("tallyman")
	_tally.position = Vector3(-25.0, 0.0, 3.9)
	_tally.rotation.y = -PI / 2
	add_child(_tally)
	_scene_bits.append(_tally)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 3.4
	lamp.omni_range = 6.0
	lamp.position = Vector3(-19.6, 2.1, 0.6)
	add_child(lamp)
	_scene_bits.append(lamp)
	var breath := _audio3d("res://assets/audio/sfx/stalker_breath.ogg", -4.0, true)
	if breath:
		breath.position.y = 2.2
		_tally.add_child(breath)
		breath.play()

func _tally_walk() -> Signal:
	_scrape(-6.0)
	# Stops where the close-up looks through the pane (the wall is thick).
	return _tally.walk_to(Vector3(-19.75, 0.0, 3.9), 0.95, "stalk")

func _tally_stare() -> void:
	_tally.play("idle", 0.4)
	_tally.face(Vector3(-17.0, 0.0, 6.6), 1.4)
	Cutscenes._sfx(SFX % "title_hit", -14.0)

func _tally_leave() -> Signal:
	_scrape(-8.0)
	var s := _tally.walk_to(Vector3(-13.6, 0.0, 3.4), 0.95, "stalk")
	var tw := _tally.create_tween()
	tw.tween_interval(3.5)
	tw.tween_callback(func():
		for a in _tally.find_children("*", "AudioStreamPlayer3D", false, false):
			a.create_tween().tween_property(a, "volume_db", -60.0, 2.5))
	return s

func _scrape(vol: float) -> void:
	var a := _audio3d(SFX % "hook_scrape", vol, false)
	if a and is_instance_valid(_tally):
		a.position = Vector3(0.6, 0.2, 0.9)
		_tally.add_child(a)
		a.play()

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

func _warden_stage() -> void:
	_place("zegan", Vector3(13.3, 0.0, 2.2), HARDASS_SPOT)
	_place("obcera", Vector3(13.1, 0.0, 3.1), HARDASS_SPOT)
	if _hardass:
		_hardass.global_position = HARDASS_SPOT
		_hardass.rotation.y = _yaw_to(HARDASS_SPOT, Vector3(13.2, 0, 2.6))
		_hardass.play("idle", 0.0)
		_talk.monitorable = false

func _hardass_play(clip: String) -> void:
	if _hardass:
		_hardass.play(clip, 0.3)

func _hardass_once(clip: String) -> void:
	if _hardass:
		_hardass.play_once(clip, "idle", 0.2)

func _hardass_walk_off() -> Signal:
	if not _hardass:
		return get_tree().process_frame
	var clip := "injured_walk" if _hardass.has_clip("injured_walk") else "walk"
	return _hardass.walk_to(HARDASS_REST, 0.8, clip)

# ================================================================== the set

func _build_wreck() -> void:
	_wreck = Node3D.new()
	_wreck.name = "AmbulanceWreck"
	_wreck.position = WRECK
	add_child(_wreck)
	var path := "res://assets/props/ambulance_wreck/ambulance_wreck.glb"
	var size := Vector3(6.6, 2.4, 2.5)
	if ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate()
		_wreck.add_child(m)
		var box := _bounds(m)
		if box.size.z > box.size.x:
			m.rotation.y = PI / 2
			box = _bounds(m)
		var s := 6.6 / maxf(box.size.x, 0.01)
		m.scale = Vector3.ONE * s
		box = _bounds(m)
		m.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
		size = box.size
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y / 2
	sb.add_child(cs)
	_wreck.add_child(sb)
	# Fire in the cab end, smoke, embers and the glow on the wet road.
	var front := Vector3(size.x * 0.36, 0.5, 0.0)
	_wreck.add_child(_flames(front, Vector3(0.7, 0.3, 0.8)))
	_wreck.add_child(_flames(Vector3(-size.x * 0.1, size.y * 0.75, 0.2), Vector3(0.6, 0.15, 0.5), 0.6))
	_wreck.add_child(_smoke(front + Vector3(0, 1.2, 0)))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.18)
	glow.light_energy = 3.2
	glow.omni_range = 9.0
	glow.shadow_enabled = true
	glow.position = front + Vector3(0.6, 1.0, 1.0)
	_wreck.add_child(glow)
	_fire_glow = glow
	var crackle := _audio3d(SFX % "fire", -8.0, true)
	if crackle:
		crackle.position = front
		crackle.unit_size = 3.5
		_wreck.add_child(crackle)
		crackle.autoplay = true

func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := _wreck.global_transform.affine_inverse()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

## The wreck's fire: photographed flame sprites, embers and smoke (the same
## fire as everywhere else, see Effects.make_fire). The glow is lit separately.
func _flames(at: Vector3, extents: Vector3, strength := 1.0) -> Node3D:
	var f := Effects.make_fire(extents, strength * 1.4, true, false)
	f.position = at
	return f

func _smoke(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 5.0
	p.position = at
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.4, 0.3, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.12, 0.1, 0.09, 0.0))
	grad.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
	grad.add_point(0.15, Color(0.14, 0.12, 0.1, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.angle_max = 360.0
	pm.anim_offset_max = 1.0
	p.process_material = pm
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = Effects.SMOKE_TEX
	mat.particles_anim_h_frames = 2
	mat.particles_anim_v_frames = 2
	mat.particles_anim_loop = false
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.5
	mat.roughness = 1.0
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

var _dot: Texture2D
func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_dot = gt
	return _dot

## The shelter's bedsheet banner over the gate, hand-painted, one corner torn
## away, moving in the wind.
func _build_banner() -> void:
	var tex_path := "res://assets/story/textures/shelter_banner.png"
	var mi := MeshInstance3D.new()
	mi.name = "ShelterBanner"
	var q := QuadMesh.new()
	q.size = Vector2(4.6, 1.15)
	q.subdivide_width = 28
	q.subdivide_depth = 6
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/cloth_banner.gdshader")
	if ResourceLoader.exists(tex_path):
		sm.set_shader_parameter("tex", load(tex_path))
	mi.material_override = sm
	mi.position = GATE + Vector3(0.0, 3.95, -0.32)
	mi.rotation = Vector3(0.0, PI, deg_to_rad(-3.0))   # faces the street (-Z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# Two ropes it hangs from.
	for x in [-2.35, 2.35]:
		var rope := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.012
		c.bottom_radius = 0.012
		c.height = 0.5
		rope.mesh = c
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.35, 0.3, 0.22)
		rope.material_override = rm
		rope.position = GATE + Vector3(x, 4.6, -0.32)
		add_child(rope)

## Frosted glass in the wall between the west corridor and the reading room.
func _build_frosted_pane() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "FrostedPane"
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.5)
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/frosted_glass.gdshader")
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = PANE
	add_child(mi)

func _build_hardass() -> void:
	if not ResourceLoader.exists("res://assets/characters/hardass/hardass.glb"):
		return
	_hardass = StoryActor.new("hardass")
	_hardass.name = "WardenHardass"
	add_child(_hardass)
	_talk = Area3D.new()
	_talk.set_script(TalkArea)
	_talk.collision_layer = 16
	_talk.collision_mask = 0
	_talk.set("story", self)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45
	sh.height = 1.8
	cs.shape = sh
	cs.position.y = 0.95
	_talk.add_child(cs)
	_hardass.add_child(_talk)
	if GameState.has_flag("story_warden"):
		_hardass_at_rest()
	else:
		_hardass.position = HARDASS_SPOT
		_hardass.rotation.y = _yaw_to(HARDASS_SPOT, Vector3(12.0, 0, 2.6))
		_talk.monitorable = false

func _hardass_at_rest() -> void:
	if not _hardass:
		return
	_hardass.stop_walk()
	_hardass.global_position = HARDASS_REST
	_hardass.rotation.y = _yaw_to(HARDASS_REST, Vector3(20.0, 0, 6.6))
	_hardass.play("idle", 0.3)
	_talk.monitorable = true

## Talking to Hardass after his scene: one of his lines, for this player only.
var _talk_i := 0
func talk_to_hardass() -> void:
	var lines := [["h_keep", "Somebody has to keep the count."], ["h_count", "Forty-one people came here for shelter. I counted them in. Count yourselves out."],
		["h_card", "The vault elevator is the only way out of this building. It needs power. Take the card."]]
	var l: Array = lines[_talk_i % lines.size()]
	_talk_i += 1
	_hardass.face(_player_of(GameState.local_character()).global_position if _player_of(GameState.local_character()) else HARDASS_SPOT, 0.5)
	var a := _audio3d("res://assets/audio/voice/story/%s.ogg" % l[0], 0.0, false)
	if a:
		a.bus = "Voice"
		a.position.y = 1.6
		_hardass.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_subtitle("Warden Hardass", l[1], 4.0)

const TalkArea := preload("res://scripts/story/talk_area.gd")
