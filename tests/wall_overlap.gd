extends SceneTree
## Finds walls, floors and trims of neighbouring rooms that sit in the same
## plane and overlap: the renderer can't tell which one is in front, so the
## two textures flicker through each other in triangles (z-fighting), which
## is how the west corridor's green wall kept showing the reading room's
## orange plaster through it. Checks every box RoomBuilder made, and prints
## WALLS OK, or WALLS FAIL with each overlapping pair.
## Another level: `-- res://scenes/levels/undercroft.tscn`.
var frames := 0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var gs = root.get_node("GameState")
		var a := OS.get_cmdline_user_args()
		if a.size() > 0:
			gs.level_path = a[0]
			gs.shared_checkpoint = "ch2_lift" if a[0].ends_with("undercroft.tscn") else "start"
			gs.set_flag("story_c2_arrival")
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
	if frames == 30:
		_check()
	return false

func _check() -> void:
	var level := get_first_node_in_group("level")
	var boxes := []
	for room in level.get_children():
		if not (room is Node3D):
			continue
		for n in room.get_children():
			if n is MeshInstance3D and n.mesh is BoxMesh:
				var size: Vector3 = (n.mesh as BoxMesh).size
				var c: Vector3 = n.global_position
				# Rotated boxes (planks, props) aren't level geometry.
				if not n.global_basis.is_equal_approx(Basis()):
					continue
				boxes.append({"room": str(room.name), "lo": c - size / 2, "hi": c + size / 2, "mat": n.material_override})
	var fails := []
	for i in boxes.size():
		var a: Dictionary = boxes[i]
		for j in range(i + 1, boxes.size()):
			var b: Dictionary = boxes[j]
			if a["room"] == b["room"]:
				continue   # a room's own pieces only touch edge to edge
			var area := _shared_face(a, b)
			# Slivers under 0.05 m² are end caps buried inside a wall.
			if area > 0.05:
				fails.append("%s / %s: %.2f m² of the same face at %s" % [a["room"], b["room"], area, str((a["lo"] + a["hi"]) / 2).replace(" ", "")])
	if boxes.size() < 100:
		fails.append("only %d boxes found: the level didn't build" % boxes.size())
	for f in fails:
		print("  ", f)
	print("WALLS OK (%d boxes)" % boxes.size() if fails.is_empty() else "WALLS FAIL (%d overlaps)" % fails.size())
	quit(0 if fails.is_empty() else 1)

## Area where a face of one box lies in the same plane as a face of the other,
## facing the same way, and both are actually there (they overlap).
func _shared_face(a: Dictionary, b: Dictionary) -> float:
	var best := 0.0
	for k in 3:
		# Tops and bottoms only matter for floors and ceilings: a wall's
		# underside sits on the floor and its top hides above the ceiling.
		if k == 1 and (a["hi"].y - a["lo"].y > 0.3 or b["hi"].y - b["lo"].y > 0.3):
			continue
		var u := (k + 1) % 3
		var v := (k + 2) % 3
		var ou := minf(a["hi"][u], b["hi"][u]) - maxf(a["lo"][u], b["lo"][u])
		var ov := minf(a["hi"][v], b["hi"][v]) - maxf(a["lo"][v], b["lo"][v])
		if ou <= 0.001 or ov <= 0.001:
			continue
		for side in ["lo", "hi"]:
			if absf(a[side][k] - b[side][k]) < 0.002:
				best = maxf(best, ou * ov)
	return best
