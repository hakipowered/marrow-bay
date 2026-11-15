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
const GAME_SFX := "res://assets/audio/sfx/%s.ogg"

const WRECK := Vector3(-8.0, 0.0, -27.6)
const GATE := Vector3(0.0, 0.0, -14.0)
## Frosted pane in the wall between the west corridor and the reading room.
const PANE := Vector3(-19.4, 1.65, 5.0)
## The bolted staff stair door in the reading room's west wall (ArchiveHub):
## the Tallyman's way in and out. His path from the pane to it, and the hook
## marks it has left on the floor.
const STAFF_DOOR := Vector3(-26.0, 0.0, -1.2)
const TALLY_EXIT := [Vector3(-23.0, 0.0, 0.9), Vector3(-25.2, 0.0, -1.2), Vector3(-27.3, 0.0, -1.2)]
## Warden Hardass keeps watch from the armchair beside the office door,
## facing it: he counted every one of the shelter in through that door.
## HARDASS_POST is the spot he stands up onto (the seated clips put the chair
## WARDEN_SEAT_BACK behind it, see warden_chair()); HARDASS_TALK is where he
## stops them, a step inside the door, where Zegan and Obcera stand.
const HARDASS_POST := Vector3(14.0, 0.0, 4.55)
const HARDASS_WATCH := Vector3(12.4, 0.0, 2.6)
const HARDASS_TALK := Vector3(13.75, 0.0, 3.75)
const WARDEN_Z := Vector3(13.4, 0.0, 2.35)
const WARDEN_O := Vector3(12.85, 0.0, 2.95)
const WARDEN_SEAT_BACK := 0.45
## Eye heights (metres) for framing faces under the letterbox bars.
const EYE := {"hardass": 1.66, "zegan": 1.69, "obcera": 1.58}
## The letterbox bars (Cutscenes "bars") cover this much of the screen
## height at the top and again at the bottom.
const BARS := 0.11

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
	_build_drag_marks()
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
			Cutscenes.set_objective("Take Nasri's package to the Civic Archive")
		"gates":
			Cutscenes.set_objective("Find Nasri inside the Archive")
		"glass":
			if is_instance_valid(_tally):
				_tally.queue_free()
			_tally = null
			# Skipped while he was in the doorway: it is bolted again.
			var door := _staff_door()
			if door and door.is_open:
				door.swing(false, Vector3.ZERO, false)
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
## Film cue times come from tools/story/build_intro.py (it prints them): keep
## the two in step when the edit changes.
func _intro() -> Array:
	var narr := func(at: float, n: int, text: String) -> Dictionary:
		return {"at": at, "do": "say", "who": "narrator", "line": "n_intro_%d" % n, "text": text}
	var line := func(at: float, who: String, id: String, text: String) -> Dictionary:
		return {"at": at, "do": "say", "who": who, "line": id, "text": text}
	var sub := func(at: float, who: String, text: String, t: float) -> Dictionary:
		return {"at": at, "do": "sub", "who": who, "text": text, "t": t}
	var sfx := func(at: float, file: String, vol: float) -> Dictionary:
		return {"at": at, "do": "sfx", "file": file, "vol": vol}
	return [
		{"do": "fade", "to": 1.0, "t": 0.0},
		{"do": "music", "track": "story_intro"},
		{"do": "loop", "file": SFX % "rain", "vol": -16.0},
		# The city, the tunnel worker waking (one shot), the blackout, the title,
		# then Zegan's last call: the flatline, the sheet, the radio nobody
		# answers, Obcera riding, the dead man sitting up and grabbing him.
		{"do": "video", "file": VIDEO % "intro_a", "cues": [
			{"at": 0.0, "do": "fade", "to": 0.0, "t": 0.2},
			narr.call(1.5, 1, "Every city keeps a ledger. Births. Deaths. Debts."),
			sfx.call(11.8, SFX % "tunnel", -9.0),
			narr.call(12.0, 2, "Three weeks ago, the Deep Tunnel crews broke into something the city had buried in 1891."),
			narr.call(22.05, 3, "The men came home with a fever. They slept for two days... and woke up hungry."),
			narr.call(33.0, 4, "City Hall called it the flu. They locked the evidence in the Archive... and kept the river festival going."),
			sfx.call(43.3, SFX % "blackout", -6.0),
			narr.call(43.5, 5, "Tonight, the quarantine failed. The lights went out across downtown. And the Archive, the city's storm shelter, stopped answering the radio."),
			sfx.call(57.1, SFX % "ambulance", -12.0),
			narr.call(57.35, 6, "That night, RaGoon City stopped counting the living."),
			sfx.call(63.45, SFX % "title_hit", -3.0),
			{"at": 63.5, "do": "title", "text": "RAGOON CITY", "t": 3.6},
			narr.call(67.2, 7, "Two strangers drove into it at the same moment. A paramedic, finishing his last call..."),
			sfx.call(74.09, SFX % "flatline", -10.0),
			line.call(84.09, "zegan", "z_lc_radio", "Dispatch, Medic Twelve. No pulse, no response... I'm bringing him in."),
			sfx.call(88.99, SFX % "radio_static", -6.0),
			sub.call(91.16, "zegan", "...Dispatch?", 1.4),
			narr.call(94.18, 8, "...and a courier, carrying a sealed package addressed to the Archive."),
			sfx.call(100.84, SFX % "sheet_rise", -4.0),
			sfx.call(105.64, GAME_SFX % "zombie_attack_1", -2.0),
			line.call(105.84, "zegan", "z_lc_grab", "No... NO! GET OFF ME!"),
			sfx.call(108.64, SFX % "skid", -6.0),
			sfx.call(114.08, SFX % "ambulance", -6.0),
		]},
		# The crash, Obcera pulling him out of the dead man's hands, and the
		# talk by the wreck: her brother's note, his reason to come, their names.
		{"do": "video", "file": VIDEO % "intro_b", "hold": true, "cues": [
			sfx.call(0.55, SFX % "crash", 0.0),
			{"at": 1.4, "do": "loop", "file": SFX % "fire", "vol": -14.0},
			{"at": 8.59, "do": "say", "who": "zegan", "line": "z_lc_help", "text": "HELP! SOMEBODY HELP ME!", "vol": -3.0},
			sfx.call(16.12, GAME_SFX % "zombie_attack_3", -3.0),
			line.call(16.72, "zegan", "z_lc_strain", "Get... OFF!"),
			line.call(20.27, "obcera", "o_lc_off", "GET OFF HIM!"),
			sfx.call(21.31, SFX % "door_hit", 0.0),
			sfx.call(22.06, GAME_SFX % "melee_hit_1", 0.0),
			line.call(28.8, "obcera", "lc_1", "You alive? Or are you gonna bite me too?"),
			line.call(32.8, "zegan", "lc_2", "Ask me again in a minute."),
			sub.call(35.83, "zegan", "My patient... he was dead. He was dead, and he sat up.", 5.4),
			line.call(41.34, "obcera", "lc_3", "Yeah. The whole street's doing it."),
			line.call(49.23, "zegan", "z_lc_that", "You nearly died... for that?"),
			line.call(52.16, "obcera", "o_lc_brother", "My brother sent it. Nasri. First word from him in two years."),
			sub.call(57.49, "obcera", "One line with it: \"Put it in my hands at the Archive. Tonight. Tell no one.\"", 6.3),
			line.call(64.42, "zegan", "z_lc_shelter", "The Archive's the storm shelter. Half the district went there."),
			line.call(68.42, "obcera", "o_lc_come", "Then they'll need a medic. And I need somebody watching my back. Come with me."),
			line.call(73.49, "zegan", "z_lc_lost", "I couldn't save him. I'm not losing anybody else tonight."),
			line.call(82.69, "obcera", "o_lc_name", "Obcera."),
			line.call(83.79, "zegan", "z_lc_name", "Zegan."),
		]},
		{"do": "wait", "t": 0.6},
		# Into the engine: the wreck burning in the rain, the two of them on
		# their feet, then both turn to the Archive at the end of the street.
		{"do": "fade", "to": 1.0, "t": 0.0},
		{"do": "call", "fn": "_intro_stage"},
		{"do": "bars", "on": true, "t": 0.0},
		{"do": "cam", "pos": Vector3(-3.6, 0.45, -24.2), "look": WRECK + Vector3(0.6, 1.0, 0.0), "fov": 50.0},
		{"do": "cam", "pos": Vector3(-3.1, 0.8, -23.4), "look": WRECK + Vector3(0.8, 1.3, 0.2), "t": 5.0, "block": false},
		{"do": "fade", "to": 0.0, "t": 1.6},
		{"do": "shake", "amount": 0.015, "t": 2.5},
		{"do": "wait", "t": 2.6},
		{"do": "cam", "pos": Vector3(1.4, 1.5, -21.2), "look": Vector3(-1.75, 1.3, -23.2), "fov": 46.0},
		{"do": "cam", "pos": Vector3(1.0, 1.55, -21.6), "look": Vector3(-1.75, 1.35, -23.1), "t": 3.6, "block": false},
		{"do": "wait", "t": 0.5},
		{"do": "call", "fn": "_gesture", "args": ["obcera", "call"]},
		{"do": "call", "fn": "_face_gates"},
		{"do": "wait", "t": 2.6},
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
		{"do": "say", "who": "obcera", "line": "o_gate_nasri", "text": "Nasri's in there. He has to be."},
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
		# He goes back the way he came: across the reading room to the staff
		# stair door, which slams and is bolted behind him. (That door stays
		# bolted: the room is empty when they get in.)
		{"do": "call", "fn": "_tally_leave", "wait": false},
		{"do": "wait", "t": 3.2},
		{"do": "cam", "pos": Vector3(-17.7, 1.6, 7.5), "look": Vector3(-15.9, 1.5, 6.4), "fov": 48.0},
		{"do": "call", "fn": "_act", "args": ["zegan", "talk/talk_open"], "wait": false},
		{"do": "say", "who": "zegan", "line": "z_glass_what", "text": "What the hell was that?"},
		{"do": "cam", "pos": Vector3(-17.5, 1.6, 7.45), "look": Vector3(-15.9, 1.5, 6.4), "fov": 45.0, "t": 4.5, "block": false},
		{"do": "wait", "t": 2.9},
		{"do": "call", "fn": "_turn_to", "args": ["zegan", PANE + Vector3(-2.0, 0, -2.0)], "wait": false},
		{"do": "call", "fn": "_turn_to", "args": ["obcera", PANE + Vector3(-2.0, 0, -2.0)], "wait": false, "delay": 0.2},
		{"do": "wait", "t": 1.4},
		{"do": "call", "fn": "_act", "args": ["obcera", "talk/talk_raise"], "wait": false},
		{"do": "say", "who": "obcera", "line": "o_glass_big", "text": "Something big. Don't let it see us."},
		{"do": "wait", "t": 0.8},
		{"do": "fade", "to": 1.0, "t": 0.6},
	]

