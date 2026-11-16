extends SceneTree
## How smoothly the other phone's survivor and the infected move on each
## phone, over a link with lag, jitter and stalls (relay/local_relay.js with
## LAG_MS / JITTER_MS / STALL_EVERY_MS / STALL_MS).
##
## Zegan hosts and Obcera joins. On the host, Zegan and one infected walk
## circles at a steady 3 m/s, their place on the circle set by the wall
## clock, which both copies of the game share on one PC. So any phone can
## tell from where it shows one of them how long ago the host had them there.
## Obcera does the same on her phone, so the host sees a moving partner too.
##
## Each phone measures, every frame, for what the other phone moves:
##   delay   how far behind the sender it is shown (ms): median, and the
##           spread from the 5th to the 95th percentile (steady = smooth)
##   stalls  frames where it barely moved though it was walking (%)
##   jumps   frames where it moved more than twice its walking pace (%)
## and the readout's numbers (ping, frame rate).
##
## host: RAGOON_RELAY=ws://127.0.0.1:8787 godot --headless --path . --script tests/coop_smooth.gd -- host
## join: same with -- join.   tools/playtest.sh runs it through a relay with
## lag, jitter and stalls. Prints "COOP ok/FAIL ..." and "COOP SMOOTH DONE n fails".
## SMOOTH_SECS (default 20) sets how long it measures; SMOOTH_REPORT_ONLY=1
## prints the numbers without judging them.

const CODE := "QASM88"
const SPEED := 3.0     # m/s around the circle
const RADIUS := 2.5
const W := SPEED / RADIUS
const PERIOD := TAU / W
## Circles in the open on Ashgrove Street (y is set from the floor there).
const CENTERS := {"zegan": Vector3(-13.0, 0.0, -21.5), "infected": Vector3(-13.0, 0.0, -14.5), "obcera": Vector3(-6.0, 0.0, -18.0)}

var role := ""
var fails: Array = []
var GS: Node
var NET: Node
var CHEATS: Node
var _floor_y := {}
var _driving: Array = []   # [key, node]
var _watch: Array = []     # [key, node, samples: Array of [t, pos]]
var _measuring := false

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	GS = root.get_node("GameState")
	NET = root.get_node("Net")
	CHEATS = root.get_node("Cheats")
	Engine.max_fps = 60
	create_timer(200.0).timeout.connect(func():
		print(role, " COOP FAIL timed out")
		quit(1))
	physics_frame.connect(_drive)
	process_frame.connect(_sample)
	_main.call_deferred()

func _check(cond: bool, what: String) -> void:
	print("%s COOP %s %s" % [role, "ok  " if cond else "FAIL", what])
	if not cond:
		fails.append(what)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _until(cond: Callable, max_t: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_t * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return false

func _sync(step: String) -> void:
	GS.share_flag("qa_sync:%s:%s" % [step, role])
	var other := "join" if role == "host" else "host"
	if not await _until(func(): return GS.has_flag("qa_sync:%s:%s" % [step, other]), 30.0):
		_check(false, "%s: the other phone reached '%s'" % [role, step])

func _player(who: String) -> Node:
	for p in get_nodes_in_group("players"):
		if p.character == who:
			return p
	return null

static func _now() -> float:
	return Time.get_unix_time_from_system()

## Where `key` is on its circle at wall-clock time t.
static func _on_circle(key: String, t: float, y: float) -> Vector3:
	var a := W * t + (1.3 if key == "infected" else 0.0)
	return CENTERS[key] + Vector3(cos(a) * RADIUS, y, sin(a) * RADIUS)

## When (wall clock, at or before `now`) the sender had `key` at `pos`.
static func _sent_at(key: String, pos: Vector3, now: float) -> float:
	var d: Vector3 = pos - CENTERS[key]
	var a := atan2(d.z, d.x) - (1.3 if key == "infected" else 0.0)
	var base := a / W
	var k := floorf((now - base) / PERIOD)
	return base + k * PERIOD

## The sender's side: put what it drives on its circle, every physics frame.
func _drive() -> void:
	var now := _now()
	for d in _driving:
		var n: Node3D = d[1]
		if is_instance_valid(n):
			n.global_position = _on_circle(d[0], now, _floor_y[d[0]])
			var a := W * now + (1.3 if d[0] == "infected" else 0.0)
			var yaw := atan2(-(-sin(a)), -cos(a))   # facing along the circle
			if n.is_in_group("zombies"):
				n.rotation.y = yaw
			else:
				n.body.rotation.y = yaw

func _sample() -> void:
	if not _measuring:
		return
	var now := _now()
	for w in _watch:
		var n: Node3D = w[1]
		if is_instance_valid(n):
			w[2].append([now, n.global_position])

func _main() -> void:
	GS.reset_run()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.0)
	if role == "host":
		NET.partner_joined.connect(func(_id):
			await _wait(1.0)
			current_scene._start_coop.rpc(GS.level_path, "start", {"story_intro": true}, {}, "normal"))
		NET.host_online("zegan", CODE)
	else:
		await _wait(2.5)
		NET.join_online(CODE, "obcera")
	if not await _until(func(): return get_first_node_in_group("level") != null and get_nodes_in_group("players").size() == 2, 40.0):
		_check(false, "both survivors in the level")
		_finish()
		return
	await _wait(2.0)
	if role == "host":
		CHEATS.set_cheat("god_mode", true)
	var level: Node = get_first_node_in_group("level")
	var me: Node = _player("zegan" if role == "host" else "obcera")
	var them: Node = _player("obcera" if role == "host" else "zegan")
	var mine: String = me.character
	me.input_locked = true
	_floor_y = {"zegan": me.global_position.y, "obcera": me.global_position.y, "infected": me.global_position.y}
	_floor_y[mine] = _floor(CENTERS[mine], me.global_position.y)
	await _sync("in_level")
	if role == "host":
		level.spawn_zombie_synced.rpc("QA_Circler", CENTERS["infected"] + Vector3(RADIUS, 0.2, 0), "shambler")
	if not await _until(func(): return level.has_node("QA_Circler"), 10.0):
		_check(false, "the circling infected reached the %s's phone" % role)
		_finish()
		return
	var z: Node3D = level.get_node("QA_Circler")
	if role == "host":
		z.set_physics_process(false)   # the test walks it, not its brain
		_floor_y["infected"] = _floor(CENTERS["infected"], me.global_position.y)
		_driving.append(["infected", z])
	_driving.append([mine, me])
	# Her body: where she's drawn (her capsule may stand a moment ahead).
	_watch.append([them.character, them.body, []])
	if role == "join":
		_watch.append(["infected", z, []])
	await _wait(3.0)   # settle: snapshots flowing, playback delay found
	_measuring = true
	var secs := float(OS.get_environment("SMOOTH_SECS")) if OS.get_environment("SMOOTH_SECS") != "" else 20.0
	var NS: GDScript = load("res://scripts/net/net_smooth.gd")
	var other_peer: int = them.peer_id
	for i in int(secs):
		await _wait(1.0)
		if OS.get_environment("SMOOTH_TRACE") != "":
			var l = NS.link(other_peer)
			print("%s TRACE t=%d delay=%.0f target=%.0f offset=%.1f gap=%.0f seen=%d late=%d lateness p50=%.0f p90=%.0f p97=%.0f gapseen=%.0f" % [role, i, l.delay, l.target, l.offset, l.gap_ms, l.seen, l.too_late, l.late_at(0.5), l.late_at(0.9), l.late_at(0.97), 0.0])
	_measuring = false
	var judge := OS.get_environment("SMOOTH_REPORT_ONLY") == ""
	for w in _watch:
		_report(w[0], w[2], judge)
	_readout(judge)
	await _sync("done")
	_finish()

