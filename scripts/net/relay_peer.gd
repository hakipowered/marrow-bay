class_name RelayPeer
extends MultiplayerPeerExtension
## Tunnels Godot's high-level multiplayer through a WebSocket relay so two
## phones on different networks can play without port forwarding.
##
## Wire format (binary frames):
##   client -> relay : [u32 target_peer][u8 channel][u8 mode] payload  (target 0 = everyone else)
##   relay -> client : [u32 from_peer ][u8 channel][u8 mode] payload
## Control messages are JSON text frames: welcome / peer_joined / peer_left / error.
##
## When the connection ends, relay_closed says why, once, as one of:
##   no_room      the relay has no game open with this code (a joiner)
##   room_full    that game already has two players
##   code_taken   another host already has this code (a host)
##   host_left    the host closed their game
##   unreachable  the relay never answered (no internet, DNS, blocked)
##   lost         the connection dropped after the relay had let us in
## Not emitted when this side closes on purpose (Net.close()).

signal relay_closed(kind: String)

## Why the connection ended (see relay_closed), "" while it's still open.
var close_kind := ""

var _ws := WebSocketPeer.new()
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id := 0
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refuse := false
var _incoming: Array = []   # [{from, channel, mode, data}]
var _peers: Dictionary = {}
var _welcomed := false

func open(url: String) -> Error:
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return err

func _poll() -> void:
	if close_kind != "":
		return
	_ws.poll()
	# Read what arrived before looking at the state: the relay's "No game
	# with that code" comes in the same moment as it closes the socket, and
	# skipping it is how a wrong code used to show up as "Relay timed out".
	while close_kind == "" and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_handle_control(pkt.get_string_from_utf8())
		elif pkt.size() >= 6:
			var from := pkt.decode_u32(0)
			_incoming.append({
				"from": from,
				"channel": pkt[4],
				"mode": pkt[5],
				"data": pkt.slice(6),
			})
	if close_kind == "" and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_finish(_why_closed())

## The relay closes a refused socket with its reason ("No game with that
## code"), and the joiner's socket with "Host left" when the host goes.
func _why_closed() -> String:
	var kind := kind_for(_ws.get_close_reason())
	if kind != "":
		return kind
	return "lost" if _welcomed else "unreachable"

## The relay's words (worker.js / local_relay.js) as a relay_closed kind.
static func kind_for(message: String) -> String:
	var m := message.to_lower()
	if m.contains("no game"):
		return "no_room"
	if m.contains("full"):
		return "room_full"
	if m.contains("already in use"):
		return "code_taken"
	if m.contains("host left"):
		return "host_left"
	return ""

func _finish(kind: String) -> void:
	if close_kind != "":
		return
	close_kind = kind
	for id in _peers.keys():
		peer_disconnected.emit(id)
	_peers.clear()
	_incoming.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	relay_closed.emit(kind)

func _handle_control(text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match msg.get("type", ""):
		"welcome":
			_welcomed = true
			_unique_id = int(msg["id"])
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			for id in msg.get("peers", []):
				_peers[int(id)] = true
				peer_connected.emit(int(id))
		"peer_joined":
			var id := int(msg["id"])
			if _refuse and _unique_id == 1:
				return
			_peers[id] = true
			peer_connected.emit(id)
		"peer_left":
			var id := int(msg["id"])
			if _peers.erase(id):
				peer_disconnected.emit(id)
		"error":
			var kind := kind_for(str(msg.get("message", "")))
			_finish(kind if kind != "" else ("lost" if _welcomed else "unreachable"))

func _get_available_packet_count() -> int:
	return _incoming.size()

func _get_packet_script() -> PackedByteArray:
	return _incoming.pop_front()["data"] if not _incoming.is_empty() else PackedByteArray()

func _get_packet_peer() -> int:
	return _incoming[0]["from"] if not _incoming.is_empty() else 0

func _get_packet_channel() -> int:
	return _incoming[0]["channel"] if not _incoming.is_empty() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[0]["mode"] if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var header := PackedByteArray()
	header.resize(6)
	header.encode_u32(0, max(_target, 0))
	header[4] = _channel
	header[5] = _mode
	# Negative target = everyone except -target. With two players that is
	# the same as "everyone else", which the relay does for target 0.
	return _ws.send(header + buffer, WebSocketPeer.WRITE_MODE_BINARY)

func _get_max_packet_size() -> int:
	return 1 << 20

func _set_target_peer(peer: int) -> void: _target = peer
func _get_unique_id() -> int: return _unique_id
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return _status
func _is_server() -> bool: return _unique_id == 1
func _is_server_relay_supported() -> bool: return true
func _set_transfer_channel(c: int) -> void: _channel = c
func _get_transfer_channel() -> int: return _channel
func _set_transfer_mode(m: MultiplayerPeer.TransferMode) -> void: _mode = m
func _get_transfer_mode() -> MultiplayerPeer.TransferMode: return _mode
func _set_refuse_new_connections(e: bool) -> void: _refuse = e
func _is_refusing_new_connections() -> bool: return _refuse
func _get_packet_peer_id() -> int: return _get_packet_peer()

func _disconnect_peer(_peer: int, _force: bool) -> void:
	pass  # the relay owns connections; a player leaves by closing.

func _close() -> void:
	if close_kind == "":
		close_kind = "closed"   # on purpose: nothing to tell the player
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_incoming.clear()
