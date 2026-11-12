extends Node
## Cutscene player (autoload "Cutscenes").
##
## A cutscene is a list of steps that the level's story node hands over
## (see Chapter1Story.cutscene()). The host starts it for everyone; each
## phone then plays the same timeline locally, so both players see it at the
## same moment. Players can't move, the infected freeze, the HUD hides.
## Anyone can tap Skip; in co-op the scene skips once both players have.
## Whatever a cutscene changes in the world (flags, items, the objective,
## where people stand) is done in the story node's on_cutscene_end(), which
## always runs, so a skipped scene leaves the game in the same state.
##
## Steps are dictionaries with a "do" key:
##   fade      {to: 0..1 (1 = black), t}
##   bars      {on: bool, t}                     cinematic letterbox
##   video     {file, audio?, t?, hold?, cues?}  full-screen clip (Ogg Theora);
##             cues are steps with "at" (seconds into the clip), fired on the
##             clip's own clock: narration, sounds, title cards
##   say       {who, line, text}                 voice line + subtitle (waits for it)
##   sub       {who, text, t}                    subtitle only
##   sfx       {file, vol?}                      one-shot, 2D
##   loop      {file, vol?}                      ambience until the scene ends
##   music     {track}                           music override ("" = back to normal)
##   wait      {t}
##   title     {text, sub?, t}                   big centred title card
##   chapter   {num, name}                       chapter card
##   cam       {pos, look, fov?, t?, from?: [pos, look]}   cut (t = 0) or glide
##   shake     {amount, t}
##   call      {fn, args?}                       a function on the story node
##   objective {text}
## Any step can carry "delay" (seconds before it runs) and "wait": false (run
## in the background so the next step starts at once).

signal started(id: String)
signal finished(id: String)
signal all_peers_ready
signal objective_changed(text: String)

const VOICE := "res://assets/audio/voice/story/%s.ogg"
const SPEAKERS := {
	"narrator": ["", Color(0.88, 0.85, 0.78)],
	"zegan": ["ZEGAN", Color(0.58, 0.86, 0.62)],
	"obcera": ["OBCERA", Color(1.0, 0.56, 0.52)],
	"hardass": ["WARDEN HARDASS", Color(0.7, 0.8, 1.0)],
	"tallyman": ["???", Color(1.0, 0.62, 0.3)],
	"naghal": ["DEPUTY MAYOR NAGHAL", Color(0.95, 0.85, 0.5)],
}

var active := false
var current := ""
var _skip := false
var _skip_votes := {}
var _ready_peers := {}
var _token := 0
var _story: Node
var _frozen: Array = []
var _hidden: Array = []
const HIDE_NEAR_CAM := 14.0
var _hud_visible := true

var _layer: CanvasLayer
var _root: Control
var _black: ColorRect
var _video_bg: ColorRect
var _video: VideoStreamPlayer
var _bars: Array[ColorRect] = []
var _fade: ColorRect
var _sub_box: PanelContainer
var _sub_name: Label
var _sub_text: Label
var _title: Label
var _title_sub: Label
var _skip_btn: Button
var _skip_hint: Label
var _obj_box: PanelContainer
var _obj_label: Label
var _cam: Camera3D
var _cam_tween: Tween
var _shake := 0.0
var _shake_t := 0.0
var _cam_base := Transform3D()
var _voice: AudioStreamPlayer
var _loops: Array[AudioStreamPlayer] = []
var _sub_until := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	Net.partner_left.connect(func(_id):
		if active and multiplayer.is_server():
			_check_votes())

# ------------------------------------------------------------------ session

## LevelBase calls this when its scene is built. The host waits until every
## player's phone has loaded the level before it starts a scene.
func level_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(1)
	else:
		_rpc_ready.rpc_id(1)

func level_left() -> void:
	_ready_peers.clear()
	if active:
		_teardown()

@rpc("any_peer", "reliable")
func _rpc_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(multiplayer.get_remote_sender_id())

