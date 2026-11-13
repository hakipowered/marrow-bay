class_name MasterClock
extends Node3D
## The Undercroft's master clock (chapter 2), in the clock gallery: a tall
## longcase regulator with a locked drawer in its plinth, that once drove every slave clock in
## the tunnels. The wall of slave dials beside it, one for each room, all
## stopped at ten past eleven, the night the keeper pulled the field fuse
## and hid it in the case.
##
## The brass winding key (found in the map room) winds it: it ticks again,
## every dial jolts forward minute by minute in step and stops at 11:44, the
## clock strikes, and the drawer in the plinth springs open on the fuse. The chime carries through the tunnels, and
## something down here that counts hears it (the story's "hunt" scene starts
## when the fuse is taken).
##
## Placed against a wall: local +z points out into the room, the origin is
## on the floor at the wall face. The slave wall sits to its right (+x).

const FLAG := "c2_clock_open"
const KEY := "clock_key"
const FUSE_ID := "c2_fuse"
const SLAVES := ["LIFT SHAFT", "SERVICE TUNNEL", "KEEPER'S LODGE", "SURVEY ROOM", "CLOCK GALLERY", "MUSTER ROOM",
	"ENGINE HALL", "COAL YARD", "DEEP STACKS", "NORTH STAIR", "PUMP ROOM", "THE COUNTING HOUSE"]
const STOP_MIN := 10
## The scanned case is 2.19 m; the master regulator stands taller.
const CASE_S := 1.15
const DRAWER_OUT := 0.3
## Where the fuse lies in the open drawer, local.
const FUSE_AT := Vector3(0, 0.17 * CASE_S + 0.03, 0.435 * CASE_S + 0.3 - 0.17)
const END_MIN := 44

var _door: Node3D
var _hands: Array = []      # [hour hand, minute hand] per dial (master first)
var _minute := float(STOP_MIN)
var _running := false
var _tick_t := 0.0

static func is_open() -> bool:
	return GameState.has_flag(FLAG)

func _ready() -> void:
	add_to_group("master_clock")
	_build()
	if is_open():
		_door.position.z += DRAWER_OUT
		_minute = END_MIN
		_running = true
		_place_fuse.call_deferred()
	_set_hands(_minute)

func _place_fuse() -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level and not GameState.has_flag("taken:" + FUSE_ID) and not level.has_node("Pickup_" + FUSE_ID):
		level.place_pickup("key:fuse", global_transform * FUSE_AT, FUSE_ID)

# ------------------------------------------------------------------ the case

func _build() -> void:
	# The case: a tall scanned longcase clock, scaled up to a regulator's
	# height. Its hood is empty behind the glass, so the dial is ours.
	var case := RoomBuilder.prop(self, "vintage_grandfather_clock_01", Vector3(0, 0, 0.19 * CASE_S), 0.0, CASE_S, true)
	case.name = "Case"
	var dial := _dial(self, Vector3(0, 1.77 * CASE_S, 0.36 * CASE_S), 0.15 * CASE_S, "", true)
	_hands.append(dial)
	# The drawer in the plinth: shut flush with its front, the keyhole above.
	var wood := Mats.trim(Color(0.3, 0.14, 0.07), 0.45, 0.0)
	var brass := Mats.trim(Color(0.66, 0.5, 0.22), 0.3, 0.9)
	_door = Node3D.new()
	_door.name = "Drawer"
	_door.position = Vector3(0, 0.24 * CASE_S, 0.435 * CASE_S)
	add_child(_door)
	RoomBuilder._box(_door, Vector3(0, 0, 0), Vector3(0.42 * CASE_S, 0.16 * CASE_S, 0.02), wood, false)
	RoomBuilder._box(_door, Vector3(0, -0.07 * CASE_S, -0.17), Vector3(0.4 * CASE_S, 0.015, 0.34), wood, false)
	for x in [-0.2 * CASE_S, 0.2 * CASE_S]:
		RoomBuilder._box(_door, Vector3(x, -0.02 * CASE_S, -0.17), Vector3(0.015, 0.1 * CASE_S, 0.34), wood, false)
	UndercroftKit.bar(_door, Vector3(0, 0, 0.02), 0.012, 0.02, brass, "z")
	RoomBuilder._box(self, Vector3(0, 0.36 * CASE_S, 0.437 * CASE_S), Vector3(0.025, 0.04, 0.01), brass, false)   # keyhole escutcheon
	UndercroftKit.reach(self, self, Vector3(0, 1.1, 0.95), Vector3(1.0, 2.2, 0.6))
	_build_slaves()

## A clock face: a dark bezel, an ivory face with its twelve marks, and two
## hands. Returns [hour hand, minute hand].
func _dial(parent: Node3D, at: Vector3, r: float, text: String, roman := false) -> Array:
	var d := Node3D.new()
	d.position = at
	parent.add_child(d)
	var bezel := UndercroftKit.bar(d, Vector3(0, 0, -0.01), r + 0.03, 0.04, Mats.trim(Color(0.1, 0.08, 0.06), 0.4, 0.6), "z", 32)
	bezel.name = "Bezel"
	var face := UndercroftKit.bar(d, Vector3(0, 0, 0.012), r, 0.004, Mats.trim(Color(0.86, 0.82, 0.7), 0.6), "z", 32)
	face.name = "Face"
	var ink := Color(0.08, 0.06, 0.05)
	var numerals := ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(sin(a), cos(a), 0) * r * 0.8
		if roman:
			UndercroftKit.label(d, numerals[i], p + Vector3(0, 0, 0.016), int(r * 120), ink, 0.0, 0.001)
		else:
			var tick := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(r * 0.05, r * 0.16, 0.002)
			tick.mesh = bm
			tick.material_override = Mats.trim(ink, 0.6)
			tick.position = Vector3(sin(a), cos(a), 0) * r * 0.82 + Vector3(0, 0, 0.016)
			tick.rotation.z = -a
			d.add_child(tick)
	if text != "":
		UndercroftKit.label(d, text, Vector3(0, -r * 0.42, 0.016), int(r * 70), ink, 0.0, 0.001)
	var hour := _hand(d, r * 0.5, r * 0.07, 0.02)
	var minute := _hand(d, r * 0.78, r * 0.045, 0.024)
	return [hour, minute]

