extends SceneTree
## Joining a co-op game through the relay: every way it can go wrong must say
## what really happened, on the join screen, and nothing may overwrite it a
## few seconds later. (0.15 showed "Relay timed out" for a mistyped code.)
## host: RAGOON_RELAY=ws://127.0.0.1:8797 godot --headless --path . --script tests/coop_join_errors.gd -- host
## join: same with -- join
## JOIN_TEST_CODE=<6 digits> picks the room (default 731406); use a random one
## against the live relay. Both sides drive the real title screen.
##
## Joiner: parse checks; a 5-digit code and an empty box (told at once, relay
## never asked); no relay at the address; a relay that never answers; the
## host's code with one digit wrong (told within seconds, still the same
## message 14 s later); a wrong code then the right one straight after (gets
## in, no late error); then the host leaving.
## Host: the room shows "Opening the room..." until the relay has it; a third
## phone is told the room is full; a second host with the same code is told
## it's taken; leaving tells the joiner; a taken code is swapped for a new one
## on screen.

const WAITING := "Send this code or the invite link to your friend.\nWaiting for them to join..."

var role := ""
var failures := 0
var menu
var net
var problems: Array[String] = []

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func _code() -> String:
	var c := OS.get_environment("JOIN_TEST_CODE")
	return c if c != "" else "731406"

func _check(ok: bool, what: String) -> void:
	if ok:
		print(role, " ok: ", what)
	else:
		failures += 1
		print(role, " FAIL: ", what)

func _wait(secs: float) -> void:
	await create_timer(secs).timeout

## Seconds until cond() holds, or -1.0 if it doesn't within secs.
func _until(cond: Callable, secs: float) -> float:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if cond.call():
			return (Time.get_ticks_msec() - t0) / 1000.0
		await process_frame
	return -1.0

func _status() -> String:
	return menu._status.text if is_instance_valid(menu._status) else ""

func _shown_as_problem() -> bool:
	return is_instance_valid(menu._status) and menu._status.has_theme_color_override("font_color")

func _run() -> void:
	await _wait(0.2)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.5)
	menu = current_scene
	net = root.get_node("Net")
	net.session_failed.connect(func(r): problems.append(r); print(role, " session_failed: ", r))
	print(role, " relay ", net.relay_url, " room ", _code())
	if role == "host":
		await _host()
	else:
		await _join()
	print(role, " done, ", failures, " failing")
	quit(1 if failures else 0)

# ---------------------------------------------------------------- joiner

func _type_and_join(text: String) -> void:
	menu._code_edit.text = text
	menu._try_join()

func _join() -> void:
	var code := _code()
	var shown: String = net.pretty_code(code)
	for pair in [
		["482 917", "482917"], ["482-917", "482917"], ["  48O 9l7 ", "480917"],
		["rdrfvx", "RDRFVX"], ["ragooncity://join/482917", "482917"],
		["Join my RaGoon City game: https://ragoon-city-download.hakipowered.workers.dev/play/?join=482917  (or enter code 482 917)", "482917"],
		["code is 482 917, see you", "482917"], ["4829170", "4829170"], ["", ""]]:
		var got: String = net.parse_code(pair[0])
		_check(got == pair[1], "parse_code(%s) = %s (want %s)" % [JSON.stringify(pair[0]), got, pair[1]])
	var fresh: String = net.new_room_code()
	_check(fresh.length() == 6 and fresh.is_valid_int(), "new room codes are 6 numbers (%s)" % fresh)
	_check(net.pretty_code("482917") == "482 917", "codes are shown as 482 917")

	menu._join_menu("")
	await _wait(0.5)
	_check(menu._code_edit.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_NUMBER, "the code box brings up the number pad")
	menu._code_edit.text = "rdrfvx"
	menu._code_edit.text_changed.emit("rdrfvx")
	_check(menu._code_edit.text == "RDRFVX", "typed letters come out in capitals (%s)" % menu._code_edit.text)

	# A code that can't be right: said straight away, and no relay is asked.
	_type_and_join("48291")
	var t := await _until(func(): return _status().begins_with("Room codes have 6 numbers"), 1.0)
	_check(t >= 0.0 and _shown_as_problem(), "5 digits: told at once (%s)" % _status())
	_check(not net.multiplayer.multiplayer_peer is RelayPeer, "5 digits: the relay isn't asked")
	_type_and_join("")
	t = await _until(func(): return _status().begins_with("Type the room code"), 1.0)
	_check(t >= 0.0, "empty box: told to type the code (%s)" % _status())

	# Nothing listening where the relay should be.
	var real_relay: String = net.relay_url
	net.relay_url = "ws://127.0.0.1:9"
	_type_and_join(shown)
	t = await _until(func(): return _status().begins_with("Can't reach the co-op server"), 6.0)
	_check(t >= 0.0, "no relay: \"can't reach\" after %.1f s (%s)" % [t, _status()])

	# A relay that takes the connection and never answers: a real timeout.
	var srv := TCPServer.new()
	_check(srv.listen(18799, "127.0.0.1") == OK, "silent server listening")
	net.relay_url = "ws://127.0.0.1:18799"
	_type_and_join(shown)
	t = await _until(func(): return _status().begins_with("The co-op server didn't answer"), 16.0)
	_check(t >= 10.0, "silent relay: \"didn't answer in time\" after %.1f s (%s)" % [t, _status()])
	srv.stop()
	net.relay_url = real_relay

	# The host's code with one digit wrong (their D-for-T moment).
	var wrong := code.substr(0, 1) + str((int(code[1]) + 5) % 10) + code.substr(2)
	problems.clear()
	_type_and_join(net.pretty_code(wrong))
	_check(_status() == "Joining room %s..." % net.pretty_code(wrong), "wrong code: says which room it's trying (%s)" % _status())
	t = await _until(func(): return _status().begins_with("No game is open with code %s" % net.pretty_code(wrong)), 8.0)
	_check(t >= 0.0 and t < 5.0 and _shown_as_problem(), "wrong code: \"no game is open\" after %.1f s (%s)" % [t, _status()])
	var said := _status()
	await _wait(net.RELAY_TIMEOUT + 2.0)
	_check(_status() == said and problems.size() == 1, "wrong code: nothing overwrites it %d s later (now %s, messages %s)" % [int(net.RELAY_TIMEOUT + 2.0), _status(), problems])

	# Wrong code, then the right one at once: no stale message from the first.
	problems.clear()
	_type_and_join(net.pretty_code(wrong))
	await process_frame
	_type_and_join(shown)
	t = await _until(func(): return _status() == "Connected. Waiting for host to start...", 15.0)
	_check(t >= 0.0, "right code: connected after %.1f s (%s)" % [t, _status()])
	await _wait(net.RELAY_TIMEOUT + 2.0)
	_check(_status() == "Connected. Waiting for host to start..." and problems.is_empty(), "right code: still connected, no late error (%s, messages %s)" % [_status(), problems])

	# The host closes their game.
	t = await _until(func(): return _status() == "Your friend closed their game.", 60.0)
	_check(t >= 0.0, "host left: told so (%s)" % _status())