## Warden Hardass in the archivist's office. He has kept watch in the
## armchair by the door for three nights; he stops them, checks them for the
## fever, says who he is, what happened to his shelter, what Nasri was doing
## in the vault, who the thing behind the glass was, and what City Hall
## wanted. Zegan sees the bite; he hides it. He gives them his key card and
## goes back to his chair to keep the count.
func _warden() -> Array:
	var H := HARDASS_TALK
	var Z := WARDEN_Z
	var O := WARDEN_O
	var P := HARDASS_POST
	_cam_avoid = [H, Z, O, warden_chair()[0]]
	_cam_room = Rect2(12.3, 0.3, 7.4, 7.4)   # the archivist's office, inside its walls
	var card := "h1_card_on" if VaultCircuit.is_on() else "h1_card"
	var card_text := "The vault elevator goes down to the old service tunnels. That's where he went. " + \
		("You've got the power back on. Take my card." if VaultCircuit.is_on() else "It needs power. The breaker's in the boiler room. Take my card.")
	# His good hand, held out to Zegan with the card on the palm.
	var card_len := _voice_len(card, 7.5)
	var fwd := Vector3(Z.x - H.x, 0, Z.z - H.z).normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var palm := H + fwd * 0.66 + Vector3.UP * 1.15
	var steps: Array = [
		{"do": "call", "fn": "_warden_stage"},
		{"do": "bars", "on": true, "t": 0.4, "wait": false},
		# In through the door; he is in the armchair beside it, watching it.
		{"do": "cam", "pos": Vector3(17.0, 1.72, 3.2), "look": Vector3(13.3, 1.05, 3.7), "fov": 50.0},
		{"do": "cam", "pos": Vector3(16.6, 1.66, 3.3), "look": Vector3(13.4, 1.0, 3.8), "fov": 48.0, "t": 4.0, "block": false},
		{"do": "wait", "t": 1.2},
		{"do": "call", "fn": "_h_rise", "wait": false},
		{"do": "call", "fn": "_turn_to", "args": ["zegan", P], "wait": false, "delay": 0.3},
		{"do": "call", "fn": "_turn_to", "args": ["obcera", P], "wait": false, "delay": 0.5},
		{"do": "say", "who": "hardass", "line": "h1_stop", "text": "Stop. Right there.", "gap": 0.4},
		# Up out of the chair and a step towards them, a hand up.
		_ots(Z, "zegan", P, "hardass", 1.0, 44.0),
		{"do": "wait", "t": 1.6},
		{"do": "call", "fn": "_h_step_in"},
		{"do": "call", "fn": "_turn_to", "args": ["zegan", H], "wait": false},
		{"do": "call", "fn": "_turn_to", "args": ["obcera", H], "wait": false},
		_close(H, "hardass", Z - H, 1.35, 42.0, -0.12),
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_raise"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_eyes", "text": "Into the light. Let me see your eyes."},
		# He looks them over: Zegan, then Obcera.
		_ots(H, "hardass", Z, "zegan", 1.0, 40.0),
		{"do": "call", "fn": "_h_loop", "args": ["talk/listen"]},
		{"do": "call", "fn": "_h_face", "args": [O, 0.8], "delay": 2.8, "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_clean", "text": "No grey in the skin. No dark veins at the temples... Alright. You're clean.", "gap": 0.3},
		{"do": "call", "fn": "_h_face", "args": [Z, 0.6], "wait": false},
		_close(Z, "zegan", H - Z, 1.3, 40.0, 0.1),
		{"do": "call", "fn": "_act", "args": ["zegan", "talk/talk_right"], "wait": false},
		{"do": "say", "who": "zegan", "line": "z1_who", "text": "I'm a paramedic. Who's in charge here?"},
		# Who he is, and what happened to the shelter.
		_close(H, "hardass", (Z + O) / 2.0 - H, 1.4, 40.0, 0.0),
		{"do": "call", "fn": "_h_face", "args": [(Z + O) / 2.0, 0.5], "wait": false},
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_right"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_name", "text": "You're looking at him. Jackson Hardass. Twenty years on this building's security desk."},
		_push_in(_close(H, "hardass", (Z + O) / 2.0 - H, 1.4, 40.0, 0.0), H, "hardass", 1.15, 8.0),
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_open"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_shelter", "text": "Three nights ago the city made this place a storm shelter. Forty-one people came through those gates. I counted every one of them in."},
		_close(O, "obcera", H - O, 1.3, 40.0, -0.1),
		{"do": "call", "fn": "_act", "args": ["obcera", "talk/talk_open"], "wait": false},
		{"do": "say", "who": "obcera", "line": "o1_empty", "text": "Forty-one people? We didn't see anyone alive out there."},
		_close(H, "hardass", O - H, 1.25, 40.0, 0.1),
		{"do": "call", "fn": "_h_once", "args": ["talk/headache"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_fever", "text": "The fever came in with them. Two days asleep... then they wake up hungry.", "gap": 0.4},
		# He looks back out through the door, at the hall full of his dead.
		{"do": "call", "fn": "_h_face", "args": [HARDASS_WATCH + Vector3(-2.0, 0, 0), 1.0], "wait": false},
		{"do": "cam", "pos": Vector3(15.3, 1.62, 3.4), "look": Vector3(12.0, 1.35, 2.9), "fov": 46.0},
		{"do": "cam", "pos": Vector3(15.05, 1.6, 3.35), "look": Vector3(12.0, 1.35, 2.9), "fov": 43.0, "t": 5.0, "block": false},
		{"do": "wait", "t": 0.6},
		{"do": "say", "who": "hardass", "line": "h1_never", "text": "Most of my forty-one never left this building.", "gap": 0.6},
		# Nasri.
		{"do": "call", "fn": "_h_face", "args": [O, 0.7], "wait": false},
		_ots(H, "hardass", O, "obcera", -1.0, 40.0),
		{"do": "call", "fn": "_act", "args": ["obcera", "talk/talk_right"], "wait": false},
		{"do": "say", "who": "obcera", "line": "o1_nasri", "text": "I'm looking for my brother. Nasri. He works in records."},
		_close(H, "hardass", O - H, 1.4, 40.0, -0.1),
		_push_in(_close(H, "hardass", O - H, 1.4, 40.0, -0.1), H, "hardass", 1.1, 22.0, -0.1),
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_right"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_nasri1", "text": "Nasri. Good man. Pulled some old files for the city doctor, and hasn't slept since."},
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_open"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_nasri2", "text": "Eighteen ninety-one. The same fever, the same sleep. He spent his nights in the vault copying the old burial records. Kept saying the numbers didn't add up.", "gap": 0.4},
		{"do": "call", "fn": "_h_loop", "args": ["talk/listen"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_nasri3", "text": "Two days ago he went down there and never came back up. Orrin, our night keeper, went after him.", "gap": 0.4},
	]
	# The thing behind the reading room glass, if they have seen it.
	if GameState.has_flag("story_glass"):
		steps += [
			_close(Z, "zegan", H - Z, 1.3, 40.0, 0.1),
			{"do": "call", "fn": "_act", "args": ["zegan", "talk/talk_open"], "wait": false},
			{"do": "say", "who": "zegan", "line": "z1_glass", "text": "Something big walked past the reading room glass. Dragging a hook."},
		]
	steps += [
		_low(H, "hardass", (Z + O) / 2.0 - H, 1.3, 38.0),
		{"do": "call", "fn": "_h_once", "args": ["talk/talk_raise"], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_orrin", "text": "Orrin came back. He isn't Orrin anymore. If you hear counting in the dark... you move.", "gap": 0.5},
		# The package, and City Hall.
		_close(O, "obcera", H - O, 1.25, 40.0, -0.1),
		{"do": "call", "fn": "_show_package", "wait": false},
		{"do": "say", "who": "obcera", "line": "o1_package", "text": "Nasri sent me this. Sealed. I'm putting it in his hands."},
		{"do": "cam", "pos": Vector3(14.95, 1.7, 1.15), "look": Vector3(13.35, 1.25, 3.2), "fov": 50.0},
		{"do": "cam", "pos": Vector3(14.75, 1.68, 1.3), "look": Vector3(13.35, 1.25, 3.2), "fov": 47.0, "t": 10.0, "block": false},
		{"do": "call", "fn": "_h_for", "args": ["talk/talk_angry", 9.6], "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_cityhall", "text": "Then don't let anyone else get their hands on it. City Hall radioed twice before the lines went dead. Not to send help. To ask if the vault was still locked.", "gap": 0.5},
		# Zegan sees the bite on his wrist; he pulls the hand away.
		_ots(Z, "zegan", H, "hardass", -1.0, 44.0),
		{"do": "call", "fn": "_h_face", "args": [Z, 0.5], "wait": false},
		{"do": "call", "fn": "_act", "args": ["zegan", "talk/talk_right"], "wait": false},
		{"do": "say", "who": "zegan", "line": "z1_wrist", "text": "Your wrist's bleeding. Let me look at that.", "gap": 0.1},
		{"do": "call", "fn": "_h_pull_back", "wait": false},
		{"do": "say", "who": "hardass", "line": "h1_scratch", "text": "It's a scratch. Leave it.", "gap": 0.6},
		# His key card, held out in his good hand.
		{"do": "cam", "pos": Vector3(14.6, 1.45, 1.55), "look": Vector3(13.4, 1.2, 3.25), "fov": 46.0},
		# The hand comes out on "Take my card"; then a look at it on his palm.
		{"do": "call", "fn": "_h_hand_over", "wait": false, "delay": maxf(card_len - 4.4, 0.0)},
		{"do": "cam", "pos": palm + right * 0.42 + Vector3.UP * 0.3 - fwd * 0.08, "look": palm, "fov": 34.0, "delay": maxf(card_len - 1.2, 0.0), "wait": false},
		{"do": "say", "who": "hardass", "line": card, "text": card_text, "gap": 0.45},
		_close(O, "obcera", H - O, 1.2, 40.0, -0.1),
		{"do": "call", "fn": "_act", "args": ["obcera", "talk/talk_raise"], "wait": false},
		{"do": "say", "who": "obcera", "line": "o1_come", "text": "Come with us.", "gap": 0.5},
		# Back to his chair, to keep watch on the door.
		{"do": "call", "fn": "_turn_to", "args": ["zegan", P], "wait": false, "delay": 0.6},
		{"do": "call", "fn": "_turn_to", "args": ["obcera", P], "wait": false, "delay": 0.8},
		{"do": "cam", "pos": Vector3(12.55, 1.85, 1.3), "look": Vector3(14.15, 1.0, 4.55), "fov": 46.0},
		{"do": "call", "fn": "_h_sit_back", "wait": false},
		{"do": "wait", "t": 1.6},
		{"do": "say", "who": "hardass", "line": "h1_keep", "text": "Somebody has to keep the count... Go. Find your brother.", "gap": 1.0},
		{"do": "cam", "pos": Vector3(12.75, 1.8, 1.6), "look": Vector3(14.15, 0.95, 4.6), "fov": 40.0, "t": 3.0, "block": false},
		{"do": "wait", "t": 1.8},
		{"do": "fade", "to": 1.0, "t": 0.7},
	]
	return steps

## A camera on one face, from `dir` (flat, from them towards the camera) at
## `dist` metres: the top of the head sits just under the letterbox bar
## whatever the lens, and `side` (metres) moves them off centre (positive:
## to the right of frame). The camera swings round them (or comes closer)
## until nobody in the scene stands at it or between it and the face.
func _close(at: Vector3, who: String, dir: Vector3, dist: float, fov := 40.0, side := 0.0) -> Dictionary:
	var off := _clear_spot(at, Vector3(dir.x, 0, dir.z).normalized(), dist)
	var d := off.normalized()
	var top: float = EYE.get(who, 1.65) + 0.13
	var half := off.length() * tan(deg_to_rad(fov / 2.0)) * (1.0 - 2.0 * BARS)
	var look_h := top + 0.06 - half
	var right := Vector3(d.z, 0, -d.x)   # the camera's right, looking back along -d
	return {"do": "cam", "pos": at + off + Vector3.UP * (look_h + 0.05), "look": at + Vector3.UP * look_h - right * side, "fov": fov}

## The same from a little below the eye line, looking up: a warning.
func _low(at: Vector3, who: String, dir: Vector3, dist: float, fov := 38.0) -> Dictionary:
	var c := _close(at, who, dir, dist, fov)
	c["pos"] = c["pos"] - Vector3.UP * 0.22
	return c

## Over `near`'s shoulder (side 1: their right) onto `far`'s face. Far enough
## behind them that their shoulder frames the shot instead of filling it.
func _ots(near: Vector3, near_who: String, far: Vector3, far_who: String, side := 1.0, fov := 38.0) -> Dictionary:
	var f := Vector3(far.x - near.x, 0, far.z - near.z).normalized()
	var right := Vector3(-f.z, 0, f.x)
	var pos: Vector3 = near - f * 0.85 + right * 0.42 * side + Vector3.UP * (float(EYE.get(near_who, 1.65)) + 0.04)
	var dist := Vector3(far.x - pos.x, 0, far.z - pos.z).length()
	var top: float = EYE.get(far_who, 1.65) + 0.13
	var half := dist * tan(deg_to_rad(fov / 2.0)) * (1.0 - 2.0 * BARS)
	return {"do": "cam", "pos": pos, "look": far + Vector3.UP * (top + 0.06 - half) - right * 0.12 * side, "fov": fov}

## A slow move straight in on the same face (from where `c`, a _close shot of
## them, stands) to `dist` metres, over `t` seconds, keeping the head clear of
## the bar all the way.
func _push_in(c: Dictionary, at: Vector3, who: String, dist: float, t: float, side := 0.0) -> Dictionary:
	var p: Vector3 = c["pos"]
	var n := _close(at, who, p - at, dist, float(c["fov"]), side)
	n["t"] = t
	n["block"] = false
	return n

## Where the people (and the armchair) are while the scene is built, and the
## room the cameras stay inside.
var _cam_avoid: Array = []
var _cam_room := Rect2()

func _clear_spot(at: Vector3, d: Vector3, dist: float) -> Vector3:
	for k in [1.0, 0.85, 0.72]:
		for deg in [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0]:
			var off: Vector3 = d.rotated(Vector3.UP, deg_to_rad(deg)) * dist * k
			if _spot_ok(at, at + off):
				return off
	return d * dist

func _spot_ok(at: Vector3, p: Vector3) -> bool:
	if _cam_room.size != Vector2.ZERO and not _cam_room.has_point(Vector2(p.x, p.z)):
		return false
	var a := Vector2(at.x, at.z)
	var b := Vector2(p.x, p.z)
	for o in _cam_avoid:
		var q := Vector2(o.x, o.z)
		if q.distance_to(a) < 0.2:
			continue   # the one we are filming
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < 0.45:
			return false
	return true

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

## The film ends with Obcera pulling Zegan to his feet by the wreck, so the
## engine picks up with both of them standing there, facing each other.
func _intro_stage() -> void:
	_place("zegan", Vector3(-2.2, 0.0, -23.5), Vector3(-1.3, 0.0, -22.9))
	_place("obcera", Vector3(-1.3, 0.0, -22.9), Vector3(-2.2, 0.0, -23.5))

## Both turn toward the gates at the end of the street.
func _face_gates() -> void:
	get_tree().create_timer(0.6).timeout.connect(func():
		for ch in ["zegan", "obcera"]:
			var m := _model_of(ch)
			if m:
				var holder: Node3D = m.get_parent() if _player_of(ch) else m
				var from := holder.rotation.y
				var to := _yaw_to(holder.global_position, GATE)
				create_tween().tween_method(func(k: float): holder.rotation.y = lerp_angle(from, to, k),
						0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE))

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
	_listen("zegan")
	_listen("obcera")
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

## Across the reading room to the staff stair, through the door, which
## slams; then the bolt. The breathing and the scrape fade with him.
func _tally_leave() -> void:
	_scrape(-8.0)
	var door := _staff_door()
	var speeds := [0.95, 1.3, 1.15]
	var tw := _tally.create_tween()
	var from := _tally.global_position
	var yaw := _tally.rotation.y
	_tally.play("stalk", 0.3)
	for i in TALLY_EXIT.size():
		var to: Vector3 = TALLY_EXIT[i]
		var target := yaw + wrapf(_yaw_to(from, to) - yaw, -PI, PI)
		yaw = target
		tw.tween_property(_tally, "rotation:y", target, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_tally, "global_position", to, from.distance_to(to) / speeds[i])
		if i == 1 and door:
			# He pulls the door open and ducks through.
			tw.tween_callback(func(): door.swing(true, Vector3.LEFT))
			tw.tween_interval(0.7)
		from = to
	tw.tween_callback(func():
		for a in _tally.find_children("*", "AudioStreamPlayer3D", false, false):
			a.create_tween().tween_property(a, "volume_db", -60.0, 1.5))
	if door:
		tw.tween_callback(func():
			door.swing(false, Vector3.LEFT)
			Sfx.play_at("door_bang", STAFF_DOOR + Vector3.UP, "", 4.0, 14.0))
		tw.tween_interval(0.8)
		tw.tween_callback(func(): Sfx.play_at("bolt_shut", STAFF_DOOR + Vector3.UP * 1.2, "door_locked", 6.0, 14.0))

func _staff_door() -> Door:
	return get_tree().get_first_node_in_group("staff_stair_door") as Door

## The hook's marks: two dark scrapes side by side, dragged across the
## reading room floor from the pane to the staff stair door, over and over.
func _build_drag_marks() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.035, 0.0))
	g.set_color(1, Color(0.05, 0.04, 0.035, 0.0))
	g.add_point(0.35, Color(0.06, 0.05, 0.04, 0.75))
	g.add_point(0.5, Color(0.03, 0.025, 0.02, 0.9))
	g.add_point(0.65, Color(0.06, 0.05, 0.04, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 32
	tex.height = 8
	var pts: Array = [Vector3(-19.75, 0.0, 3.9)] + TALLY_EXIT.slice(0, 2)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir := (b - a).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var n := int(a.distance_to(b) / 0.9)
		for k in n:
			for prong in [-0.035, 0.035]:
				var d := Decal.new()
				d.texture_albedo = tex
				d.size = Vector3(0.05, 0.3, 0.75 + randf() * 0.25)
				var at: Vector3 = a.lerp(b, (k + 0.5) / n) + side * (0.55 + float(prong) + randf_range(-0.05, 0.05))
				d.position = at + Vector3.UP * 0.05
				d.rotation.y = atan2(dir.x, dir.z) + randf_range(-0.08, 0.08)
				d.modulate = Color(1, 1, 1, randf_range(0.55, 0.9))
				d.cull_mask = 1
				add_child(d)

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
	# Just inside the door, looking into the room.
	_place("zegan", WARDEN_Z, WARDEN_Z + Vector3(2.0, 0, 0.6))
	_place("obcera", WARDEN_O, WARDEN_O + Vector3(2.0, 0, 0.3))
	_listen("zegan")
	_listen("obcera")
	if _hardass:
		_h_reset()
		_hardass.global_position = HARDASS_POST
		_hardass.rotation.y = _yaw_to(HARDASS_POST, HARDASS_WATCH)
		_hardass.play("talk/sit_arms_crossed", 0.0)
		_talk.monitorable = false

# ---------------------------------------------------------------- the warden
# His moves are the "talk" clips (tools/import_talk.gd): sitting, getting up,
# talking with his hands, grief, pulling the bitten hand away, holding out the
# card. Every timed return to his idle carries a token, so a skipped scene
# (on_cutscene_end puts him back in his chair) is never undone by a late one.

var _h_tw: Tween
var _h_token := 0
var _card: Node3D

func _h_idle() -> String:
	return _hardass.idle_clip() if _hardass else "idle"

## Stops whatever he was in the middle of.
func _h_reset() -> void:
	_h_token += 1
	if _h_tw:
		_h_tw.kill()
		_h_tw = null
	if _hardass:
		_hardass.stop_walk()
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null

## Plays a clip, then back to standing after `secs` (default: the clip's own
## length), unless something else has started since.
func _h_play_then(clip: String, secs := -1.0, speed := 1.0, from := 0.0, then := "") -> void:
	if not _hardass or not _hardass.has_clip(clip):
		return
	_h_token += 1
	var tok := _h_token
	_hardass.play(clip, 0.25, speed, from)
	if secs < 0.0:
		secs = (_hardass.clip_length(clip) - from) / maxf(speed, 0.01) - 0.3
	var back := then if then != "" else _h_idle()
	get_tree().create_timer(maxf(secs, 0.1)).timeout.connect(func():
		if tok == _h_token and is_instance_valid(_hardass):
			_hardass.play(back, 0.35))

func _h_once(clip: String, speed := 1.0) -> void:
	_h_play_then(clip, -1.0, speed)

func _h_for(clip: String, secs: float) -> void:
	_h_play_then(clip, secs)

func _h_loop(clip: String) -> void:
	if _hardass and _hardass.has_clip(clip):
		_h_token += 1
		_hardass.play(clip, 0.35)

func _h_face(point: Vector3, t := 0.6) -> void:
	if _hardass:
		_hardass.face(point, t)

## Up out of the armchair onto his feet.
func _h_rise() -> void:
	_h_play_then("talk/sit_to_stand", -1.0, 1.35)

## A step towards them (his walk is the tired, injured one).
func _h_step_in() -> Signal:
	if not _hardass:
		return get_tree().process_frame
	_h_token += 1
	var clip := "injured_walk" if _hardass.has_clip("injured_walk") else "walk"
	var s := _hardass.walk_to(HARDASS_TALK, 0.75, clip, _h_idle())
	s.connect(func(): _h_face(WARDEN_Z, 0.5), CONNECT_ONE_SHOT)
	return s

## Zegan reaches for the bitten hand: he snatches it back against his chest.
## (Only the end of the clip, where he clutches the wrist: before that the
## clip flings both arms out.)
func _h_pull_back() -> void:
	_h_play_then("talk/hand_pull", -1.0, 0.7, 2.45)

## Holds his key card out in his good hand (the left: the bite is on the
## right). The card goes once his hand comes back.
func _h_hand_over() -> void:
	if not _hardass:
		return
	_h_play_then("talk/hand_over", -1.0, HAND_OVER_SPEED)
	_card = _key_card()
	if _card:
		var tok := _h_token
		get_tree().create_timer(_hardass.clip_length("talk/hand_over") * 0.62 / HAND_OVER_SPEED).timeout.connect(func():
			if tok == _h_token and is_instance_valid(_card):
				_card.queue_free())

## The hand-over is slowed so his hand stays out (clip 2.4-3.6 s) long
## enough for the insert shot.
const HAND_OVER_SPEED := 0.75

func _voice_len(line: String, fallback: float) -> float:
	var path := "res://assets/audio/voice/story/%s.ogg" % line
	if ResourceLoader.exists(path):
		return (load(path) as AudioStream).get_length()
	return fallback

## Obcera shows him Nasri's package (her right hand brings it up to her
## chest and out to him), then puts it away.
func _show_package() -> void:
	var m := _model_of("obcera")
	if m == null:
		return
	_act("obcera", "talk/talk_hip")
	var skel: Skeleton3D = m._skel
	if skel == null or skel.find_bone("RightHand") < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "RightHand"
	skel.add_child(att)
	_scene_bits.append(att)
	att.add_child(_package(skel))
	get_tree().create_timer(maxf(m.clip_length("talk/talk_hip") - 0.5, 0.5)).timeout.connect(func():
		if is_instance_valid(att):
			att.queue_free())

## Nasri's sealed package: a small brown-paper parcel tied with string. In the
## survivors' hand bone space (cm): fingers along +Y, palm facing -Z.
func _package(skel: Skeleton3D) -> Node3D:
	var holder := Node3D.new()
	var k := 1.0 / maxf(skel.global_transform.basis.get_scale().x, 0.0001)
	holder.scale = Vector3.ONE * k
	holder.position = Vector3(0.0, 8.5, -5.2)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.55, 0.42, 0.28)
	paper.roughness = 0.9
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.82, 0.78, 0.68)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.17, 0.05)
	box.mesh = bm
	box.material_override = paper
	holder.add_child(box)
	for along_y in [true, false]:
		var tie := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.006, 0.172, 0.052) if along_y else Vector3(0.122, 0.006, 0.052)
		tie.mesh = tm
		tie.material_override = string_mat
		holder.add_child(tie)
	var label := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.05, 0.03, 0.051)
	label.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.86, 0.82, 0.72)
	label.material_override = lmat
	label.position = Vector3(0.025, 0.045, 0.0)
	holder.add_child(label)
	return holder

