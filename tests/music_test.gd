extends SceneTree
## Checks the music state machine: menu, action on/off (only for big fights
## since 0.10), boss, safe room, seamless loop.

var _t := 0.0
var _step := 0
var _fails := 0
var music: Node

func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_fails += 1

func _process(delta: float) -> bool:
	if music == null:
		music = root.get_node("Music")
		music.play_menu()
		return false
	_t += delta
	match _step:
		0:
			if _t > 0.5:
				_check(music.current_track() == "menu_theme", "menu theme on title screen")
				_check(music._players[music._cur].playing, "menu player is playing")
				music.enter_game()
				_step = 1; _t = 0.0
		1:
			if _t > 0.2:
				_check(music.current_track() == "", "no music when exploring")
				music.threat = 4.0   # a few ordinary infected: the ambience carries it
				_step = 15; _t = 0.0
		15:
			if _t > 0.2:
				_check(music.current_track() == "" and not music.fighting(), "no fight for a few shamblers")
				music.threat = 7.0   # a brute, a charger, or a big breach
				_step = 2; _t = 0.0
		2:
			if _t > 0.2:
				_check(music.fighting() and music.current_track() == music.FIGHT_TRACK, "a big fight plays the fight track ('%s')" % music.FIGHT_TRACK)
				music.threat = 0.0
				_step = 3; _t = 0.0
		3:
			if _t > 3.0 and _t < 3.2:
				_check(music.fighting() and music.current_track() == music.FIGHT_TRACK, "the fight holds after the last blow")
			if _t > 10.0:
				_check(music.current_track() == "" and not music.fighting(), "the fight ends after calm")
				music.boss = "brood_mother"
				_step = 4; _t = 0.0
		4:
			if _t > 0.2:
				_check(music.current_track() == "boss_1", "brood mother gets boss theme 1")
				music.boss = "warden"
				_step = 5; _t = 0.0
		5:
			if _t > 0.2:
				_check(music.current_track() == "boss_2", "other bosses get boss theme 2")
				music.boss = ""
				music.in_safe_room = true
				_step = 6; _t = 0.0
		6:
			if _t > 3.0:
				_check(music.current_track() == "safe_room", "safe room music")
				var a: AudioStreamPlayer = music._players[music._cur]
				_check(a.volume_db > -1.0, "safe room faded in (%.1f dB)" % a.volume_db)
				_check(not music._players[1 - music._cur].playing, "previous track stopped")
				a.seek(a.stream.get_length() - 4.5)
				_step = 7; _t = 0.0
		7:
			if _t > 1.5:
				var a: AudioStreamPlayer = music._players[music._cur]
				_check(a.get_playback_position() < 3.0, "loop restarted from the top (pos %.1f)" % a.get_playback_position())
				_check(music._players[1 - music._cur].playing, "old tail still fading out")
				_step = 8; _t = 0.0
		8:
			if _t > 5.0:
				_check(not music._players[1 - music._cur].playing, "tail stopped after the overlap")
				print("MUSIC %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
				return true
	return false