func _mark_ready(id: int) -> void:
	_ready_peers[id] = true
	if all_ready():
		all_peers_ready.emit()

func all_ready() -> bool:
	for id in GameState.character_by_peer:
		if not _ready_peers.has(id):
			return false
	return true

## Host (or solo): start a cutscene for everyone. A client asking is
## forwarded to the host.
func play(id: String) -> void:
	if multiplayer.is_server():
		_rpc_play.rpc(id)
	else:
		_rpc_request.rpc_id(1, id)

@rpc("any_peer", "reliable")
func _rpc_request(id: String) -> void:
	if multiplayer.is_server() and not active:
		_rpc_play.rpc(id)

@rpc("authority", "reliable", "call_local")
func _rpc_play(id: String) -> void:
	if active:
		return
	_story = get_tree().get_first_node_in_group("story")
	if _story == null or not _story.has_method("cutscene"):
		return
	var steps: Array = _story.cutscene(id)
	if steps.is_empty():
		_story.call("on_cutscene_end", id)
		return
	_start(id, steps)
	await _run(steps, _token)
	if current == id and active:
		_end()

# ------------------------------------------------------------------ skipping

func _on_skip_pressed() -> void:
	if not active or _skip:
		return
	_skip_btn.disabled = true
	if Net.is_coop():
		_skip_btn.text = "Waiting for partner..."
	if multiplayer.is_server():
		_vote(1)
	else:
		_rpc_vote.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_vote() -> void:
	if multiplayer.is_server():
		_vote(multiplayer.get_remote_sender_id())

func _vote(peer: int) -> void:
	_skip_votes[peer] = true
	_rpc_partner_voted.rpc(peer)
	_check_votes()

func _check_votes() -> void:
	for id in GameState.character_by_peer:
		if not _skip_votes.has(id):
			return
	_rpc_skip.rpc(current)

@rpc("authority", "reliable", "call_local")
func _rpc_partner_voted(peer: int) -> void:
	if peer != multiplayer.get_unique_id() and active and not _skip_btn.disabled:
		_skip_hint.text = "Your partner wants to skip"
		_skip_hint.modulate.a = 1.0

@rpc("authority", "reliable", "call_local")
func _rpc_skip(id: String) -> void:
	if not active or current != id:
		return
	_skip = true
	_end()

# ------------------------------------------------------------------ lifecycle

func _start(id: String, steps: Array = []) -> void:
	active = true
	current = id
	_skip = false
	_skip_votes.clear()
	_token += 1
	_sub_until = 0.0
	_skip_btn.visible = true
	_skip_btn.disabled = false
	_skip_btn.text = "SKIP  ▸▸"
	_skip_hint.modulate.a = 0.0
	_sub_box.modulate.a = 0.0
	_title.modulate.a = 0.0
	_title_sub.modulate.a = 0.0
	for b in _bars:
		b.custom_minimum_size.y = 0
	# The world holds still.
	_frozen.clear()
	for group in ["zombies", "stalker"]:
		for n in get_tree().get_nodes_in_group(group):
			if n.is_physics_processing():
				_frozen.append(n)
				n.set_physics_process(false)
	hide_near_cameras(steps)
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			p.set("input_locked", true)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		_hud_visible = hud.visible
		hud.visible = false
	# Our own camera, starting where the player's is.
	_cam = Camera3D.new()
	_cam.name = "CutsceneCamera"
	_cam.fov = 55.0
	_cam.near = 0.05
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(_cam)
		var vc := get_viewport().get_camera_3d()
		if vc and vc != _cam:
			_cam.global_transform = vc.global_transform
		_cam_base = _cam.global_transform
		_cam.make_current()
	started.emit(id)

