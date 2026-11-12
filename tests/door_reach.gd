extends SceneTree
## Doors answer from touching distance out to arm's reach: stands the survivor
## facing each closed door at 0.36 m (pressed against it), 0.8 m and 1.5 m and
## checks the interact prompt names the door. Prints DOOR REACH OK or FAIL.
var frames := 0
var cases := []
var ci := 0
var p: Node = null
var fails := []
var wait := 0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(root.get_node("GameState").level_path)
	var cs = root.get_node_or_null("Cutscenes")
	if frames > 3 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	if frames == 60:
		p = get_first_node_in_group("players")
		for zz in get_nodes_in_group("zombies"):
			zz.queue_free()
		for d in get_nodes_in_group("doors"):
			if d.kind == d.Kind.COOP:
				continue   # two handles at the sides, checked by the co-op tests
			for dist in [0.36, 0.8, 1.5]:
				for side in [1.0, -1.0]:
					cases.append([d, dist, side])
	if frames > 60 and ci < cases.size():
		var c: Array = cases[ci]
		var d: Node = c[0]
		var n: Vector3 = d.global_transform.basis.z * c[2]
		if wait == 0:
			d._set_open(false, Vector3.ZERO, false)
			p.global_position = d.global_position + n * c[1]
			p.velocity = Vector3.ZERO
			p.body.global_rotation.y = atan2(n.x, n.z)   # facing the door
			p.move_input = Vector2.ZERO
		wait += 1
		if wait == 4:
			p.interact_ray.force_raycast_update()
			p._update_focus()
			var text: String = p._prompt_text
			var dd: float = (p.global_position - d.global_position).dot(d.global_transform.basis.z)
			var hit = p.interact_ray.get_collider() if p.interact_ray.is_colliding() else null
			print("  %s at %.2f m (side %+d): \"%s\"  [stood at %.2f, ray hit %s, fwd.n %.2f]" % [d.name, c[1], c[2], text, dd, str(hit.get_parent().name) if hit else "-", (-p.body.global_transform.basis.z).dot(n)])
			if absf(absf(dd) - c[1]) > 0.15:
				print("    (skipped: something on that side pushed her to %.2f m)" % dd)
			elif text == "":
				fails.append("%s at %.2f m" % [d.name, c[1]])
			wait = 0
			ci += 1
	elif frames > 60:
		print("DOOR REACH OK" if fails.is_empty() else "DOOR REACH FAIL: %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
