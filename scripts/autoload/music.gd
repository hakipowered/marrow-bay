extends Node
## Game music. One track plays at a time and changes with a crossfade.
## Each track loops by fading into its own start a few seconds before the end,
## so there is never a gap. In game the track is chosen by priority:
## boss fight > FIGHT_TRACK (a big fight: a brute, a crowd, the Tallyman on
## you; none for now) > safe room > none.
## Ordinary infected get no music, only the ambience and a low string bed
## (HorrorDirector): a couple of shamblers aren't a battle.
## With no track, only the HorrorDirector's ambience plays.

const DIR := "res://assets/audio/music/%s.ogg"
const FADE := 2.5
const LOOP_OVERLAP := 4.0
## The track for a big fight (a brute and more, a horde breaking in, the
## awake Tallyman on her). Empty: fights play no music, only the ambience and
## the infected themselves. Bulmaim hated "action" (0.10 playtest), so it's
## out until there's a fight track he picks.
const FIGHT_TRACK := ""
## Which theme each boss uses. Bosses not listed use boss_2.
const BOSS_THEMES := {"brood_mother": "boss_1"}
## Action music starts at this threat score and stops after it has stayed
## below ACTION_OFF for ACTION_HOLD seconds.
const ACTION_ON := 6.0
const ACTION_OFF := 3.0
const ACTION_HOLD := 9.0

var in_game := false
var in_safe_room := false
## A cutscene's score. While set it wins over everything else.
var override_track := ""
var boss := ""
var threat := 0.0

var _players: Array[AudioStreamPlayer] = []
var _cur := -1
var _track := ""
var _fades := {}
var _action := false
var _calm_t := 0.0
var _forced_action := 0.0
var _streams := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.bus = "Music"
		a.volume_db = -80.0
		add_child(a)
		_players.append(a)

## Title screen.
func play_menu() -> void:
	in_game = false
	_set_beat(true)
	_set_track("menu_theme")

## Bass energy of the music, 0..1, for the title screen's pulse.
func beat() -> float:
	var fx := _analyzer()
	if fx == null:
		return 0.0
	var m: Vector2 = fx.get_magnitude_for_frequency_range(30.0, 160.0)
	return clamp((linear_to_db(max(m.length(), 0.00001)) + 42.0) / 28.0, 0.0, 1.0)

func _analyzer() -> AudioEffectSpectrumAnalyzerInstance:
	var bus := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectSpectrumAnalyzer and AudioServer.is_bus_effect_enabled(bus, i):
			return AudioServer.get_bus_effect_instance(bus, i)
	return null

func _set_beat(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectSpectrumAnalyzer:
			AudioServer.set_bus_effect_enabled(bus, i, on)

## A level has started: clear the old fight state and let the game pick.
func enter_game() -> void:
	in_game = true
	_set_beat(false)
	in_safe_room = false
	boss = ""
	threat = 0.0
	_action = false
	_forced_action = 0.0
	_set_track("")

## Scripted fights (a horde breaking in, an ambush) can hold the action music.
func force_action(seconds: float) -> void:
	_forced_action = max(_forced_action, seconds)

func current_track() -> String:
	return _track

## Whether the game counts this as a big fight (FIGHT_TRACK plays when set).
func fighting() -> bool:
	return _action

func _process(delta: float) -> void:
	if in_game:
		_forced_action = max(0.0, _forced_action - delta)
		if threat >= ACTION_ON or _forced_action > 0.0:
			_action = true
			_calm_t = 0.0
		elif _action and threat < ACTION_OFF:
			_calm_t += delta
			if _calm_t > ACTION_HOLD:
				_action = false
		var want := ""
		if boss != "":
			want = BOSS_THEMES.get(boss, "boss_2")
		elif _action and FIGHT_TRACK != "":
			want = FIGHT_TRACK
		elif in_safe_room:
			want = "safe_room"
		if override_track != "":
			want = override_track
		_set_track(want)
	_loop_check()
	_run_fades(delta)

func _set_track(id: String) -> void:
	if id == _track:
		return
	_track = id
	if _cur >= 0:
		_fade(_players[_cur], -80.0, FADE, true)
	if id == "":
		_cur = -1
		return
	var s := _stream(id)
	if s == null:
		_cur = -1
		return
	_cur = 1 - _cur if _cur >= 0 else 0
	_start(_players[_cur], s, FADE)

func _start(a: AudioStreamPlayer, s: AudioStream, fade: float) -> void:
	a.stream = s
	a.volume_db = -40.0
	a.play()
	_fade(a, 0.0, fade, false)

## Near the end of the track, start it again on the other player and crossfade.
func _loop_check() -> void:
	if _cur < 0:
		return
	var a := _players[_cur]
	if not a.playing or a.stream == null:
		return
	var length := a.stream.get_length()
	if length <= LOOP_OVERLAP * 2.0:
		return
	if a.get_playback_position() >= length - LOOP_OVERLAP:
		_fade(a, -80.0, LOOP_OVERLAP, true)
		_cur = 1 - _cur
		_start(_players[_cur], a.stream, LOOP_OVERLAP * 0.6)

func _fade(a: AudioStreamPlayer, to_db: float, secs: float, stop_after: bool) -> void:
	_fades[a] = {"from": db_to_linear(a.volume_db), "to": db_to_linear(to_db), "t": 0.0, "secs": max(secs, 0.01), "stop": stop_after}

func _run_fades(delta: float) -> void:
	for a in _fades.keys():
		var f: Dictionary = _fades[a]
		f["t"] += delta
		var k: float = clamp(f["t"] / f["secs"], 0.0, 1.0)
		# Equal-power curve so a crossfade doesn't dip in the middle.
		var lin: float = lerp(f["from"], f["to"], sin(k * PI * 0.5) if f["to"] > f["from"] else 1.0 - cos(k * PI * 0.5))
		a.volume_db = linear_to_db(max(lin, 0.0001))
		if k >= 1.0:
			_fades.erase(a)
			if f["stop"]:
				a.stop()

func _stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var path := DIR % id
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	_streams[id] = s
	return s