## Anything frozen near a camera would stand mid-stride in the shot: keep it
## out of the picture until the scene ends (it is still there afterwards).
func hide_near_cameras(steps: Array) -> void:
	_hidden.clear()
	var eyes: Array[Vector3] = []
	for st in steps:
		if st.get("do", "") == "cam":
			eyes.append(st["pos"])
			eyes.append(st["look"])
	for group in ["zombies", "stalker"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D and n.visible:
				for e in eyes:
					if n.global_position.distance_to(e) < HIDE_NEAR_CAM:
						n.visible = false
						_hidden.append(n)
						break

func _end() -> void:
	var id := current
	_teardown()
	if _story and is_instance_valid(_story) and _story.has_method("on_cutscene_end"):
		_story.call("on_cutscene_end", id)
	finished.emit(id)

func _teardown() -> void:
	active = false
	_token += 1
	_skip_btn.visible = false
	_video.stop()
	_video.stream = null
	_video.visible = false
	_video_bg.visible = false
	get_viewport().disable_3d = false
	_voice.stop()
	for a in _loops:
		if is_instance_valid(a):
			var t := create_tween()
			t.tween_property(a, "volume_db", -50.0, 1.2)
			t.tween_callback(a.queue_free)
	_loops.clear()
	Music.override_track = ""
	for n in _frozen:
		if is_instance_valid(n):
			n.set_physics_process(true)
	_frozen.clear()
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for p in get_tree().get_nodes_in_group("players"):
		p.set("cutscene_pose", false)
		if p.is_multiplayer_authority():
			p.set("input_locked", false)
			if p.get("camera"):
				p.camera.make_current()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.visible = _hud_visible
	if _cam_tween:
		_cam_tween.kill()
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	_shake = 0.0
	# Fade back in from wherever the scene left the screen.
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.6)
	t2.parallel().tween_property(_sub_box, "modulate:a", 0.0, 0.3)
	t2.parallel().tween_property(_title, "modulate:a", 0.0, 0.3)
	t2.parallel().tween_property(_title_sub, "modulate:a", 0.0, 0.3)
	for b in _bars:
		t2.parallel().tween_property(b, "custom_minimum_size:y", 0.0, 0.5)

# ------------------------------------------------------------------ runner

func _run(steps: Array, token: int) -> void:
	for s in steps:
		if _skip or token != _token:
			return
		if s.get("wait", true) and not s.has("delay"):
			await _do(s, token)
		elif s.get("wait", true):
			await _delayed(s, token)
		else:
			_delayed(s, token)

func _delayed(s: Dictionary, token: int) -> void:
	await _sleep(float(s.get("delay", 0.0)), token)
	if _skip or token != _token:
		return
	await _do(s, token)

func _sleep(t: float, token: int) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end and not _skip and token == _token:
		await get_tree().process_frame

func _do(s: Dictionary, token: int) -> void:
	match s.get("do", ""):
		"fade":
			var t := create_tween()
			t.tween_property(_fade, "color:a", float(s.get("to", 1.0)), float(s.get("t", 0.6)))
			await _sleep(float(s.get("t", 0.6)), token)
		"bars":
			var h := get_viewport().get_visible_rect().size.y * 0.11 if s.get("on", true) else 0.0
			var t := create_tween()
			for b in _bars:
				t.parallel().tween_property(b, "custom_minimum_size:y", h, float(s.get("t", 0.6)))
			await _sleep(float(s.get("t", 0.6)), token)
		"video":
			await _play_video(s, token)
		"say":
			await _say(s, token)
		"sub":
			_show_sub(s.get("who", ""), s.get("text", ""), float(s.get("t", 3.0)))
			await _sleep(float(s.get("t", 3.0)), token)
		"sfx":
			_sfx(s.get("file", ""), float(s.get("vol", 0.0)))
		"loop":
			var a := _sfx(s.get("file", ""), float(s.get("vol", 0.0)), true)
			if a:
				_loops.append(a)
		"music":
			Music.override_track = s.get("track", "")
		"wait":
			await _sleep(float(s.get("t", 1.0)), token)
		"title":
			await _show_title(s.get("text", ""), s.get("sub", ""), float(s.get("t", 4.0)), token)
		"chapter":
			await _show_title(s.get("name", ""), s.get("num", ""), float(s.get("t", 4.0)), token, true)
		"cam":
			await _move_cam(s, token)
		"shake":
			_shake = float(s.get("amount", 0.1))
			_shake_t = float(s.get("t", 0.5))
		"call":
			if _story and is_instance_valid(_story) and _story.has_method(s["fn"]):
				var r = _story.callv(s["fn"], s.get("args", []))
				if r is Signal:
					await r
		"objective":
			set_objective(s.get("text", ""))

