extends SceneTree
## The Warden fight's rules (chapter 2 boss), with real pistol shots where
## it matters (the hitboxes have to sit on the model): the riot shield stops
## shots from the front but not the legs; the growth on his back takes
## triple damage and enough of it drops him to his knees, then he gets up;
## at half health he roars, loses the shield and goes faster; he hurts
## whoever is in reach; and when he dies the starting handle drops and the
## barred door opens. Prints WARDEN FIGHT OK or WARDEN FIGHT FAIL.
##   godot --headless --path . --fixed-fps 60 --script tests/warden_fight.gd
const UC := "res://scenes/levels/undercroft.tscn"
var frames := 0
var p: Node
var b: Node
var gs: Node
var cheats: Node
var fails := []
var step := 0
var wait_to := 0
var _hp0 := 0.0
var _shots := 0
var _target: Vector3
var _zone_want := ""
var _kneel_seen := false

func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)

func _zone_box(zone: String) -> Area3D:
	for a in b._hitboxes:
		if is_instance_valid(a) and a.get_meta("hit_zone", "") == zone:
			return a
	return null

## Points her camera (and gun) at a spot; a few frames to settle.
func _aim(pt: Vector3) -> float:
	var cam: Vector3 = p.camera.global_position
	var d := (pt - cam).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1.0, 1.0))
	p.aiming = true
	var fwd: Vector3 = -p.camera.global_transform.basis.z
	return rad_to_deg(fwd.angle_to(d))

