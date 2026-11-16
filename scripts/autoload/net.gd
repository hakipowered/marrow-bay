extends Node
## Session setup: solo, online via relay (room code / invite link), or LAN.

signal session_ready
signal partner_joined(peer_id: int)
signal partner_left(peer_id: int)
signal session_failed(reason: String)
## The host's room got a different code (the first one was taken).
signal room_code_changed(code: String)

## Set this to your deployed relay (see relay/README.md).
const RELAY_URL := "wss://ragoon-city-relay.hakipowered.workers.dev"
const LAN_PORT := 24680
const INVITE_SCHEME := "ragooncity://join/"
## Room codes are six numbers. Letters were misheard and misread between
## friends (a D read out as T sent a joiner to a room that didn't exist);
## digits survive a voice call, any font, and the phone's number pad.
const CODE_ALPHABET := "0123456789"
const CODE_LENGTH := 6
## How long a joiner waits for the relay to answer before saying so.
const RELAY_TIMEOUT := 12.0

## How long the host waits for a joiner's version hello before telling the
## player that their friend's game is too old to check.
const HELLO_TIMEOUT := 6.0
const VersionCheck := preload("res://scripts/net/version_check.gd")

var room_code := ""
var relay_url := RELAY_URL
## Each host/join attempt gets a number; replies to an older attempt (the
## player pressed Join again, or went Back) are ignored.
var _attempt := 0
var _host_fixed_code := false
var _host_retries := 0
## Joiners whose game content matches the host's (see version_check.gd).
var _verified := {}
var _version_check: Node

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): session_ready.emit())
	# Through the relay, RelayPeer.relay_closed says what really happened
	# (_on_relay_closed); these two only speak for Same Wi-Fi games.
	multiplayer.connection_failed.connect(func():
		if not multiplayer.multiplayer_peer is RelayPeer:
			session_failed.emit("Couldn't reach the host phone. Check that you're both on the same Wi-Fi and the IP is right."))
	multiplayer.server_disconnected.connect(func():
		if not multiplayer.multiplayer_peer is RelayPeer:
			session_failed.emit("Host left the game"))
	_version_check = VersionCheck.new()
	_version_check.name = "VersionCheck"
	add_child(_version_check)
	_version_check.peer_verified.connect(_on_peer_verified)
	_version_check.peer_rejected.connect(func(_id, theirs): session_failed.emit(VersionCheck.explain(PackMount.version_name, theirs)))
	_version_check.rejected_by_host.connect(func(theirs):
		close.call_deferred()
		session_failed.emit(VersionCheck.explain(PackMount.version_name, theirs)))
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		relay_url = cfg.get_value("net", "relay_url", RELAY_URL)
	if OS.get_environment("RAGOON_RELAY") != "":
		relay_url = OS.get_environment("RAGOON_RELAY")
	# Browser version: /play/?relay=ws://... points a test build at a local relay.
	if WebPlatform.url_param("relay") != "":
		relay_url = WebPlatform.url_param("relay")

func start_solo(character: String) -> void:
	close()
	GameState.mode = GameState.Mode.SOLO
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.character_by_peer = {1: character}
	session_ready.emit()

func new_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in CODE_LENGTH:
		s += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return s

## "482917" -> "482 917", easier to read out and to compare by eye. Older
## letter codes (and test codes) stay as they are.
static func pretty_code(code: String) -> String:
	if code.length() == CODE_LENGTH and _all_digits(code):
		return code.substr(0, 3) + " " + code.substr(3)
	return code

static func is_valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for ch in code:
		if not (ch >= "A" and ch <= "Z") and not (ch >= "0" and ch <= "9"):
			return false
	return true

static func _all_digits(t: String) -> bool:
	for ch in t:
		if ch < "0" or ch > "9":
			return false
	return t != ""

## A web link: it opens the browser version straight into the join screen,
## so a friend without the app can play too (the message also has the code).
func invite_link() -> String:
	return WebPlatform.invite_url(room_code)

## Accepts "482917", "482 917", "482-917", "ragooncity://join/482917",
## ".../play/?join=482917", a pasted invite message containing one of them,
## and older letter codes ("rdrfvx"). Returns the code in capitals, or what
## was typed (letters and digits only) when it isn't six long, so the join
## screen can say what's wrong instead of guessing.
static func parse_code(text: String) -> String:
	var t := text.strip_edges().to_upper()
	for marker in ["JOIN=", "JOIN/"]:
		var idx := t.find(marker)
		if idx >= 0:
			return _squash(t.substr(idx + marker.length()).get_slice("&", 0).get_slice(" ", 0))
	var whole := _squash(t)
	if whole.length() <= CODE_LENGTH:
		return whole
	# A longer message: the first "482 917" / "482917" in it.
	var re := RegEx.create_from_string("(?<![0-9])([0-9]{3})[ -]?([0-9]{3})(?![0-9])")
	var m := re.search(t)
	if m:
		return m.get_string(1) + m.get_string(2)
	return whole

## Letters and digits only. In an all-number code, O and I/L typed by
## mistake mean 0 and 1.
static func _squash(t: String) -> String:
	var out := ""
	for ch in t:
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	var as_digits := out.replace("O", "0").replace("I", "1").replace("L", "1")
	return as_digits if _all_digits(as_digits) else out

func host_online(character: String, fixed_code := "") -> String:
	close()
	_host_fixed_code = fixed_code != ""
	_host_retries = 0
	room_code = fixed_code if fixed_code != "" else new_room_code()
	_open_relay("host", character)
	return room_code

func join_online(code: String, character: String) -> void:
	close()
	room_code = parse_code(code)
	if not is_valid_code(room_code):
		GameState.mode = GameState.Mode.COOP
		session_failed.emit.call_deferred(explain_join_problem("bad_code", room_code))
		return
	_open_relay("join", character)

