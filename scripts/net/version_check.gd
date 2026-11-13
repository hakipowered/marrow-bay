extends Node
## Co-op version handshake: both phones must run the same game content.
##
## The joiner calls hello() on the host as soon as it connects. The host lets
## it in when the content builds match, and otherwise answers mismatch() so
## the joiner can say who needs to update. Net owns this node at
## /root/Net/VersionCheck.
##
## DON'T CHANGE THE RPCs BELOW (names, arguments or modes), and don't add any.
## Godot numbers a node's RPCs by their sorted names, and this handshake has
## to work between an older and a newer version of the game.

signal peer_verified(id: int)
signal peer_rejected(id: int, their_version: String)
signal rejected_by_host(host_version: String)


func send_hello() -> void:
	hello.rpc_id(1, PackMount.build_id, PackMount.version_name)


@rpc("any_peer", "reliable")
func hello(build: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if build == PackMount.build_id:
		peer_verified.emit(id)
	else:
		mismatch.rpc_id(id, PackMount.build_id, PackMount.version_name)
		peer_rejected.emit(id, version)


@rpc("authority", "reliable")
func mismatch(_host_build: String, host_version: String) -> void:
	rejected_by_host.emit(host_version)


## What to tell this player when their game and their friend's don't match.
static func explain(mine: String, theirs: String) -> String:
	match compare(mine, theirs):
		-1:
			return "Your friend has version %s and you have %s. Close and reopen RaGoon City to update, then join again." % [theirs, mine]
		1:
			return "Your friend has version %s and you have %s. They need to close and reopen RaGoon City to update." % [theirs, mine]
	return "Your game and your friend's don't match (%s / %s). Both of you close and reopen RaGoon City to update." % [mine, theirs]


## -1, 0 or 1 like "0.9" < "0.10"; 0 when either isn't a version number.
static func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for part in pa + pb:
		if not part.is_valid_int():
			return 0
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0