func _stand(at: Vector3, look: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	var d := look - at
	var y := atan2(-d.x, -d.z)
	p.yaw = y
	p.body.global_rotation.y = y
	p.move_input = Vector2.ZERO

## Fires `n` aimed pistol shots at a hitbox zone, one every 0.4 s.
func _shoot_zone(zone: String, n: int) -> void:
	_zone_want = zone
	_shots = n
	step_fire = 0

var step_fire := 0

## Called every frame while shooting; returns true when done.
func _tick_fire() -> bool:
	var box := _zone_box(_zone_want)
	if box == null:
		_check(false, "the %s hitbox exists" % _zone_want)
		return true
	var err := _aim(box.global_position)
	step_fire += 1
	if step_fire % 24 == 12 and err < 1.5:
		p.fire_held = true
	elif step_fire % 24 == 14:
		p.fire_held = false
		_shots -= 1
	return _shots <= 0 and step_fire % 24 == 20

func _process(_d: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 240000:
		print("TIMEOUT at step %d" % step)
		print("WARDEN FIGHT FAIL: timeout")
		quit(1)
	if frames == 3:
		gs = root.get_node("GameState")
		cheats = root.get_node("Cheats")
		gs.reset_run()
		for f in ["story_c2_arrival", "c2_arrival", "story_c2_hall", "story_c2_hunt", "c2_hunt", "c2_hunt_over", "story_c2_intercom", "story_c2_warden", "c2_clock_open", "taken:c2_fuse"]:
			gs.set_flag(f)
		gs.level_path = UC
		gs.shared_checkpoint = "ch2_lift"
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(UC)
		return false
	if frames < 50:
		return false
	match step:
		0:
			p = get_first_node_in_group("players")
			b = current_scene.get_node_or_null("Warden")
			_check(b != null, "a game saved in the fight puts the Warden back in his room")
			if b == null:
				_finish()
				return true
			for z in get_nodes_in_group("zombies"):
				if z != b:
					z.queue_free()
			_check(b.awake and b.is_in_group("zombies") and b.is_in_group("boss"), "he is awake, an infected and a boss")
			var zones := {}
			for a in b._hitboxes:
				zones[a.get_meta("hit_zone", "")] = true
			for z in ["head", "torso", "arm", "leg", "wound"]:
				_check(zones.has(z), "%s hitbox" % z)
			var md: Node = null
			for d in get_nodes_in_group("doors"):
				if d.door_id == "muster_door":
					md = d
			_check(md != null and not md.is_open and not gs.has_flag("unlocked:muster_door"), "the muster door is barred during the fight")
			cheats.set_cheat("god_mode", true)
			cheats.set_cheat("infinite_ammo", true)
			cheats.set_cheat("all_weapons", true)
			# Hold him still in the middle of the room, facing the door.
			b.set_physics_process(false)
			b.global_position = Vector3(26.0, 0.0, 10.0)
			b.rotation.y = 0.0
			p.equip("p9")
			_stand(Vector3(26.0, 0.0, 6.2), b.global_position)
			_hp0 = b.hp
			_shoot_zone("torso", 3)
			step = 1
		1:
			if not _tick_fire():
				return false
			_check(is_equal_approx(b.hp, _hp0), "three shots into his front hit the shield, not him (hp %.0f -> %.0f)" % [_hp0, b.hp])
			_check(b._shield_hp < b.get_script().SHIELD_HP, "the shield took them (%.0f of %.0f left)" % [b._shield_hp, b.get_script().SHIELD_HP])
			_hp0 = b.hp
			_shoot_zone("leg", 3)
			step = 2
		2:
			if not _tick_fire():
				return false
			_check(b.hp < _hp0, "shots at his legs get under the shield (hp %.0f -> %.0f)" % [_hp0, b.hp])
			# Round the back: the growth.
			_stand(Vector3(26.0, 0.0, 13.6), b.global_position)
			_hp0 = b.hp
			_shoot_zone("wound", 2)
			step = 3
		3:
			if not _tick_fire():
				return false
			var lost: float = _hp0 - b.hp
			_check(lost >= 2 * 26.0 * 2.5, "the growth on his back takes triple damage (lost %.0f from two 26-damage shots)" % lost)
			# Enough on the growth: he drops to his knees.
			b.take_hit(b.get_script().WOUND_KNEEL, "p9", "wound", -b.global_basis.z)
			_check(b._act == "kneel", "enough hits on the growth drop him to his knees (%s)" % b._act)
			_hp0 = b.hp
			b.take_hit(20.0, "p9", "torso", b.global_basis.z)
			_check(absf((_hp0 - b.hp) - 30.0) < 0.5, "on his knees the shield doesn't save him and he takes half again (%.0f)" % (_hp0 - b.hp))
			b.set_physics_process(true)
			_stand(Vector3(26.0, 0.0, 6.0), b.global_position)
			step = 4
			wait_to = frames + 60 * 7
		4:
			if b._act == "kneel":
				_kneel_seen = true
			if frames < wait_to:
				return false
			_check(_kneel_seen and b._act != "kneel", "he gets back up after a few seconds (now '%s')" % b._act)
			# Half his health gone: phase two.
			b.hp = b.max_hp * 0.5 + 1.0
			b.take_hit(10.0, "p9", "leg", b.global_basis.z)
			step = 5
			wait_to = frames + 30
		5:
			if frames < wait_to:
				return false
			_check(b.phase == 2, "at half health he enters phase two")
			_check(b._shield_hp <= 0.0, "he tears the shield off")
			# He goes for her: real hits, no god mode.
			cheats.set_cheat("god_mode", false)
			p.hp = 100.0
			p.aiming = false
			p.fire_held = false
			_stand(b.global_position + Vector3(0, 0, -1.6), b.global_position)
			_hp0 = p.hp
			step = 6
			wait_to = frames + 60 * 14
		6:
			if p.hp < _hp0 or p.downed:
				_check(true, "he hits her when she's in reach (hp %.0f -> %.0f%s)" % [_hp0, p.hp, ", down" if p.downed else ""])
				step = 7
				return false
			if frames < wait_to:
				return false
			_check(false, "he hits her when she's in reach (hp still %.0f after 14 s, his move '%s')" % [p.hp, b._act])
			step = 7
		7:
			cheats.set_cheat("god_mode", true)
			b.take_hit(5000.0, "p9", "torso", -b.global_basis.z)
			step = 8
			wait_to = frames + 60 * 3
		8:
			if frames < wait_to:
				return false
			_check(b.state == load("res://scripts/enemies/zombie.gd").S.DEAD and gs.has_flag("c2_warden_dead"), "he dies (c2_warden_dead)")
			_check(b.collision_layer == 0, "his body stops blocking")
			_check(current_scene.has_node("Pickup_c2_crank"), "the starting handle drops")
			var h: Node3D = current_scene.get_node_or_null("Pickup_c2_crank")
			if h:
				_check(h.global_position.distance_to(b.global_position) < 2.0 and h.global_position.y > -0.1 and h.global_position.y < 0.5, "it lies on the floor where he fell (%s)" % str(h.global_position))
			_check(gs.has_flag("unlocked:muster_door"), "the muster door is unbarred")
			_finish()
	return false

func _finish() -> void:
	print("WARDEN FIGHT OK" if fails.is_empty() else "WARDEN FIGHT FAIL: %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
