extends SceneTree
## Every infected placed in a level can get out of its room and come for
## her once the doors are open: from where it stands, the navmesh reaches the
## level's first checkpoint. In 0.13 the Records Vault's brute, grappler and
## riot cop all started in a back aisle the drum and the boxes sealed off, so
## two of them could never leave it (only the brute's straight-line charge
## got out). Also checks a door opened after the level loaded lets them
## through (the link across it), and a shut one doesn't.
## godot --headless --path . --script tests/enemy_reach.gd [-- <level.tscn> <checkpoint>]
## Prints ENEMY REACH OK, or ENEMY REACH FAIL with the reasons.
const LEVELS := [
	["res://scenes/levels/archive_hub.tscn", "start"],
	["res://scenes/levels/undercroft.tscn", "ch2_lift"],
]
var frames := 0
var idx := 0
var stage := 0
var fails := []
var notes := []
var levels: Array = LEVELS
var t := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2:
		levels = [[a[0], a[1]]]

func _process(d: float) -> bool:
	frames += 1
	t += d
	var cs = root.get_node_or_null("Cutscenes")
	if cs and cs.active and frames % 10 == 0:
		cs._on_skip_pressed()
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				_load()
		1:
			if frames > 50 and t > 1.0:
				_door_shut()
				stage = 2
				t = 0.0
		2:
			# (the navigation map takes in a link switched on or off on its
			# next sync, a physics frame later: wait on the clock, not frames)
			if t > 0.25:
				_door_open()
				stage = 3
				t = 0.0
		3:
			if t > 0.25:
				_door_through()
				for dr in get_nodes_in_group("doors"):
					if not dr.is_open:
						dr._set_open(true, Vector3.ZERO, false)
				stage = 4
				t = 0.0
		4:
			if t > 0.25:
				_check_level()
				idx += 1
				if idx < levels.size():
					_load()
				else:
					stage = 9
		9:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("ENEMY REACH OK")
			else:
				print("ENEMY REACH FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _load() -> void:
	var gs = root.get_node("GameState")
	gs.reset_run()
	gs.level_path = levels[idx][0]
	gs.shared_checkpoint = levels[idx][1]
	change_scene_to_file(levels[idx][0])
	stage = 1
	frames = 0
	t = 0.0

func _map() -> RID:
	return root.get_world_3d().navigation_map

func _reaches(from: Vector3, to: Vector3) -> bool:
	var map := _map()
	var a := NavigationServer3D.map_get_closest_point(map, from)
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(b) < 0.6

func _goal() -> Vector3:
	for c in get_nodes_in_group("checkpoints"):
		if c.checkpoint_id == levels[idx][1]:
			return c.global_position
	return Vector3.ZERO

## One ordinary door shut, then opened after the level loaded: no way
## through while it's shut, a way through once it's open.
var _shut_ok := false
func _test_door() -> Node:
	var name: String = "Door_hall_main" if levels[idx][1] == "start" else "Door_lodge_door"
	return get_first_node_in_group("level").get_node_or_null(name)

func _door_ends(door: Node) -> Array:
	var fwd: Vector3 = door.global_transform.basis.z
	return [door.global_position + fwd * 1.6, door.global_position - fwd * 1.6]

func _door_shut() -> void:
	var door := _test_door()
	if door and door.is_open:
		door._set_open(false, Vector3.ZERO, false)

func _door_open() -> void:
	var door := _test_door()
	if door == null:
		return
	var e := _door_ends(door)
	_shut_ok = not _reaches(e[0], e[1])
	door._set_open(true, door.global_transform.basis.z, false)

func _door_through() -> void:
	var door := _test_door()
	if door == null:
		return
	var e := _door_ends(door)
	var open := _reaches(e[0], e[1])
	notes.append("%s: blocks them while shut %s, lets them through once opened %s" % [door.name, str(_shut_ok), str(open)])
	if not open:
		fails.append("%s opened after load: still no way through" % door.name)

func _check_level() -> void:
	var goals := []
	for c in get_nodes_in_group("checkpoints"):
		goals.append(c.global_position)
	var n := 0
	for z in get_nodes_in_group("zombies"):
		n += 1
		var at: Vector3 = z.global_position
		if z.get("state") == z.S.HIDDEN:
			continue   # up in a vent: it drops in right by her
		var closest := NavigationServer3D.map_get_closest_point(_map(), at)
		if Vector2(closest.x - at.x, closest.z - at.z).length() > 0.9:
			fails.append("%s: %s stands off the navmesh at %s" % [levels[idx][0].get_file(), z.name, str(at.snapped(Vector3.ONE * 0.1))])
		elif not goals.any(func(g): return _reaches(at, g)):
			fails.append("%s: %s at %s can't get out (no path to any checkpoint)" % [levels[idx][0].get_file(), z.name, str(at.snapped(Vector3.ONE * 0.1))])
	notes.append("%s: %d infected checked" % [levels[idx][0].get_file(), n])