## The vault key card in his left hand: white plastic, a dark stripe, the
## Archive's crest in red.
func _key_card() -> Node3D:
	var skel: Skeleton3D = _hardass.find_child("Skeleton3D", true, false)
	if skel == null or skel.find_bone("LeftHand") < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = "LeftHand"
	skel.add_child(att)
	var holder := Node3D.new()
	# Flat on the palm, along the fingers. In his hand bone's space (cm,
	# measured from the hand's vertices): the palm's middle is ~13.8 cm out
	# from the wrist along +Y and its face points along PALM. Meshy
	# armatures are scaled 0.01: the holder undoes it so the card is real size.
	const PALM := Vector3(0.86, -0.16, -0.48)
	var n := PALM.normalized()
	var along := Vector3(0.08, 0.99, -0.12)
	along = (along - n * along.dot(n)).normalized()
	var k := 1.0 / maxf(skel.global_transform.basis.get_scale().x, 0.0001)
	holder.transform = Transform3D(Basis(along, n.cross(along), n).scaled(Vector3.ONE * k), Vector3(0.94, 13.4, -0.1) + n * 1.6)
	att.add_child(holder)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.086, 0.054, 0.004)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.85, 0.8)
	mat.roughness = 0.45
	mi.material_override = mat
	holder.add_child(mi)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.086, 0.012, 0.0045)
	stripe.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.08, 0.08, 0.09)
	stripe.material_override = smat
	stripe.position.y = 0.012
	holder.add_child(stripe)
	var crest := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.016, 0.016, 0.0046)
	crest.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.6, 0.08, 0.06)
	crest.material_override = cmat
	crest.position = Vector3(-0.026, -0.01, 0)
	holder.add_child(crest)
	return att

