extends Node
## Co-op call-outs: one player shouts for the other (to come to a door,
## help with a puzzle, or just to vent). Each character has normal (low voice)
## and scream variants. Audio files live in res://assets/audio/voice/<char>/
## named <line_id>.ogg; until recorded, the subtitle still shows.

signal callout_played(speaker_peer: int, character: String, line_id: String, text: String, scream: bool)

const LINES := {
	"zegan": {
		"normal": [
			{"id": "z_obcera_low", "text": "Obcera."},
			{"id": "z_over_here", "text": "Obcera, over here."},
			{"id": "z_need_you", "text": "I need you at this door."},
			{"id": "z_together", "text": "We open this together. Come on."},
			{"id": "z_cover_me", "text": "Cover me."},
			{"id": "z_follow", "text": "Stay close."},
			{"id": "z_help", "text": "Help me."},
			{"id": "z_go", "text": "Go."},
			{"id": "z_come", "text": "Come."},
		],
		"scream": [
			{"id": "z_beesh", "text": "OBCERA YOU BEEEESH!"},
			{"id": "z_come_mofuka", "text": "COME MOFUKA!"},
			{"id": "z_obcera_scream", "text": "OBCERAAA!"},
			{"id": "z_wtf", "text": "WHAT THE FUCK ARE YOU DOING YOU BEESH!"},
			{"id": "z_hurry", "text": "OBCERA, HURRY UP!"},
			{"id": "z_help_beesh", "text": "HELP YOU BEEESH!"},
		],
	},
	"obcera": {
		"normal": [
			{"id": "o_zegan_low", "text": "Zegan."},
			{"id": "o_over_here", "text": "Zegan, over here."},
			{"id": "o_need_you", "text": "Get to the door, I can't do this alone."},
			{"id": "o_on_three", "text": "On three. Ready?"},
			{"id": "o_cover_me", "text": "Watch my back."},
			{"id": "o_follow", "text": "This way."},
			{"id": "o_help", "text": "Help me."},
			{"id": "o_go", "text": "Go."},
			{"id": "o_come", "text": "Come."},
		],
		"scream": [
			{"id": "o_zegaan", "text": "ZEGAAAN!"},
			{"id": "o_mofuka_fast", "text": "ZEGAN MOFUKA COME FAST!"},
			{"id": "o_zaga", "text": "ZEGAN YOU ZAGA!"},
			{"id": "o_move", "text": "ZEGAN, MOVE IT!"},
			{"id": "o_where", "text": "WHERE THE HELL ARE YOU?!"},
			{"id": "o_help_beesh", "text": "HELP YOU BEEESH!"},
		],
	},
}

const COOLDOWN := 1.5
var _last_time := -10.0

func lines_for(character: String, scream: bool) -> Array:
	return LINES.get(character, {}).get("scream" if scream else "normal", [])

## Called by the local player's UI. Picks a random line unless one is given.
func call_partner(scream: bool, line_id: String = "") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_time < COOLDOWN:
		return
	_last_time = now
	var character := GameState.local_character()
	var pool := lines_for(character, scream)
	if pool.is_empty():
		return
	var line: Dictionary = pool.pick_random()
	if line_id != "":
		for l in pool:
			if l["id"] == line_id:
				line = l
	_rpc_play.rpc(character, line["id"], line["text"], scream)

@rpc("any_peer", "reliable", "call_local")
func _rpc_play(character: String, line_id: String, text: String, scream: bool) -> void:
	var speaker := multiplayer.get_remote_sender_id()
	if speaker == 0:
		speaker = multiplayer.get_unique_id()
	var player := _player_for(speaker)
	var path := "res://assets/audio/voice/%s/%s.ogg" % [character, line_id]
	if ResourceLoader.exists(path) and player:
		var a := AudioStreamPlayer3D.new()
		a.stream = load(path)
		a.unit_size = 18.0 if scream else 8.0
		a.max_db = 6.0 if scream else 0.0
		a.bus = "Voice"
		player.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	callout_played.emit(speaker, character, line_id, text, scream)
	# Zombies hear screams.
	if scream and player:
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.global_position.distance_to(player.global_position) < 22.0:
				z.hear_noise(player.global_position)

func _player_for(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null