func _open_relay(role: String, character: String) -> void:
	GameState.mode = GameState.Mode.COOP
	_attempt += 1
	var attempt := _attempt
	var peer := RelayPeer.new()
	# Deferred: it fires inside the peer's own poll, where swapping the
	# multiplayer peer (a retry with a new code) isn't safe.
	peer.relay_closed.connect(_on_relay_closed.bind(role, character, attempt), CONNECT_DEFERRED)
	var url := "%s/room/%s?role=%s" % [relay_url, room_code, role]
	if peer.open(url) != OK:
		session_failed.emit.call_deferred(explain_join_problem("unreachable", room_code, role))
		return
	multiplayer.multiplayer_peer = peer
	_wait_for_id(peer, character, attempt)

## Everything the relay connection can end with, said plainly. role is
## "host" or "join"; code is the room code tried.
static func explain_join_problem(kind: String, code: String, role := "join") -> String:
	var shown := pretty_code(code)
	match kind:
		"bad_code":
			if code == "":
				return "Type the room code from your friend's screen first."
			return "Room codes have 6 numbers, and \"%s\" has %d. Check the code on your friend's screen." % [shown, code.length()]
		"no_room":
			return "No game is open with code %s. Check it against your friend's screen. If it matches, their room has closed: ask them to invite you again." % shown
		"room_full":
			return "Room %s already has two players." % shown
		"code_taken":
			return "Room code %s is already in use. Tap Cancel and invite again for a new code." % shown
		"host_left":
			return "Your friend closed their game."
		"timeout":
			return "The co-op server didn't answer in time. Check your internet connection and try again."
		"lost":
			if role == "host":
				return "Lost the connection to the co-op server, so your friend can't join room %s. Check your internet connection, then tap Cancel and invite again." % shown
			return "Lost the connection to the co-op server. Check your internet connection and join again."
	return "Can't reach the co-op server. Check your internet connection and try again."

func _on_relay_closed(kind: String, role: String, character: String, attempt: int) -> void:
	if attempt != _attempt:
		return
	# Another host already has this code: open the room with a new one.
	if kind == "code_taken" and role == "host" and not _host_fixed_code and _host_retries < 5:
		_host_retries += 1
		room_code = new_room_code()
		_open_relay("host", character)
		room_code_changed.emit(room_code)
		return
	session_failed.emit(explain_join_problem(kind, room_code, role))

func _wait_for_id(peer: RelayPeer, character: String, attempt: int) -> void:
	var t := 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and t < RELAY_TIMEOUT:
		await get_tree().process_frame
		t += get_process_delta_time()
	if attempt != _attempt:
		return   # closed, or a newer attempt has started
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if peer.close_kind == "":
			# Still knocking: the relay never answered.
			close()
			session_failed.emit(explain_join_problem("timeout", room_code))
		return   # otherwise _on_relay_closed has said why
	GameState.character_by_peer[multiplayer.get_unique_id()] = character
	if multiplayer.is_server():
		session_ready.emit()
	else:
		session_ready.emit()
		_version_check.send_hello()
		_rpc_register.rpc_id(1, character, _my_looks(character))

func host_lan(character: String) -> void:
	close()
	GameState.mode = GameState.Mode.COOP
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(LAN_PORT, 1) != OK:
		session_failed.emit("Port busy")
		return
	multiplayer.multiplayer_peer = peer
	GameState.character_by_peer[1] = character
	session_ready.emit()

func join_lan(ip: String, character: String) -> void:
	close()
	GameState.mode = GameState.Mode.COOP
	var peer := ENetMultiplayerPeer.new()
	peer.create_client(ip, LAN_PORT)
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	GameState.character_by_peer[multiplayer.get_unique_id()] = character
	_version_check.send_hello()
	_rpc_register.rpc_id(1, character, _my_looks(character))

## The joiner's saved look for both survivors, since the host may hand it
## the other one when both picked the same.
func _my_looks(_character: String) -> Dictionary:
	var out := {}
	for c in GameState.CHARACTERS:
		out[c] = GameState.look(c)
	return out

## Joiner tells host its character and looks; host resolves a clash, then
## broadcasts who plays whom and what each survivor wears.
@rpc("any_peer", "reliable")
func _rpc_register(character: String, looks: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _verified.has(id):
		return  # a different version of the game: version_check.gd said why
	var host_char: String = GameState.character_by_peer.get(1, "zegan")
	if character == host_char:
		character = GameState.partner_character(host_char)
	GameState.character_by_peer[id] = character
	var custom: Variant = looks.get(character, {})
	GameState.customization_by_peer[id] = custom if custom is Dictionary and not custom.is_empty() else GameState.default_customization(character)
	if not GameState.customization_by_peer.has(1):
		GameState.customization_by_peer[1] = GameState.look(host_char)
	_rpc_roster.rpc(GameState.character_by_peer, GameState.customization_by_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_roster(roster: Dictionary, customs: Dictionary) -> void:
	GameState.character_by_peer = roster
	GameState.customization_by_peer = customs

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		partner_joined.emit(id)
		return
	# The host lets a joiner in once its hello shows the same game content.
	get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(func():
		if not _verified.has(id) and multiplayer.get_peers().has(id):
			session_failed.emit("Your friend's game is an older version. They need to close and reopen RaGoon City to update."))

func _on_peer_verified(id: int) -> void:
	if _verified.has(id):
		return
	_verified[id] = true
	partner_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	_verified.erase(id)
	GameState.character_by_peer.erase(id)
	partner_left.emit(id)

func is_coop() -> bool:
	return GameState.mode == GameState.Mode.COOP

func close() -> void:
	_attempt += 1
	_verified.clear()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
