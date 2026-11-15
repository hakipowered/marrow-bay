extends SceneTree
## Walking the pump room on her own legs (chapter 2): in at the door, round
## the dead pumps to the sump gate, down the steps to where the starting
## handle lies, and back up out of the pit. She steers along the navmesh
## path the way a player's stick would; nothing is placed by hand once she
## starts. Catches a body the navmesh walks through and a lip on the steps
## that stops anyone climbing out.
## Prints PUMP WALK OK or PUMP WALK FAIL.
##   godot --headless --path . --fixed-fps 60 --script tests/pump_walk.gd
const UC := "res://scenes/levels/undercroft.tscn"
var frames := 0
var p: Node
var room: Node
var fails := []
var legs := []
var leg := -1
var leg_t := 0.0
var path := PackedVector3Array()
var pi := 0
var lowest := INF

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)

func _start_leg() -> void:
	leg += 1
	leg_t = 0.0
	pi = 0
	if leg >= legs.size():
		p.move_input = Vector2.ZERO
		_check(lowest > -1.6, "never below the sump floor (lowest %.2f)" % lowest)
		# The man at the bottom can come up after her: the navmesh runs from
		# the sump floor out to the tunnel (the door's link, standing open).
		var o: Vector3 = room.global_position
		var from: Vector3 = o + room.get_script().HANDLE_AT
		var to := o + Vector3(1.6, 0, -1.1)
		var nav := NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, from, to, true)
		var end: Vector3 = nav[nav.size() - 1] if nav.size() > 0 else from
		_check(end.distance_to(to) < 0.8, "the navmesh climbs out of the sump to the tunnel (ends %.1f m off)" % end.distance_to(to))
		print("PUMP WALK %s" % ("OK" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
		quit(0 if fails.is_empty() else 1)
		return
	var map: RID = p.get_world_3d().navigation_map
	path = NavigationServer3D.map_get_path(map, p.global_position, legs[leg][1], true)
	path.append(legs[leg][1])
	if OS.has_environment("PW_DEBUG"):
		var o: Vector3 = room.global_position
		var pts := []
		for q in path:
			pts.append("(%.2f, %.2f, %.2f)" % [q.x - o.x, q.y, q.z - o.z])
		print("leg %d path (room coords): %s" % [leg, " ".join(pts)])

func _process(_d: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 150000:
		print("PUMP WALK FAIL: timeout on leg %d" % leg)
		quit(1)
	if frames == 3:
		var gs := root.get_node("GameState")
		gs.reset_run()
		gs.level_path = UC
		gs.shared_checkpoint = "ch2_lift"
		# The sump drained and its gate unhooked.
		gs.set_flag("c2_sump_drained")
		gs.set_flag("c2_sump_gate")
		root.get_node("Net").start_solo("zegan")
		change_scene_to_file(UC)
		return false
	if frames < 40:
		return false
	if p == null:
		p = get_first_node_in_group("players")
		room = get_first_node_in_group("pump_room")
		var cs := root.get_node("Cutscenes")
		if cs.active:
			cs._end()
		for z in get_nodes_in_group("zombies"):
			z.queue_free()
		for st in get_nodes_in_group("story"):
			st.set_physics_process(false)
		root.get_node("Cheats").flags["god_mode"] = true
		for d in get_nodes_in_group("doors"):
			if d.name.contains("pump_door") and not d.is_open:
				d._set_open(true, Vector3(0, 0, 1), false)
		var o: Vector3 = room.global_position
		var sc: Script = room.get_script()
		var stair: Rect2 = sc.STAIR
		var pit: Rect2 = sc.PIT
		var gate_stand := o + Vector3(stair.get_center().x, 0, pit.position.y - 0.75)
		var bottom := o + Vector3(stair.get_center().x, sc.FLOOR_Y, stair.end.y + 0.5)
		var valves := o + Vector3(sc.WHEEL_X + 0.5, 0, sc.VALVE_Z[1])
		p.global_position = o + Vector3(1.6, 0, -1.1)
		legs = [
			["in through the door to the valves", valves, 0.6],
			["from the valves round the pumps to the sump gate", gate_stand, 0.6],
			["down the steps to the bottom", bottom, 0.6],
			["to where the handle lies", o + sc.HANDLE_AT + Vector3(0.5, 0, 0), 0.7],
			["back up the steps out of the pit", gate_stand, 0.6],
		]
		_start_leg()
		return false
	if leg >= legs.size():
		return false
	leg_t += 1.0 / 60.0
	lowest = minf(lowest, p.global_position.y)
	var goal: Vector3 = legs[leg][1]
	var flat := Vector2(p.global_position.x - goal.x, p.global_position.z - goal.z).length()
	if flat < legs[leg][2] and absf(p.global_position.y - goal.y) < 0.4:
		_check(true, "%s (%.1f s)" % [legs[leg][0], leg_t])
		_start_leg()
		return false
	if leg_t > 20.0:
		_check(false, "%s: stopped at %s" % [legs[leg][0], p.global_position])
		p.global_position = goal + Vector3.UP * 0.05
		p.velocity = Vector3.ZERO
		_start_leg()
		return false
	while pi < path.size() - 1 and Vector2(path[pi].x - p.global_position.x, path[pi].z - p.global_position.z).length() < 0.35:
		pi += 1
	var to: Vector3 = path[pi] - p.global_position
	to.y = 0.0
	if to.length() < 0.01:
		p.move_input = Vector2.ZERO
		return false
	var local: Vector3 = Basis(Vector3.UP, p.yaw).inverse() * to.normalized()
	p.move_input = Vector2(local.x, local.z).limit_length(1.0)
	p.running = false
	return false