## Back to the armchair: walks over, turns to face the door again, sits,
## folds his arms.
func _h_sit_back() -> void:
	if not _hardass:
		return
	_h_reset()
	var tok := _h_token
	var from := _hardass.global_position
	var walk := "injured_walk" if _hardass.has_clip("injured_walk") else "walk"
	_hardass.rotation.y = _yaw_to(from, HARDASS_POST)
	_hardass.play(walk, 0.3)
	var face := _yaw_to(HARDASS_POST, HARDASS_WATCH)
	var sit := "talk/stand_to_sit"
	var sit_speed := 1.15
	_h_tw = create_tween()
	_h_tw.tween_property(_hardass, "global_position", HARDASS_POST, from.distance_to(HARDASS_POST) / 0.7)
	_h_tw.tween_callback(func(): _hardass.play(_h_idle(), 0.3))
	_h_tw.tween_property(_hardass, "rotation:y", _hardass.rotation.y + wrapf(face - _hardass.rotation.y, -PI, PI), 0.8).set_trans(Tween.TRANS_SINE)
	_h_tw.tween_callback(func(): _hardass.play(sit, 0.3, sit_speed))
	_h_tw.tween_interval(_hardass.clip_length(sit) / sit_speed - 0.3)
	_h_tw.tween_callback(func():
		if tok == _h_token:
			_hardass.play("talk/sit_arms_crossed", 0.5))

