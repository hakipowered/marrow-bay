extends SceneTree
## The infected come through a doorway after her. In 0.13 two stood in the
## Great Hall's doorway while Bulmaim was out in the courtyard and didn't
## come for her: the door had been opened after the level loaded, and the
## navmesh still had it shut. Checks that:
##  1. Sight: idle infected inside the hall, facing the open door, notice her
##     out in the courtyard 11 m away (further than they'd hear her).
##  2. They come out through the doorway and reach her.
##  3. One facing away from her at that range doesn't notice her.
## Prints DOORWAY CHASE OK, or DOORWAY CHASE FAIL with the reasons.
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var fails := []
var notes := []
var a: Node = null
var b: Node = null
var c: Node = null
var _seen_t := -1.0

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and stage < 30 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				var lvl = get_first_node_in_group("level")
				for z in get_nodes_in_group("zombies"):
					z.queue_free()
				p = get_first_node_in_group("players")
				p.global_position = Vector3(1.8, 0.1, -8.2)   # (clear of the courtyard statue)
				var door = lvl.get_node("Door_hall_main")
				door._rpc_set_open(true, Vector3(0, 0, 1))
				# Two inside the hall looking out through the doorway, one
				# beside them with its back to it.
				lvl.spawn_zombie_synced("TestHallA", Vector3(-0.8, 0, 2.2), "shambler")
				lvl.spawn_zombie_synced("TestHallB", Vector3(0.4, 0, 2.6), "shambler")
				lvl.spawn_zombie_synced("TestHallC", Vector3(3.5, 0, 2.4), "shambler")
				a = lvl.get_node("TestHallA")
				b = lvl.get_node("TestHallB")
				c = lvl.get_node("TestHallC")
				for z in [a, b, c]:
					z.state = z.S.IDLE
				a.rotation.y = 0.0
				b.rotation.y = 0.15
				c.rotation.y = PI
				stage = 2
				t = 0.0
		2:
			t += d
			p.hp = 100.0
			p.move_input = Vector2.ZERO
			var d_a: float = a.global_position.distance_to(p.global_position)
			var d_c: float = c.global_position.distance_to(p.global_position)
			if notes.is_empty():
				notes.append("start: %.1f m from her (hearing reaches 9 m), the one facing away %.1f m" % [d_a, d_c])
			if _seen_t < 0.0 and a.state == a.S.CHASE and b.state == b.S.CHASE:
				_seen_t = t
				notes.append("both facing the door noticed her after %.2f s; the one facing away: state %d" % [t, c.state])
				if c.state != c.S.IDLE and c.state != c.S.WANDER:
					fails.append("the one with its back to her noticed her at %.1f m" % d_c)
			if t > 2.0 and _seen_t < 0.0:
				var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a.global_position + Vector3.UP * 1.5, p.global_position + Vector3.UP * 1.3, 1)
				q.exclude = [a.get_rid()]
				var hit: Dictionary = a.get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty():
					notes.append("A's view blocked by %s at %s" % [str(hit.collider.get_path()), str(hit.position.snapped(Vector3.ONE * 0.1))])
				fails.append("she stood in plain sight %.1f m away and they never noticed (states %d %d)" % [d_a, a.state, b.state])
				stage = 30
			# Both out of the hall (past the door at z = -2) and on her.
			if _seen_t >= 0.0 and a.global_position.z < -3.0 and b.global_position.z < -3.0 and d_a < 2.0:
				notes.append("both came out through the doorway and reached her after %.1f s" % t)
				stage = 30
			elif t > 14.0:
				for z in [a, b]:
					notes.append("%s path %s target %s finished %s reachable %s vel %s" % [z.name, str(Array(z.agent.get_current_navigation_path()).map(func(v): return v.snapped(Vector3.ONE * 0.1))), str(z.agent.target_position.snapped(Vector3.ONE * 0.1)), str(z.agent.is_navigation_finished()), str(z.agent.is_target_reachable()), str(z.velocity.snapped(Vector3.ONE * 0.1))])
				fails.append("they never came out to her: A at %s (state %d), B at %s (state %d)" % [str(a.global_position.snapped(Vector3.ONE * 0.1)), a.state, str(b.global_position.snapped(Vector3.ONE * 0.1)), b.state])
				stage = 30
		30:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("DOORWAY CHASE OK")
			else:
				print("DOORWAY CHASE FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false