func _hand(d: Node3D, length: float, width: float, z: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, z)
	d.add_child(pivot)
	var h := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, length, 0.004)
	h.mesh = bm
	h.material_override = Mats.trim(Color(0.04, 0.035, 0.03), 0.4, 0.6)
	h.position = Vector3(0, length * 0.4, 0)
	pivot.add_child(h)
	return pivot

## The wall of slave dials to the right of the case, four across and three
## down, each with an enamel plate naming its room.
func _build_slaves() -> void:
	var plate := Mats.trim(Color(0.78, 0.74, 0.62), 0.55)
	var board := Mats.trim(Color(0.16, 0.07, 0.04), 0.5)
	RoomBuilder._box(self, Vector3(3.0, 2.0, 0.03), Vector3(3.9, 2.6, 0.05), board, false)
	UndercroftKit.label(self, "SERVICE  CLOCKS   -   DRIVEN  FROM  THE  MASTER", Vector3(3.0, 3.2, 0.06), 30, Color(0.75, 0.66, 0.4), 0.0, 0.0016)
	for i in SLAVES.size():
		var col := i % 4
		var row := i / 4
		var at := Vector3(1.6 + col * 0.93, 2.85 - row * 0.82, 0.07)
		_hands.append(_dial(self, at, 0.22, ""))
		RoomBuilder._box(self, at + Vector3(0, -0.3, -0.01), Vector3(0.62, 0.075, 0.01), plate, false)
		UndercroftKit.label(self, SLAVES[i], at + Vector3(0, -0.3, -0.003), 22, Color(0.12, 0.08, 0.06), 0.0, 0.0011)

func _set_hands(minutes: float) -> void:
	var total := 11.0 * 60.0 + minutes
	for pair in _hands:
		(pair[1] as Node3D).rotation.z = -TAU * fmod(total, 60.0) / 60.0
		(pair[0] as Node3D).rotation.z = -TAU * fmod(total / 60.0, 12.0) / 12.0

# ------------------------------------------------------------------ opening it

func interact_text(player: Node, _handle := -1) -> String:
	if is_open():
		return ""
	return "Wind the master clock" if _has_key(player) else "Check the master clock"

func interact(player: Node, _handle := -1) -> void:
	if is_open():
		return
	if _has_key(player):
		_rpc_request.rpc_id(1, player.peer_id)
	else:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Stopped at ten past eleven. The winding hole needs a small brass key.")

func _has_key(player: Node) -> bool:
	return Cheats.on("unlock_doors") or player.inventory.key_items.has(KEY)

@rpc("any_peer", "reliable", "call_local")
func _rpc_request(by_peer: int) -> void:
	if not multiplayer.is_server() or is_open():
		return
	_rpc_open.rpc(by_peer)

@rpc("authority", "reliable", "call_local")
func _rpc_open(by_peer: int) -> void:
	GameState.set_flag(FLAG)
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == by_peer and p.is_multiplayer_authority():
			p.inventory.remove_key(KEY)
	Sfx.play_at("clock_unlock", global_transform * Vector3(0, 0.6, 0.6), "breaker_throw", -2.0, 5.0)
	_running = true
	_advance()
	get_tree().call_group("story", "clock_opened")

## Every dial jolts forward a minute at a time, in step, and stops at 11:44;
## then the master strikes.
func _advance() -> void:
	await get_tree().create_timer(1.6).timeout
	while _minute < END_MIN:
		_minute += 1.0
		_set_hands(_minute)
		Sfx.play_at("clock_clack", global_transform * Vector3(2.5, 2.0, 0.3), "breaker_throw", -10.0, 6.0)
		await get_tree().create_timer(0.11).timeout
	await get_tree().create_timer(0.8).timeout
	# As it strikes, the drawer in the plinth springs open: the fuse.
	Sfx.play_at("clock_chime", global_transform * Vector3(0, 2.5, 0.4), "", 4.0, 30.0)
	var t := create_tween()
	t.tween_property(_door, "position:z", _door.position.z + DRAWER_OUT, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("drawer_open", global_transform * FUSE_AT, "breaker_throw", -4.0, 5.0)
	_place_fuse()
	for i in 2:
		await get_tree().create_timer(2.2).timeout
		Sfx.play_at("clock_chime", global_transform * Vector3(0, 2.5, 0.4), "", 4.0, 30.0)

func _process(delta: float) -> void:
	if not _running:
		return
	_tick_t += delta
	if _tick_t >= 1.0:
		_tick_t -= 1.0
		Sfx.play_at("clock_tick", global_transform * Vector3(0, 1.8, 0.5), "", -14.0, 3.0)
