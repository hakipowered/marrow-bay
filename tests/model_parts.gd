extends SceneTree
## Lists the top-level parts of kit models (models that hold several pieces).
func _initialize() -> void:
	for n in OS.get_cmdline_user_args():
		var node: Node3D = (load("res://assets/polyhaven/models/%s/%s.gltf" % [n, n]) as PackedScene).instantiate()
		root.add_child(node)
		print("== ", n)
		_walk(node, Transform3D.IDENTITY, 0)
		node.queue_free()
	quit(0)

func _walk(n: Node, xf: Transform3D, depth: int) -> void:
	for c in n.get_children():
		if c is Node3D:
			var cx: Transform3D = xf * c.transform
			var a: AABB = RoomBuilder._aabb(c, cx) if c.get_child_count() > 0 else (cx * c.mesh.get_aabb() if c is MeshInstance3D and c.mesh else AABB())
			if c is MeshInstance3D and c.mesh and c.get_child_count() == 0:
				a = cx * c.mesh.get_aabb()
			print("  ".repeat(depth + 1), c.name, "  size=", a.size.snapped(Vector3.ONE * 0.01), " at=", a.get_center().snapped(Vector3.ONE * 0.01))
			if depth < 1:
				_walk(c, cx, depth + 1)
