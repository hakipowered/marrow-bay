extends SceneTree
## Prints the bounding box size of every fetched Poly Haven model (metres).
func _initialize() -> void:
	var dir := DirAccess.open("res://assets/polyhaven/models")
	var names := dir.get_directories()
	for n in names:
		var p := "res://assets/polyhaven/models/%s/%s.gltf" % [n, n]
		if not ResourceLoader.exists(p):
			continue
		var node: Node3D = (load(p) as PackedScene).instantiate()
		root.add_child(node)
		var a: AABB = RoomBuilder._aabb(node, Transform3D.IDENTITY)
		print("%-34s size=(%.2f, %.2f, %.2f) min_y=%.2f center=(%.2f, %.2f)" % [n, a.size.x, a.size.y, a.size.z, a.position.y, a.get_center().x, a.get_center().z])
		node.queue_free()
	quit(0)
