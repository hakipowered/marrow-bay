extends Node
## Session setup: solo, online via relay (room code / invite link), or LAN.

signal session_ready
signal partner_joined(peer_id: int)
signal partner_left(peer_id: int)
signal session_failed(reason: String)

## Set this to your deployed relay (see relay/README.md).
const RELAY_URL := "wss://ragoon-city-relay.example.workers.dev"
const LAN_PORT := 24680
const INVITE_SCHEME := "ragooncity://join/"
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

var room_code := ""
var relay_url := RELAY_URL

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): session_ready.emit())
	multiplayer.connection_failed.connect(func(): session_failed.emit("Could not connect"))
	multiplayer.server_disconnected.connect(func(): session_failed.emit("Host left the game"))
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		relay_url = cfg.get_value("net", "relay_url", RELAY_URL)
	if OS.get_environment("RAGOON_RELAY") != "":
		relay_url = OS.get_environment("RAGOON_RELAY")

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
	for i in 6:
		s += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return s

func invite_link() -> String:
	return INVITE_SCHEME + room_code

## Accepts "ABC123", "ragooncity://join/ABC123" or a pasted message containing it.
static func parse_code(text: String) -> String:
	var t := text.strip_edges().to_upper()
	var idx := t.find("JOIN/")
	if idx >= 0:
		t = t.substr(idx + 5)
	var out := ""
	for ch in t:
		if CODE_ALPHABET.contains(ch):
			out += ch
		if out.length() == 6:
			break
	return out

func host_online(character: String, fixed_code := "") -> String:
	close()
	room_code = fixed_code if fixed_code != "" else new_room_code()
	_open_relay("host", character)
	return room_code

func join_online(code: String, character: String) -> void:
	close()
	room_code = parse_code(code)
	_open_relay("join", character)

func _open_relay(role: String, character: String) -> void:
	GameState.mode = GameState.Mode.COOP
	var peer := RelayPeer.new()
	peer.relay_error.connect(func(m): session_failed.emit(m))
	var url := "%s/room/%s?role=%s" % [relay_url, room_code, role]
	if peer.open(url) != OK:
		session_failed.emit("Could not reach relay")
		return
	multiplayer.multiplayer_peer = peer
	_wait_for_id(character)

func _wait_for_id(character: String) -> void:
	var peer := multiplayer.multiplayer_peer
	var t := 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		session_failed.emit("Relay timed out")
		return
	GameState.character_by_peer[multiplayer.get_unique_id()] = character
	if multiplayer.is_server():
		session_ready.emit()
	else:
		session_ready.emit()
		_rpc_register.rpc_id(1, character, GameState.customization_by_peer.get(multiplayer.get_unique_id(), {}))

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
	_rpc_register.rpc_id(1, character, GameState.customization_by_peer.get(multiplayer.get_unique_id(), {}))

## Joiner tells host its character; host resolves conflicts and broadcasts the roster.
@rpc("any_peer", "reliable")
func _rpc_register(character: String, custom: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var host_char: String = GameState.character_by_peer.get(1, "zegan")
	if character == host_char:
		character = GameState.partner_character(host_char)
	GameState.character_by_peer[id] = character
	GameState.customization_by_peer[id] = custom
	_rpc_roster.rpc(GameState.character_by_peer, GameState.customization_by_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_roster(roster: Dictionary, customs: Dictionary) -> void:
	GameState.character_by_peer = roster
	GameState.customization_by_peer = customs

func _on_peer_connected(id: int) -> void:
	partner_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	GameState.character_by_peer.erase(id)
	partner_left.emit(id)

func is_coop() -> bool:
	return GameState.mode == GameState.Mode.COOP

func close() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