# ---------------------------------------------------------------- survivors

## A survivor turns on the spot to face a point.
func _turn_to(ch: String, point: Vector3) -> void:
	var m := _model_of(ch)
	if m == null:
		return
	var holder: Node3D = m.get_parent() if _player_of(ch) else m
	var target := _yaw_to(holder.global_position, point)
	var tw := holder.create_tween()
	tw.tween_property(holder, "rotation:y", holder.rotation.y + wrapf(target - holder.rotation.y, -PI, PI), 0.6).set_trans(Tween.TRANS_SINE)
	var p := _player_of(ch)
	if p and p.is_multiplayer_authority():
		p.sync_yaw = target
		p.yaw = target

## A survivor stands still and listens (their own "talk/listen" loop, not
## the shared gameplay idle, which looks round over the shoulder).
func _listen(ch: String) -> void:
	var m := _model_of(ch)
	if m and m.has_clip("talk/listen"):
		m.act("talk/listen", 0.0)

## A survivor's line gesture (a "talk" clip), then they stand listening.
func _act(ch: String, clip: String) -> void:
	var m := _model_of(ch)
	if m == null or not m.has_clip(clip):
		return
	m.play_once(clip, 0.25)
	get_tree().create_timer(maxf(m.clip_length(clip) - 0.35, 0.1)).timeout.connect(func():
		if is_instance_valid(m) and m.current_clip() == clip:
			m.act("talk/listen"))

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
	sh.radius = 0.55
	sh.height = 1.6
	cs.shape = sh
	cs.position = Vector3(0, 0.8, 0.2)
	_talk.add_child(cs)
	_hardass.add_child(_talk)
	# His legs, stretched out in front of the armchair (the chair is a prop
	# with its own collider): nobody walks through him.
	var legs := StaticBody3D.new()
	legs.collision_layer = 1
	var ls := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(0.6, 0.6, 0.5)
	ls.shape = lb
	ls.position = Vector3(0, 0.3, 0.05)
	legs.add_child(ls)
	legs.position = HARDASS_POST
	legs.rotation.y = _yaw_to(HARDASS_POST, HARDASS_WATCH)
	add_child(legs)
	_hardass_at_rest()
	_talk.monitorable = GameState.has_flag("story_warden")