# ---------------------------------------------------------------- host

## Polls a bare RelayPeer until the relay ends it; its close_kind.
func _relay_end(peer: RelayPeer, secs: float) -> String:
	var t0 := Time.get_ticks_msec()
	while peer.close_kind == "" and Time.get_ticks_msec() - t0 < secs * 1000.0:
		peer.poll()
		await process_frame
	return peer.close_kind

func _host() -> void:
	var code := _code()
	var joined := [false]
	net.partner_joined.connect(func(_id): joined[0] = true)
	net.host_online("zegan", code)
	menu._lobby_host(code)
	_check(menu._room_title.text == "ROOM %s" % net.pretty_code(code), "room title %s" % menu._room_title.text)
	_check(_status() == "Opening the room...", "lobby says it's opening the room first (%s)" % _status())
	var t := await _until(func(): return _status() == WAITING, 10.0)
	_check(t >= 0.0, "room open after %.1f s" % t)

	t = await _until(func(): return joined[0], 120.0)
	_check(t >= 0.0, "partner joined")

	# A third phone, and a second host on the same code.
	var third := RelayPeer.new()
	third.open("%s/room/%s?role=join" % [net.relay_url, code])
	var kind := await _relay_end(third, 10.0)
	_check(kind == "room_full", "third phone: room_full (%s)" % kind)
	_check(net.explain_join_problem(kind, code).begins_with("Room %s already has two players" % net.pretty_code(code)), "room_full reads " + net.explain_join_problem(kind, code))
	var dup := RelayPeer.new()
	dup.open("%s/room/%s?role=host" % [net.relay_url, code])
	kind = await _relay_end(dup, 10.0)
	_check(kind == "code_taken", "second host on the same code: code_taken (%s)" % kind)
	_check(joined[0] and net.multiplayer.get_peers().size() == 1, "partner still in after both were turned away")

	# The joiner watches for late errors; then leave.
	await _wait(net.RELAY_TIMEOUT + 6.0)
	net.close()
	menu._home()
	await _wait(1.0)

	# A taken code: the room opens with a new one, and the screen shows it.
	var k2 := "%06d" % ((int(code) + 111111) % 1000000)
	var squat := RelayPeer.new()
	squat.open("%s/room/%s?role=host" % [net.relay_url, k2])
	var t0 := Time.get_ticks_msec()
	while squat.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() - t0 < 10000:
		squat.poll()
		await process_frame
	_check(squat.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "someone else holds room %s" % k2)
	var changed := [""]
	net.room_code_changed.connect(func(c): changed[0] = c)
	problems.clear()
	net._host_fixed_code = false
	net._host_retries = 0
	net.room_code = k2
	net._open_relay("host", "zegan")
	menu._lobby_host(k2)
	t = await _until(func(): return _status() == WAITING, 10.0)
	_check(t >= 0.0 and changed[0] != "" and changed[0] != k2 and net.room_code == changed[0], "taken code %s swapped for %s" % [k2, changed[0]])
	_check(menu._room_title.text == "ROOM %s" % net.pretty_code(changed[0]), "lobby shows the new code (%s)" % menu._room_title.text)
	_check(problems.is_empty(), "no problem shown for a swapped code (%s)" % [problems])
	squat.close()
	net.close()
