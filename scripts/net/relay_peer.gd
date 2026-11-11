class_name RelayPeer
extends MultiplayerPeerExtension
## Tunnels Godot's high-level multiplayer through a WebSocket relay so two
## phones on different networks can play without port forwarding.
##
## Wire format (binary frames):
##   client -> relay : [u32 target_peer][u8 channel][u8 mode] payload  (target 0 = everyone else)
##   relay -> client : [u32 from_peer ][u8 channel][u8 mode] payload
## Control messages are JSON text frames: welcome / peer_joined / peer_left / error.

signal relay_error(message: String)

var _ws := WebSocketPeer.new()
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id := 0
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refuse := false
var _incoming: Array = []   # [{from, channel, mode, data}]
var _peers: Dictionary = {}

func open(url: String) -> Error:
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return err

func _poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			for id in _peers.keys():
				peer_disconnected.emit(id)
			_peers.clear()
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return
	while _ws.get_available_packet_count() > 0:
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

func _handle_control(text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match msg.get("type", ""):
		"welcome":
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
			relay_error.emit(str(msg.get("message", "relay error")))
			_close()

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
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_incoming.clear()
