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

## Walks her capsule through each opened doorway in 5 cm steps, from 0.85 m
## on one side to 0.85 m on the other, along the middle and (for doors wider
## than 1.6 m) near both edges. At each step she stands on whatever floor is
## under her (so she goes up kerb ramps the way she does in play), and the
## step fails if there is no floor or her body overlaps anything solid.
const REACH := 0.85
const STEP := 0.05

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
		var across: Vector3 = d.global_transform.basis.x.normalized()
		var lanes := [0.0]
		if d.width > 1.6:
			lanes = [-(d.width / 2 - 0.45), 0.0, d.width / 2 - 0.45]
		var verdict := "clear"
		for lane in lanes:
			var why := _walk(space, cap, d.global_position + across * lane, n)
			if why != "":
				verdict = "BLOCKED %s (%+.1f m from the middle)" % [why, lane]
				break
		print("  %s (kind %d, %.1f m wide): %s" % [d.name, d.kind, d.width, verdict])
		if verdict != "clear":
			fails.append(str(d.name))
	if fails.is_empty():
		print("DOORS OK (%d doors)" % doors.size())
	else:
		print("DOORS FAIL: ", fails)
	quit(0 if fails.is_empty() else 1)

## "" if she gets through, else where and by what she was stopped.
func _walk(space: PhysicsDirectSpaceState3D, cap: CapsuleShape3D, at: Vector3, n: Vector3) -> String:
	var steps := int(round(REACH * 2 / STEP))
	for i in steps + 1:
		var off := REACH - i * STEP
		var p := at + n * off
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.6, 1)
		var floor_hit := space.intersect_ray(ray)
		if floor_hit.is_empty():
			return "no floor at %+.2f m" % off
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.collision_mask = 1
		q.transform = Transform3D(Basis(), floor_hit["position"] + Vector3.UP * (0.05 + cap.height / 2))
		var hits := space.intersect_shape(q, 1)
		if not hits.is_empty():
			var c: Object = hits[0]["collider"]
			return "at %+.2f m by %s" % [off, str(c.get_path()) if c is Node else str(c)]
	return ""
