extends SceneTree
## Chapter 2 (the Undercroft), end to end, solo, through the real prompts:
## the arrival in the lift, the engine hall scene, the generator's three
## missing parts, the master clock (winding key, the dials, the drawer and
## the fuse), the Tallyman's hunt, the diesel, Hardass on the tannoy, the
## muster room door, the Warden scene and fight, the starting handle, a
## reload part way, cranking with the waves of infected coming in out of
## sight, the lights and the flood door, and the last scene in the deep
## stacks. The infected are cleared out of the way (the bot's chapter 2 route
## fights them: tests/playtest.gd -- only route2).
## Prints CHAPTER 2 FLOW OK or CHAPTER 2 FLOW FAIL.
##   godot --headless --path . --fixed-fps 60 --script tests/chapter2_flow.gd
const UC := "res://scenes/levels/undercroft.tscn"
var frames := 0
var p: Node
var gs: Node
var cs: Node
var cheats: Node
var fails := []
var step := 0
var wait_to := 0
var wall_to := 0
var gen: Node
var story: Node
var _waves_seen := 0
var _crank_spawns: Array = []     # [name, position, seen by her when it appeared]
var _spawn_check: Array = []
var _story_cls: Script
var _heave_t := 0.0

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)

func _initialize() -> void:
	node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if str(n.name).begins_with("Z_crank_"):
		_spawn_check.append(n)

## Stands her `dist` m out from a point (n points from it towards her),
## facing it, and returns the prompt she gets.
func _prompt_at(target: Vector3, n: Vector3, dist: float) -> String:
	n.y = 0.0
	n = n.normalized()
	p.global_position = Vector3(target.x, 0.0, target.z) + n * dist
	p.velocity = Vector3.ZERO
	var face := atan2(n.x, n.z)
	p.body.global_rotation.y = face
	p.yaw = face
	p.sync_yaw = face
	p.move_input = Vector2.ZERO
	for i in 3:
		p.interact_ray.force_raycast_update()
	p._update_focus()
	return p._prompt_text

## Takes a pickup the way a player does: beside it, facing it, the prompt.
func _take(pid: String) -> bool:
	var node: Node = null
	for x in get_nodes_in_group("pickups"):
		if x.pickup_id == pid:
			node = x
	if node == null:
		_check(false, "item %s is in the level" % pid)
		return false
	var at: Vector3 = node.global_position
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	for r in [0.6, 0.8, 1.0, 1.2]:
		for k in 16:
			var dir := Vector3(sin(k * TAU / 16.0), 0.0, cos(k * TAU / 16.0))
			var c: Vector3 = Vector3(at.x, 0.0, at.z) + dir * r
			q.transform = Transform3D(Basis(), c + Vector3.UP * 0.83)
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var t: String = _prompt_at(at, dir, r)
			if t.begins_with("Pick up"):
				p.interact()
				_check(gs.has_flag("taken:" + pid), "picked up %s (%s)" % [pid, t])
				return gs.has_flag("taken:" + pid)
	_check(false, "a 'Pick up' prompt next to %s at %s" % [pid, str(at)])
	return false

func _obj() -> String:
	return str(gs.world_flags.get("objective", ""))

func _door(id: String) -> Node:
	for d in get_nodes_in_group("doors"):
		if d.door_id == id:
			return d
	return null

func _clear_infected() -> void:
	for z in get_nodes_in_group("zombies"):
		if z is CharacterBody3D and str(z.name).begins_with("Z_"):
			z.queue_free()

func _cutscene_over(id: String, limit_ms: int) -> bool:
	if cs.active and Time.get_ticks_msec() < wall_to:
		return false
	_check(not cs.active, "the %s scene ends by itself" % id)
	_check(gs.has_flag("story_" + id), "story_%s flag" % id)
	return true