func _play_video(s: Dictionary, token: int) -> void:
	var path: String = s.get("file", "")
	if not ResourceLoader.exists(path):
		push_warning("cutscene video missing: " + path)
		await _sleep(float(s.get("t", 3.0)), token)
		return
	_video.stream = load(path)
	_video_bg.visible = true
	_video.visible = true
	_layout_video()
	# The 3D world is fully covered: stop drawing it while the clip plays.
	get_viewport().disable_3d = true
	_video.play()
	if s.has("audio"):
		_play_voice_file(s["audio"])
	# Cues are steps tied to the clip's own clock (voice, sound, titles), so
	# they stay in sync even if the phone is slow to start decoding.
	var cues: Array = s.get("cues", []).duplicate()
	cues.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	var next := 0
	var t0 := Time.get_ticks_msec()
	var limit := t0 + int(float(s.get("t", 600.0)) * 1000.0)
	while true:
		var pos := _video.stream_position
		if pos <= 0.0:
			pos = (Time.get_ticks_msec() - t0) / 1000.0
		while next < cues.size() and float(cues[next]["at"]) <= pos:
			_do(cues[next], token)
			next += 1
		await get_tree().process_frame
		if not _video.is_playing() or Time.get_ticks_msec() >= limit or _skip or token != _token:
			break
	if token != _token:
		return
	if s.get("hold", false):
		return   # keep the last frame up until the next step replaces it
	_video.stop()
	_video.visible = false
	_video_bg.visible = false
	get_viewport().disable_3d = false

func _say(s: Dictionary, token: int) -> void:
	var path := VOICE % s.get("line", "")
	var dur := 2.5
	if ResourceLoader.exists(path):
		var st: AudioStream = load(path)
		dur = st.get_length()
		_voice.stream = st
		_voice.play()
	else:
		dur = max(2.0, String(s.get("text", "")).length() * 0.065)
	_show_sub(s.get("who", ""), s.get("text", ""), dur + 0.35)
	await _sleep(dur + float(s.get("gap", 0.25)), token)

func _play_voice_file(path: String) -> void:
	if ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.play()

func _sfx(path: String, vol: float, looped := false) -> AudioStreamPlayer:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var a := AudioStreamPlayer.new()
	var st: AudioStream = load(path)
	if looped:
		st = st.duplicate()
		if st is AudioStreamOggVorbis:
			st.loop = true
	a.stream = st
	a.volume_db = vol
	a.bus = "SFX"
	add_child(a)
	a.play()
	if not looped:
		a.finished.connect(a.queue_free)
	return a

func _move_cam(s: Dictionary, token: int) -> void:
	if not is_instance_valid(_cam):
		return
	if _video.visible:
		_video.stop()
		_video.visible = false
		_video_bg.visible = false
		get_viewport().disable_3d = false
	if _cam_tween:
		_cam_tween.kill()
	if s.has("from"):
		var f: Array = s["from"]
		_cam_base = _look(f[0], f[1])
		_cam.global_transform = _cam_base
	var to := _look(s["pos"], s["look"])
	var t := float(s.get("t", 0.0))
	if s.has("fov"):
		if t <= 0.0:
			_cam.fov = float(s["fov"])
	if t <= 0.0:
		_cam.global_transform = to
		_cam_base = to
		return
	var start := _cam_base
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_method(func(k: float): _cam_base = start.interpolate_with(to, k), 0.0, 1.0, t)
	if s.has("fov"):
		_cam_tween.parallel().tween_property(_cam, "fov", float(s["fov"]), t)
	if s.get("block", true):
		await _sleep(t, token)