## Where the armchair goes (archive_hub builds it): behind his post, facing
## the door like him. [position, rotation in degrees] for RoomBuilder.prop.
static func warden_chair() -> Array:
	var f := (HARDASS_WATCH - HARDASS_POST).normalized()
	return [HARDASS_POST - f * WARDEN_SEAT_BACK, rad_to_deg(atan2(f.x, f.z))]

## In his armchair by the door, arms folded, watching it: where he waits
## for them, and where he goes back to after their talk.
func _hardass_at_rest() -> void:
	if not _hardass:
		return
	_h_reset()
	_hardass.global_position = HARDASS_POST
	_hardass.rotation.y = _yaw_to(HARDASS_POST, HARDASS_WATCH)
	_hardass.play("talk/sit_arms_crossed", 0.3)
	if _talk:
		_talk.monitorable = true

## Talking to Hardass after his scene: one of his lines, for this player
## only, from his chair.
var _talk_i := 0
func talk_to_hardass() -> void:
	var power := ["h1_t_power_on", "Power's on. The elevator's waiting. Go."] if VaultCircuit.is_on() \
		else ["h1_t_power", "The breaker's in the boiler room, through the vault. Then the elevator."]
	var lines := [power, ["h1_t_count", "Forty-one in. When you come back up, I'll count you two out."],
		["h1_t_orrin", "If you hear counting in the dark, you move. Don't stop to look."],
		["h1_t_nasri", "Nasri brought me coffee every night shift for nine years. Bring him back."]]
	var l: Array = lines[_talk_i % lines.size()]
	_talk_i += 1
	var dur := 3.5
	var a := _audio3d("res://assets/audio/voice/story/%s.ogg" % l[0], 0.0, false)
	if a:
		a.bus = "Voice"
		a.position.y = 1.2
		_hardass.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
		dur = a.stream.get_length()
	_h_play_then("talk/sit_talk", dur, 1.0, 0.0, "talk/sit_arms_crossed")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_subtitle("Warden Hardass", l[1], dur + 0.5)

const TalkArea := preload("res://scripts/story/talk_area.gd")
