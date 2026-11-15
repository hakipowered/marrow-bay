extends Node
## What's in the item box, RE style. Every box in every safe room opens onto
## this one store (GameState.item_box), and in co-op the two survivors share
## it: what one of them puts in at the office, the other can take out in the
## keeper's lodge. It goes into every save ("item_box" in the snapshot), so
## Continue and Load bring it back as it was.
##
## Supplies stack without limit in the box, one entry per kind; every gun is
## its own entry and keeps the rounds loaded in it.
##
## Co-op: the host keeps the real contents and sends every change to both
## phones. A phone asks the host to put a stack in (it has already left that
## phone's bag) or to take one out (it lands in that phone's bag when the
## host says yes), so two survivors grabbing the last box of shells at once
## can't both get it. Anything that doesn't fit goes back in the box.

signal changed
## Something came out of the box into this phone's bag (got = how many).
signal given(id: String, got: int)
## The host turned a take down (the partner got there first).
signal refused(text: String)

## More than anyone will ever store; only a guard against a runaway loop.
const MAX_ENTRIES := 200
## How the box lists things: guns, then grenades, then ammo, then supplies.
const ORDER := {"weapon": 0, "throwable": 1, "ammo": 2, "item": 3}

## {"k": key, "id": String, "n": int, "mag": int}, in the order they went in.
## Keys are the same on both phones (the host hands them out, and a loaded
## save numbers them the same way everywhere).
var entries: Array = []
var _next_key := 1

func _ready() -> void:
	# Solo pauses the world while the box screen is open.
	process_mode = Node.PROCESS_MODE_ALWAYS

# ---------------------------------------------------------------- reading

func is_empty() -> bool:
	return entries.is_empty()

## What the box screen shows, in its order.
func sorted() -> Array:
	var out := entries.duplicate()
	out.sort_custom(func(a, b):
		var ra: int = ORDER.get(ItemInfo.kind(a["id"]), 4)
		var rb: int = ORDER.get(ItemInfo.kind(b["id"]), 4)
		return ra < rb if ra != rb else int(a["k"]) < int(b["k"]))
	return out

func entry(key: int) -> Dictionary:
	var i := _index(key)
	return entries[i] if i >= 0 else {}

## How many of id are stored (every gun of that kind, every round).
func count(id: String) -> int:
	var n := 0
	for e in entries:
		if e["id"] == id:
			n += int(e["n"])
	return n

func _index(key: int) -> int:
	for i in entries.size():
		if int(entries[i]["k"]) == key:
			return i
	return -1

# ---------------------------------------------------------------- saving

## For the save file: [[id, n, mag], ...] in the order they went in.
func to_save() -> Array:
	var out := []
	for e in entries:
		out.append([e["id"], int(e["n"]), int(e["mag"])])
	return out

## A save's box (older saves have none: an empty box). JSON brings numbers
## back as floats. Keys are numbered from 1 again, the same on both phones.
func from_save(data: Variant) -> void:
	entries.clear()
	_next_key = 1
	if data is Array:
		for s in data:
			if s is Array and s.size() >= 2 and str(s[0]) != "" and int(s[1]) > 0:
				_put(str(s[0]), int(s[1]), int(s[2]) if s.size() > 2 else 0)
	changed.emit()

func clear() -> void:
	from_save([])

## Puts n of id in (host side, or loading). Returns how many went in.
func _put(id: String, n: int, mag := 0) -> int:
	if n <= 0:
		return 0
	var gun := ItemInfo.kind(id) == "weapon"
	if not gun:
		for e in entries:
			if e["id"] == id:
				e["n"] = int(e["n"]) + n
				return n
	if entries.size() >= MAX_ENTRIES:
		return 0
	entries.append({"k": _next_key, "id": id, "n": 1 if gun else n, "mag": mag if gun else 0})
	_next_key += 1
	return 1 if gun else n

# ---------------------------------------------------------------- asking the host

## This phone puts a stack in. The caller has already taken it out of the bag.
func store(id: String, n: int, mag := 0) -> void:
	_rpc_store.rpc_id(1, id, n, mag)

## This phone takes up to n out of the entry with this key, into its bag.
func take(key: int, n: int) -> void:
	_rpc_take.rpc_id(1, key, n)

## The joining phone asks for the box as the host has it (the box screen
## opening), in case a change was missed.
func refresh_from_host() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_ask_state.rpc_id(1)

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()

@rpc("any_peer", "reliable", "call_local")
func _rpc_store(id: String, n: int, mag: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var put := _put(id, n, mag)
	if put < n:
		_rpc_give.rpc_id(peer, id, n - put, mag)
	_broadcast()

@rpc("any_peer", "reliable", "call_local")
func _rpc_take(key: int, n: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var i := _index(key)
	if i < 0 or n <= 0:
		_rpc_refused.rpc_id(peer, "Your partner already took that out." if Net.is_coop() else "That isn't in the box any more.")
		_rpc_state.rpc_id(peer, _wire(), _next_key)
		return
	var e: Dictionary = entries[i]
	var got := mini(n, int(e["n"]))
	e["n"] = int(e["n"]) - got
	if int(e["n"]) <= 0:
		entries.remove_at(i)
	_rpc_give.rpc_id(peer, e["id"], got, int(e["mag"]))
	_broadcast()

@rpc("any_peer", "reliable")
func _rpc_ask_state() -> void:
	if multiplayer.is_server():
		_rpc_state.rpc_id(_sender(), _wire(), _next_key)

func _broadcast() -> void:
	_rpc_state.rpc(_wire(), _next_key)

## What goes over the wire: the save's entries plus their keys.
func _wire() -> Array:
	var out := []
	for e in entries:
		out.append([int(e["k"]), e["id"], int(e["n"]), int(e["mag"])])
	return out

@rpc("authority", "reliable", "call_local")
func _rpc_state(wire: Array, next_key: int) -> void:
	if not multiplayer.is_server():
		entries.clear()
		for w in wire:
			entries.append({"k": int(w[0]), "id": str(w[1]), "n": int(w[2]), "mag": int(w[3])})
		_next_key = next_key
	changed.emit()

## The host's yes: the stack goes into this phone's bag. Whatever doesn't
## fit (the bag filled up on the way) goes straight back in the box.
@rpc("authority", "reliable", "call_local")
func _rpc_give(id: String, n: int, mag: int) -> void:
	var p := _local_player()
	if p == null:
		store(id, n, mag)
		return
	var inv = p.inventory
	var got := 0
	if ItemInfo.kind(id) == "weapon":
		if inv.count(id) == 0 and inv.add(id) == 1:
			inv.mag[id] = mag
			got = 1
	else:
		got = inv.add(id, n)
	if got < n:
		store(id, n - got, mag)
	# The partner's copy of this bag (and so the host's saves) hears at once.
	p.set("_inv_sync_t", 0.0)
	p._emit_ammo()
	given.emit(id, got)

@rpc("authority", "reliable", "call_local")
func _rpc_refused(text: String) -> void:
	refused.emit(text)

func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return p
	return null