func _look(pos: Vector3, at: Vector3) -> Transform3D:
	var tr := Transform3D(Basis(), pos)
	if pos.distance_to(at) > 0.001:
		tr = tr.looking_at(at, Vector3.UP)
	return tr

func _process(delta: float) -> void:
	if not active or not is_instance_valid(_cam):
		return
	var tr := _cam_base
	if _shake_t > 0.0:
		_shake_t -= delta
		var a := _shake * clampf(_shake_t * 2.0, 0.0, 1.0)
		tr.origin += Vector3(randf_range(-a, a), randf_range(-a, a), randf_range(-a, a))
	_cam.global_transform = tr
	if _sub_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _sub_until:
		_sub_until = 0.0
		create_tween().tween_property(_sub_box, "modulate:a", 0.0, 0.35)

# ------------------------------------------------------------------ text

func _show_sub(who: String, text: String, secs: float) -> void:
	var sp: Array = SPEAKERS.get(who, [who.to_upper(), Color(0.9, 0.9, 0.9)])
	_sub_name.text = sp[0]
	_sub_name.visible = sp[0] != ""
	_sub_name.add_theme_color_override("font_color", sp[1])
	_sub_text.text = text
	_sub_text.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84) if who != "narrator" else Color(0.86, 0.83, 0.76))
	_sub_box.modulate.a = 1.0
	_sub_until = Time.get_ticks_msec() / 1000.0 + secs

func _show_title(text: String, sub: String, secs: float, token: int, chapter := false) -> void:
	_title.text = text
	_title_sub.text = sub
	_title.add_theme_font_size_override("font_size", 120 if not chapter else 96)
	_title.add_theme_color_override("font_color", Color(0.78, 0.1, 0.07) if not chapter else Color(0.92, 0.88, 0.8))
	_title.scale = Vector2.ONE * 1.06
	_title.pivot_offset = _title.size * 0.5
	var t := create_tween()
	t.tween_property(_title_sub, "modulate:a", 1.0, 0.8)
	t.parallel().tween_property(_title, "modulate:a", 1.0, 1.2)
	t.parallel().tween_property(_title, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_SINE)
	await _sleep(max(secs - 1.0, 0.5), token)
	var t2 := create_tween()
	t2.tween_property(_title, "modulate:a", 0.0, 1.0)
	t2.parallel().tween_property(_title_sub, "modulate:a", 0.0, 1.0)
	await _sleep(1.0, token)

## Black at once: the level is up but a scene is about to start over it.
func cover(on := true) -> void:
	_fade.color.a = 1.0 if on else 0.0

## The current goal, shown as a banner now and kept in the world flags so it
## comes back with a save and shows again on load.
func set_objective(text: String) -> void:
	GameState.world_flags["objective"] = text
	objective_changed.emit(text)
	show_objective()

func show_objective() -> void:
	var text: String = GameState.world_flags.get("objective", "")
	if text == "":
		return
	_obj_label.text = text
	_obj_box.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.8 if active else 0.0)
	t.tween_property(_obj_box, "modulate:a", 1.0, 0.6)
	t.tween_interval(5.0)
	t.tween_property(_obj_box, "modulate:a", 0.0, 1.2)

# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_video_bg = ColorRect.new()
	_video_bg.color = Color.BLACK
	_video_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_bg.visible = false
	_root.add_child(_video_bg)
	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.bus = "SFX"
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	_root.add_child(_video)
	get_viewport().size_changed.connect(_layout_video)

	var bars := VBoxContainer.new()
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 0)
	_root.add_child(bars)
	for i in 3:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 1:
			r.color = Color(0, 0, 0, 0)
			r.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			r.color = Color.BLACK
			_bars.append(r)
		bars.add_child(r)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

	# Subtitles: speaker name in their colour over the line, bottom centre.
	_sub_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_sub_box.add_theme_stylebox_override("panel", sb)
	_sub_box.anchor_left = 0.12
	_sub_box.anchor_right = 0.88
	_sub_box.anchor_top = 1.0
	_sub_box.anchor_bottom = 1.0
	_sub_box.offset_top = -330
	_sub_box.offset_bottom = -150
	_sub_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_box.modulate.a = 0.0
	_root.add_child(_sub_box)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	_sub_box.add_child(v)
	_sub_name = _text(v, 30, HORIZONTAL_ALIGNMENT_CENTER)
	_sub_text = _text(v, 44, HORIZONTAL_ALIGNMENT_CENTER)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_title_sub = _text(center, 34, HORIZONTAL_ALIGNMENT_CENTER)
	_title_sub.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62))
	_title_sub.modulate.a = 0.0
	_title = _text(center, 120, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_constant_override("outline_size", 18)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_y", 8)
	_title.modulate.a = 0.0

	_skip_btn = Button.new()
	_skip_btn.text = "SKIP  ▸▸"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.anchor_left = 1.0
	_skip_btn.anchor_right = 1.0
	_skip_btn.offset_left = -330
	_skip_btn.offset_right = -40
	_skip_btn.offset_top = 40
	_skip_btn.offset_bottom = 130
	_skip_btn.add_theme_font_size_override("font_size", 30)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.45)
	bs.border_color = Color(0.85, 0.8, 0.7, 0.45)
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(14)
	for st in ["normal", "hover", "pressed", "disabled"]:
		_skip_btn.add_theme_stylebox_override(st, bs)
	_skip_btn.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78, 0.85))
	_skip_btn.pressed.connect(_on_skip_pressed)
	_root.add_child(_skip_btn)
	_skip_hint = _text(_root, 26, HORIZONTAL_ALIGNMENT_RIGHT)
	_skip_hint.anchor_left = 1.0
	_skip_hint.anchor_right = 1.0
	_skip_hint.offset_left = -640
	_skip_hint.offset_right = -40
	_skip_hint.offset_top = 140
	_skip_hint.modulate.a = 0.0

	# Objective banner, top centre.
	_obj_box = PanelContainer.new()
	var ob := StyleBoxFlat.new()
	ob.bg_color = Color(0.05, 0.03, 0.03, 0.7)
	ob.border_color = Color(0.6, 0.14, 0.1, 0.9)
	ob.border_width_left = 6
	ob.content_margin_left = 26
	ob.content_margin_right = 30
	ob.content_margin_top = 12
	ob.content_margin_bottom = 12
	_obj_box.add_theme_stylebox_override("panel", ob)
	_obj_box.anchor_left = 0.5
	_obj_box.anchor_right = 0.5
	_obj_box.offset_top = 180
	_obj_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_box.modulate.a = 0.0
	_root.add_child(_obj_box)
	var ov := VBoxContainer.new()
	_obj_box.add_child(ov)
	var head := _text(ov, 24, HORIZONTAL_ALIGNMENT_LEFT)
	head.text = "OBJECTIVE"
	head.add_theme_color_override("font_color", Color(0.85, 0.3, 0.22))
	_obj_label = _text(ov, 36, HORIZONTAL_ALIGNMENT_LEFT)
	_skip_btn.visible = false

func _text(parent: Control, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

## Fit the 16:9 clip inside the screen (the Fold's inner screen is nearly
## square, so this letterboxes top and bottom).
func _layout_video() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := vs.x
	var h := w * 9.0 / 16.0
	if h > vs.y:
		h = vs.y
		w = h * 16.0 / 9.0
	_video.position = Vector2((vs.x - w) / 2.0, (vs.y - h) / 2.0)
	_video.size = Vector2(w, h)