func _process(_d: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 420000:
		print("TIMEOUT at step %d" % step)
		print("CHAPTER 2 FLOW FAIL: timeout")
		quit(1)
	if frames == 3:
		gs = root.get_node("GameState")
		cs = root.get_node("Cutscenes")
		cheats = root.get_node("Cheats")
		_story_cls = load("res://scripts/story/chapter2_story.gd")
		gs.reset_run()
		gs.level_path = UC
		gs.shared_checkpoint = "ch2_lift"
		root.get_node("Net").start_solo("zegan")
		change_scene_to_file(UC)
		return false
	if frames < 40:
		return false
	# Every crank infected: was it out of her sight when it came in?
	for z in _spawn_check:
		if is_instance_valid(z) and z.is_inside_tree():
			var seen := false
			var cam: Vector3 = p.camera.global_position
			for h in [0.3, 1.0, 1.6]:
				var q := PhysicsRayQueryParameters3D.create(cam, z.global_position + Vector3.UP * h, 1, [p.get_rid()])
				if p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					var fwd: Vector3 = -p.camera.global_transform.basis.z
					if fwd.angle_to((z.global_position + Vector3.UP * h - cam).normalized()) < deg_to_rad(50.0):
						seen = true
			_crank_spawns.append([str(z.name), z.global_position, seen])
	_spawn_check.clear()
	match step:
		0:
			p = get_first_node_in_group("players")
			story = current_scene.find_child("Story", false, false)
			gen = current_scene.find_child("GeneratorSet", true, false)
			_check(current_scene.name == "Undercroft", "chapter 2's level loads")
			_check(p != null and story != null and gen != null, "player, story and generator are there")
			var lift = get_first_node_in_group("vault_elevator")
			_check(lift != null and lift.in_car(p.global_position), "she starts in the lift car")
			_check(cs.active and cs.current == "c2_arrival", "the arrival scene plays (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 90000
			step = 1
		1:
			if not _cutscene_over("c2_arrival", 90000):
				return false
			var lift = get_first_node_in_group("vault_elevator")
			_check(lift.is_open, "the lift doors open on the service level")
			_check(_obj() == _story_cls.OBJ_OUT, "objective: %s" % _obj())
			_check(not p.input_locked, "she can move")
			_clear_infected()
			# Into the engine hall's west doorway: the hall scene.
			p.global_position = Vector3(40.6, 0.0, 3.0)
			step = 2
			wait_to = frames + 30
		2:
			if frames < wait_to:
				return false
			_check(cs.active and cs.current == "c2_hall", "walking into the engine hall starts its scene (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 90000
			step = 3
		3:
			if not _cutscene_over("c2_hall", 90000):
				return false
			var o := _obj()
			_check(o.contains("diesel") and o.contains("fuse") and o.contains("starting handle"), "objective lists what the generator needs: %s" % o)
			# The generator with nothing: three prompts, three answers.
			var g: Vector3 = gen.global_position
			var t := _prompt_at(g + Vector3(-0.1, 0, 0.0), Vector3(0, 0, 1), 1.0)
			_check(t == "Check the fuel tank", "fuel tank prompt: \"%s\"" % t)
			t = _prompt_at(g + Vector3(0.7, 0, 0.0), Vector3(0, 0, 1), 1.9)
			_check(t == "Check the control box", "control box prompt: \"%s\"" % t)
			t = _prompt_at(g + Vector3(-2.0, 0, 0), Vector3(-1, 0, 0), 1.1)
			_check(t == "Check the crank", "crank prompt: \"%s\"" % t)
			p.interact()
			_check(not gen.fitted("crank"), "nothing fitted without the parts")
			# The flood door: dead.
			var fd: Node = current_scene.find_child("FloodDoor", true, false)
			t = _prompt_at(fd.global_position, Vector3(0, 0, -1), 1.4)
			_check(t == "Check the flood door", "flood door prompt: \"%s\"" % t)
			# The survey room: the winding key on the surveyor's desk.
			var sd := _door("survey_door")
			_check(sd != null, "survey room door")
			if sd and not sd.is_open:
				sd._set_open(true, Vector3(0, 0, -1), false)
			p.global_position = Vector3(19.0, 0.0, -6.0)
			step = 4
			wait_to = frames + 10
		4:
			if frames < wait_to:
				return false
			_take("c2_clock_key")
			_take("c2_survey_note")
			_check(p.inventory.key_items.has("clock_key"), "the winding key is in her bag")
			_check(p.inventory.files.has("survey_note"), "the 1891 note is in Files")
			# The master clock.
			var clock: Node = current_scene.find_child("MasterClock", true, false)
			var t := _prompt_at(clock.global_position, clock.global_basis.z, 1.6)
			_check(t == "Wind the master clock", "master clock prompt: \"%s\"" % t)
			p.interact()
			step = 5
			wait_to = frames + 60 * 9
		5:
			if frames < wait_to:
				return false
			var clock: Node = current_scene.find_child("MasterClock", true, false)
			_check(gs.has_flag("c2_clock_open"), "the clock is wound and open")
			var end_min: int = clock.get_script().END_MIN
			_check(absf(clock._minute - end_min) < 0.01, "every dial stopped at 11:%d (%.0f)" % [end_min, clock._minute])
			_check(not p.inventory.key_items.has("clock_key"), "the key stays in the clock")
			_check(current_scene.has_node("Pickup_c2_fuse"), "the drawer springs open on the fuse")
			_take("c2_fuse")
			_check(p.inventory.key_items.has("fuse"), "the fuse is in her bag")
			p.global_position = Vector3(28.0, 0.0, -2.5)
			step = 6
			wait_to = frames + 40
		6:
			if frames < wait_to:
				return false
			_check(cs.active and cs.current == "c2_hunt", "taking the fuse brings the Tallyman (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 90000
			step = 7
		7:
			if not _cutscene_over("c2_hunt", 90000):
				return false
			var st = get_first_node_in_group("stalker")
			_check(st != null and st.active, "the Tallyman is hunting them")
			var sd := _door("stair_door")
			_check(sd != null and sd.is_open, "the back stair door is open (he came through it)")
			# The Tallyman leaves a safe room alone.
			p.global_position = Vector3(11.5, 0.0, 7.6)
			step = 8
			wait_to = frames + 20
		8:
			if frames < wait_to:
				return false
			var st = get_first_node_in_group("stalker")
			_check(st._nearest() == null, "the Tallyman doesn't go for her in the keeper's lodge")
			# Out to the coal yard shed: the diesel.
			_take("c2_diesel")
			_check(p.inventory.key_items.has("diesel_can"), "the diesel is in her bag")
			st.global_position = Vector3(20.0, 0.0, -30.0)   # far off while she works
			st.set_physics_process(false)
			var g: Vector3 = gen.global_position
			var t := _prompt_at(g + Vector3(-0.1, 0, 0.0), Vector3(0, 0, 1), 1.0)
			_check(t == "Pour in the diesel", "fuel prompt with the can: \"%s\"" % t)
			p.interact()
			t = _prompt_at(g + Vector3(0.7, 0, 0.0), Vector3(0, 0, 1), 1.9)
			_check(t == "Fit the fuse", "control box prompt with the fuse: \"%s\"" % t)
			p.interact()
			step = 9
			wait_to = frames + 40
		9:
			if frames < wait_to:
				return false
			_check(gen.fitted("fuel") and gen.fitted("fuse"), "diesel and fuse in")
			_check(not p.inventory.key_items.has("diesel_can") and not p.inventory.key_items.has("fuse"), "both used up")
			st_park()
			_check(cs.active and cs.current == "c2_intercom", "Hardass comes on the tannoy (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 90000
			step = 10
		10:
			if not _cutscene_over("c2_intercom", 90000):
				return false
			_check(gs.has_flag("unlocked:muster_door"), "he unbars the muster room door")
			_check(_obj() == _story_cls.OBJ_HANDLE, "objective: %s" % _obj())
			var md := _door("muster_door")
			var t := _prompt_at(md.global_position, Vector3(0, 0, -1), 1.0)
			_check(t != "" and not t.to_lower().contains("locked"), "muster door prompt: \"%s\"" % t)
			p.interact()
			step = 11
			wait_to = frames + 90
		11:
			if frames < wait_to:
				return false
			var md := _door("muster_door")
			_check(md.is_open, "the muster room door opens")
			p.global_position = Vector3(26.1, 0.0, 6.2)
			step = 12
			wait_to = frames + 30
		12:
			if frames < wait_to:
				return false
			_check(cs.active and cs.current == "c2_warden", "walking in starts the Warden scene (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 120000
			step = 13
		13:
			if not _cutscene_over("c2_warden", 120000):
				return false
			var b: Node = current_scene.get_node_or_null("Warden")
			_check(b != null and b.awake and b.is_in_group("zombies"), "the Warden is up and fighting")
			var st = get_first_node_in_group("stalker")
			_check(st == null or not st.active, "the Tallyman has lost them")
			var md := _door("muster_door")
			_check(md != null and not md.is_open and not gs.has_flag("unlocked:muster_door"), "the door is barred behind them for the fight")
			_check(_obj() == _story_cls.OBJ_WARDEN, "objective: %s" % _obj())
			_check(p.global_position.z > 5.0, "she is inside the room, not in the doorway")
			# The fight itself is tests/warden_fight.gd; here he goes down.
			cheats.set_cheat("god_mode", true)
			b.take_hit(5000.0, "p9", "torso", -b.global_basis.z)   # from behind
			step = 14
			wait_to = frames + 60 * 4
		14:
			if frames < wait_to:
				return false
			_check(gs.has_flag("c2_warden_dead"), "the Warden is dead")
			_check(current_scene.has_node("Pickup_c2_crank"), "the starting handle drops where he fell")
			var md := _door("muster_door")
			_check(md.is_open and gs.has_flag("unlocked:muster_door"), "the door opens again after the fight")
			_check(_obj() == _story_cls.OBJ_FIT, "objective: %s" % _obj())
			# Reload here: he stays dead, the handle stays on the floor.
			reload_current_scene()
			step = 15
			wait_to = frames + 60
		15:
			if frames < wait_to:
				return false
			p = get_first_node_in_group("players")
			gen = current_scene.find_child("GeneratorSet", true, false)
			_check(not cs.active, "no scene replays after a reload")
			var b: Node = current_scene.get_node_or_null("Warden")
			_check(b == null, "no Warden after a reload")
			_check(current_scene.has_node("Pickup_c2_crank"), "the handle is still on the floor after a reload")
			_check(gen.fitted("fuel") and gen.fitted("fuse") and not gen.fitted("crank"), "the generator keeps its parts after a reload")
			var fd: Node = current_scene.find_child("FloodDoor", true, false)
			_check(not gs.has_flag("c2_flood_open"), "the flood door is still shut")
			_check(_obj() == _story_cls.OBJ_FIT, "objective after a reload: %s" % _obj())
			_clear_infected()
			_take("c2_crank")
			var g: Vector3 = gen.global_position
			var t := _prompt_at(g + Vector3(-2.0, 0, 0), Vector3(-1, 0, 0), 1.1)
			_check(t == "Fit the starting handle", "crank prompt with the handle: \"%s\"" % t)
			p.interact()
			step = 16
			wait_to = frames + 30
		16:
			if frames < wait_to:
				return false
			_check(gen.fitted("crank"), "the starting handle is on")
			_check(_obj() == _story_cls.OBJ_CRANK, "objective: %s" % _obj())
			var g: Vector3 = gen.global_position
			var t := _prompt_at(g + Vector3(-2.0, 0, 0), Vector3(-1, 0, 0), 1.1)
			_check(t == "Crank the engine", "crank prompt: \"%s\"" % t)
			cheats.set_cheat("god_mode", true)
			p.interact()
			_check(p.working == "crank", "she takes the handle and heaves")
			_heave_t = 0.0
			step = 17
			wall_to = Time.get_ticks_msec() + 200000
		17:
			# Heave until it catches; whoever comes in is seen off (her partner
			# would), after we've noted where it came from.
			for z in get_nodes_in_group("zombies"):
				if str(z.name).begins_with("Z_crank_") and z.global_position.distance_to(p.global_position) < 6.0:
					z.queue_free()
			if p.working != "crank" and not gen.running():
				p.interact()
			if gen.running() or Time.get_ticks_msec() > wall_to:
				_check(gen.running(), "the generator catches (progress %.2f)" % gen.progress)
				var gcls: Script = gen.get_script()
				_check(gen._waves_done == gcls.WAVES.size(), "all %d waves came (%d)" % [gcls.WAVES.size(), gen._waves_done])
				var expect := 0
				for m in gcls.WAVE_MIX:
					expect += m.size()
				_check(_crank_spawns.size() == expect, "%d infected came in for the waves (%d)" % [expect, _crank_spawns.size()])
				var seen := []
				for s in _crank_spawns:
					if s[2]:
						seen.append("%s at %s" % [s[0], str(s[1].snapped(Vector3.ONE * 0.1))])
				_check(seen.is_empty(), "none of them appeared in her view: %s" % ", ".join(seen))
				step = 18
				wait_to = frames + 60 * 8
		18:
			if frames < wait_to:
				return false
			_check(p.working == "", "she lets go of the handle when it catches")
			_check(gs.has_flag("power:undercroft"), "the Undercroft has power")
			var pw: Node = current_scene.find_child("UndercroftPower", true, false)
			var lit := 0
			var all := 0
			for l in get_nodes_in_group("uc_work_light"):
				all += 1
				lit += 1 if l.visible and l.light_energy > 0.0 else 0
			_check(all > 0 and lit == all, "the work lights are on (%d of %d)" % [lit, all])
			_check(gs.has_flag("c2_flood_open"), "the flood door goes up")
			_check(_obj() == _story_cls.OBJ_FLOOD, "objective: %s" % _obj())
			var fd: Node = current_scene.find_child("FloodDoor", true, false)
			_check(fd._slab.position.y > 2.0, "the flood door's slab is up (%.2f)" % fd._slab.position.y)
			# Through it, into the deep stacks.
			p.global_position = Vector3(46.0, 0.0, 14.0)
			step = 19
			wait_to = frames + 40
		19:
			if frames < wait_to:
				return false
			_check(cs.active and cs.current == "c2_end", "the deep stacks scene plays (%s)" % str(cs.current))
			wall_to = Time.get_ticks_msec() + 90000
			step = 20
		20:
			if not _cutscene_over("c2_end", 90000):
				return false
			_check(gs.has_flag("c2_complete"), "chapter 2 complete")
			_check(_obj() == _story_cls.OBJ_END, "objective: %s" % _obj())
			print("CHAPTER 2 FLOW OK" if fails.is_empty() else "CHAPTER 2 FLOW FAIL: %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	return false

## Keep the Tallyman parked away from her for the rest of the run.
func st_park() -> void:
	var st = get_first_node_in_group("stalker")
	if st:
		st.global_position = Vector3(20.0, 0.0, -30.0)
