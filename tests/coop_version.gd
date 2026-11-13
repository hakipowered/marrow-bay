extends SceneTree
## Co-op version check through the relay (scripts/net/version_check.gd).
## host: RAGOON_RELAY=ws://127.0.0.1:8797 godot --headless --script tests/coop_version.gd -- host
## join: same with -- join
## Round 1: same game content, the joiner gets in. Round 2: the joiner runs
## an older version; it must be turned away with a message saying who needs
## to update, and the host must never see it join.
var role := ""
var t0 := 0
var stage := 0
var frames := 0
var events: Array[String] = []

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	t0 = Time.get_ticks_msec()

func _secs() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0

func _fail(why: String) -> void:
	print(role, " FAIL: ", why, " events ", events)
	quit(1)

func _process(_d: float) -> bool:
	frames += 1
	var net = root.get_node("Net")
	var pm = root.get_node("PackMount")
	var gs = root.get_node("GameState")
	if _secs() > 60.0:
		_fail("TIMEOUT stage %d" % stage)
		return false
	match stage:
		0:
			if frames < 5:
				return false
			net.partner_joined.connect(func(_id): events.append("joined"))
			net.partner_left.connect(func(_id): events.append("left"))
			net.session_failed.connect(func(r): events.append("failed: " + r))
			pm.build_id = "0.10-aaaa"
			pm.version_name = "0.10"
			if role == "host":
				net.host_online("zegan", "VERSNA")
			stage = 1
			frames = 0
		1:
			# Round 1: same build.
			if role == "join" and frames == 60:
				net.join_online("VERSNA", "obcera")
			if role == "host" and events.has("joined") and gs.character_by_peer.size() == 2:
				print("host: round 1 partner verified and registered")
				stage = 2
			if role == "join" and gs.character_by_peer.size() == 2:
				print("join: round 1 let in")
				net.close()
				stage = 2
				frames = 0
		2:
			# Round 2: the joiner is a version behind.
			if role == "host" and events.has("left"):
				events.clear()
				pm.build_id = "0.11-bbbb"
				pm.version_name = "0.11"
				net.host_online("zegan", "VERSNB")
				stage = 3
				frames = 0
			if role == "join" and frames == 120:
				events.clear()
				gs.character_by_peer = {}
				net.join_online("VERSNB", "obcera")
				stage = 3
				frames = 0
		3:
			if role == "join":
				for e in events:
					if e.begins_with("failed: Your friend has version 0.11 and you have 0.10. Close and reopen"):
						print("join: round 2 turned away: ", e)
						stage = 4
						frames = 0
			else:
				for e in events:
					if e == "joined":
						_fail("an older version got in")
					if e.begins_with("failed: Your friend has version 0.10 and you have 0.11. They need to close and reopen"):
						print("host: round 2 told: ", e)
						stage = 4
						frames = 0
		4:
			# Give the other side time to finish, and make sure nobody got in.
			if frames == 90:
				# (A joiner sees the host connect as partner_joined; only the
				# host's matters here.)
				if role == "host" and events.has("joined"):
					_fail("partner_joined after a version mismatch")
					return false
				if role == "host" and gs.character_by_peer.size() != 1:
					_fail("the older joiner was registered: %s" % gs.character_by_peer)
					return false
				print(role, " PASS")
				quit(0)
	return false
