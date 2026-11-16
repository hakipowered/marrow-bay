extends Node
## Pings the partner's phone once a second, for the corner readout (frame
## rate and ping, Net.stats_text). Net owns this node at /root/Net/Ping.
##
## Its own node, not RPCs on Net: Godot numbers a node's RPCs by their sorted
## names, so adding these to Net would renumber Net's own and an older game
## talking to a newer one would call the wrong method before the version
## check turned it away.

## Round trips (ms), newest last.
var rtts: Array = []
## Pings sent and not back yet: usec sent.
var _waiting: Array = []
var _t := 0.0

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
			or multiplayer.get_peers().is_empty():
		rtts.clear()
		_waiting.clear()
		return
	_t -= delta
	if _t <= 0.0:
		_t = 1.0
		var now := Time.get_ticks_usec()
		_waiting.append(now)
		while _waiting.size() > 10:
			_waiting.pop_front()
		ping.rpc(now)

@rpc("any_peer", "unreliable")
func ping(sent_usec: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), sent_usec)

@rpc("any_peer", "unreliable")
func pong(sent_usec: int) -> void:
	_waiting.erase(sent_usec)
	rtts.append((Time.get_ticks_usec() - sent_usec) / 1000.0)
	while rtts.size() > 5:
		rtts.pop_front()

## To the partner's phone and back (ms): the middle of the last five, or
## longer if a ping has been out longer than that (a link that has frozen
## shows a climbing number, not the last good one). 0 before the first.
func ms() -> float:
	var out := 0.0
	if not rtts.is_empty():
		var s := rtts.duplicate()
		s.sort()
		out = s[s.size() / 2]
	if not _waiting.is_empty():
		var oldest := (Time.get_ticks_usec() - int(_waiting[0])) / 1000.0
		if oldest > 1500.0:
			out = maxf(out, oldest)
	return out
