extends SceneTree
## Every door in the level, opened, must let a survivor through: sweeps the
## player's capsule from 1.2 m on one side of each doorway to 1.2 m on the
## other and reports any door whose way is blocked (a wall opening that
## doesn't line up with the door, a prop in the way). Locked and co-op doors
## are opened by force here; the game says why they won't open.
## Prints DOORS OK, or DOORS FAIL with the blocked doors.
var frames := 0

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
		for p in get_nodes_in_group("players"):
			p.global_position += Vector3(0, -50, 0)   # out of the way of the sweeps
	if frames == 64:
		_sweep()
	return false

func _sweep() -> void:
	var fails := []
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	var doors := get_nodes_in_group("doors")
	for d in doors:
		d._set_open(true, Vector3.ZERO, false)
	await physics_frame
	await physics_frame
	for d in doors:
		var n: Vector3 = d.global_transform.basis.z.normalized()
		var from: Vector3 = d.global_position + Vector3.UP * 0.95 + n * 1.2
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.collision_mask = 1
		q.transform = Transform3D(Basis(), from)
		q.motion = -n * 2.4
		var r: PackedFloat32Array = space.cast_motion(q)
		var free_way := r.size() > 0 and r[0] >= 0.999
		print("  %s (kind %d, %.1f m wide): %s" % [d.name, d.kind, d.width, "clear" if free_way else "BLOCKED at %.0f%% of the way" % (r[0] * 100.0)])
		if not free_way:
			fails.append(str(d.name))
	if fails.is_empty():
		print("DOORS OK (%d doors)" % doors.size())
	else:
		print("DOORS FAIL: ", fails)
	quit(0 if fails.is_empty() else 1)