func _floor(at: Vector3, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position.y + 0.02 if not hit.is_empty() else fallback

func _report(key: String, samples: Array, judge: bool) -> void:
	if samples.size() < 60:
		_check(false, "%s: enough frames measured (%d)" % [key, samples.size()])
		return
	var delays: Array = []
	var stalls := 0
	var jumps := 0
	var moving := 0
	for i in samples.size():
		var t: float = samples[i][0]
		var p: Vector3 = samples[i][1]
		delays.append((t - _sent_at(key, p, t)) * 1000.0)
		if i == 0:
			continue
		var dt: float = t - samples[i - 1][0]
		if dt <= 0.004:
			continue
		var moved: float = Vector2(p.x - samples[i - 1][1].x, p.z - samples[i - 1][1].z).length()
		var pace := SPEED * dt
		moving += 1
		if moved < pace * 0.3:
			stalls += 1
		elif moved > pace * 2.0:
			jumps += 1
	delays.sort()
	var q := func(f: float) -> float: return delays[int(f * (delays.size() - 1))]
	var spread: float = q.call(0.95) - q.call(0.05)
	var stall_pc := 100.0 * stalls / maxf(moving, 1)
	var jump_pc := 100.0 * jumps / maxf(moving, 1)
	var who := "the infected" if key == "infected" else key.capitalize()
	print("%s SMOOTH %s frames=%d delay p50=%.0f ms spread(p5-p95)=%.0f ms max=%.0f ms stalls=%.1f%% jumps=%.1f%%" % [role, key, samples.size(), q.call(0.5), spread, q.call(1.0), stall_pc, jump_pc])
	if not judge:
		return
	_check(stall_pc < 4.0, "%s keeps moving on the %s's phone (%.1f%% of frames stood still mid-walk)" % [who, role, stall_pc])
	_check(jump_pc < 2.0, "%s doesn't jump on the %s's phone (%.1f%% of frames jumped)" % [who, role, jump_pc])
	_check(spread < 60.0, "%s is shown a steady time behind on the %s's phone (spread %.0f ms)" % [who, role, spread])
	_check(q.call(0.5) < 400.0, "%s isn't shown far behind on the %s's phone (%.0f ms)" % [who, role, q.call(0.5)])

## The readout (ping and frame rate), if this build has one.
func _readout(judge: bool) -> void:
	if not NET.has_method("ping_ms"):
		print("%s SMOOTH readout: none in this build" % role)
		return
	var ping: float = NET.ping_ms()
	print("%s SMOOTH readout ping=%.0f ms text='%s'" % [role, ping, NET.stats_text()])
	if judge:
		_check(ping > 0.0, "the %s's phone measures a ping (%.0f ms)" % [role, ping])

var _quitting := false

func _finish() -> void:
	if _quitting:
		return
	_quitting = true
	print("%s COOP SMOOTH DONE %d fails" % [role, fails.size()])
	for f in fails:
		print("  - ", f)
	await _wait(3.0)
	quit(0 if fails.is_empty() else 1)
