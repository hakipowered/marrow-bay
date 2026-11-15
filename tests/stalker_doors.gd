extends SceneTree
## The hunting Tallyman and shut doors (chapter 2): he comes for her in the
## open, waits outside the pump room door when she shuts herself in, then
## gives up and walks back to where he came in, and comes for her again once
## she's back out in the tunnel.
## Prints STALKER DOORS OK or STALKER DOORS FAIL.
##   godot --headless --path . --fixed-fps 60 --script tests/stalker_doors.gd
const UC := "res://scenes/levels/undercroft.tscn"
const HOME := Vector3(32.9, 0.0, -8.3)
const INSIDE := Vector3(35.0, 0.0, 6.4)      # pump room, by the valves
const TUNNEL := Vector3(34.6, 0.0, 1.6)      # service tunnel, by the pump door
var frames := 0
var p: Node
var s: Node
var fails := []
var step := 0
var t0 := 0
var near_door := false
var door_min := INF
var waited := 0.0
var stooped := 1.0

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)

func _hold(at: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.move_input = Vector2.ZERO

func _process(_d: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 240000:
		print("STALKER DOORS FAIL: timeout at step %d" % step)
		quit(1)
	if frames == 3:
		var gs := root.get_node("GameState")
		gs.reset_run()
		gs.level_path = UC
		gs.shared_checkpoint = "ch2_lift"
		root.get_node("Net").start_solo("zegan")
		change_scene_to_file(UC)
		return false
	if frames < 40:
		return false
	if p == null:
		p = get_first_node_in_group("players")
		s = get_first_node_in_group("stalker")
		var cs := root.get_node("Cutscenes")
		if cs.active:
			cs._end()
		# Nothing else in the way: no infected, no story.
		for z in get_nodes_in_group("zombies"):
			z.queue_free()
		for st in get_nodes_in_group("story"):
			st.set_physics_process(false)
		root.get_node("Cheats").flags["god_mode"] = true
		var door = null
		for d in get_nodes_in_group("doors"):
			if d.name.contains("pump_door"):
				door = d
		if door and door.is_open:
			door._set_open(false, Vector3.FORWARD, false)
		s.activate(HOME)
		s.set_physics_process(true)
		t0 = frames
		step = 1
		return false
	var el := (frames - t0) / 60.0
	var door_at := Vector3(34.6, 0.0, 4.6)
	match step:
		1:
			# Shut in the pump room: he comes to the door and waits there.
			_hold(INSIDE)
			var dd: float = s.global_position.distance_to(door_at)
			door_min = minf(door_min, dd)
			if dd < 3.0:
				near_door = true
				waited += 1.0 / 60.0
			stooped = minf(stooped, s._stoop_k)
			if el > 18.0:
				_check(near_door, "he came to the pump room door after her (closest %.1f m)" % door_min)
				_check(waited > 1.5, "he waited outside it a while (%.1f s)" % waited)
				_check(stooped < 0.97, "he stooped under the clock gallery's door head (%.2f)" % stooped)
				_check(s.global_position.z < 4.4, "he stayed out in the tunnel")
				t0 = frames
				step = 2
		2:
			# Then loses the scent and walks back.
			_hold(INSIDE)
			if el > 30.0:
				var d: float = s.global_position.distance_to(HOME)
				_check(d < 3.0, "he gave up and walked back to where he came in (%.1f m off)" % d)
				t0 = frames
				step = 3
		3:
			# Out in the tunnel again: he comes for her.
			_hold(TUNNEL)
			if s.global_position.distance_to(TUNNEL) < 2.5 or el > 30.0:
				_check(s.global_position.distance_to(TUNNEL) < 2.5, "he came back for her once she was out in the tunnel")
				print("STALKER DOORS %s" % ("OK" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
				quit(0 if fails.is_empty() else 1)
				return true
	return false
