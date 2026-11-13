class_name UndercroftKit
extends RefCounted
## Small building helpers for chapter 2 (the Undercroft): the Meshy set
## pieces in assets/props (generator, lockers, fuse, crank, clock key), turned
## pipe and bar shapes, painted lettering and the reach areas players use.

## A Meshy prop from res://assets/props/<id>/<id>.glb, sized so its longest
## side along the ground is `length` metres, standing on the floor at `pos`
## (its middle over that point). Returns the holder; the model is its child.
static func meshy(parent: Node3D, id: String, pos: Vector3, rot_deg := 0.0, length := 1.0, collide := true) -> Node3D:
	var holder := Node3D.new()
	holder.name = id.capitalize().replace(" ", "")
	holder.position = pos
	holder.rotation_degrees.y = rot_deg
	parent.add_child(holder)
	var path := "res://assets/props/%s/%s.glb" % [id, id]
	if not ResourceLoader.exists(path):
		push_warning("UndercroftKit: no model " + path)
		return holder
	var m: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(m)
	var box := bounds(m)
	var s := length / maxf(maxf(box.size.x, box.size.z), 0.001)
	m.scale = Vector3.ONE * s
	box = bounds(m)
	m.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	holder.set_meta("size", box.size)
	holder.set_meta("scale", s)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size
		cs.shape = bs
		cs.position = Vector3(0, box.size.y / 2, 0)
		sb.add_child(cs)
		holder.add_child(sb)
	return holder

## Bounds of every mesh under n, in n's parent space.
static func bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		# Transform up to n's parent, without needing the tree.
		var xf := Transform3D.IDENTITY
		var up: Node = mi
		while up != null and up != n.get_parent():
			if up is Node3D:
				xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

## A turned bar: a cylinder of `radius` and `length` along `axis` ("x", "y", "z").
static func bar(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material, axis := "y", sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position = at
	match axis:
		"x": mi.rotation.z = PI / 2
		"z": mi.rotation.x = PI / 2
	parent.add_child(mi)
	return mi

## Painted or stencilled lettering facing local +z.
static func label(parent: Node3D, text: String, at: Vector3, size: int, color: Color, rot_y := 0.0, pixel := 0.0011) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 0
	l.pixel_size = pixel
	l.modulate = color
	l.shaded = true
	l.double_sided = false
	l.position = at
	l.rotation.y = rot_y
	parent.add_child(l)
	return l

## What a survivor's reach finds (layer 16, like doors): routes to
## target.interact_text(player, handle) / target.interact(player, handle).
static func reach(parent: Node3D, target: Node, at: Vector3, size: Vector3, handle := -1) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	a.add_child(cs)
	a.position = at
	a.set_script(preload("res://scripts/world/interact_proxy.gd"))
	a.target = target
	a.set_meta("handle", handle)
	parent.add_child(a)
	return a

## Whether no player can see `pos` (a point a metre up from it): the way
## infected are brought in, never out of thin air in view.
static func out_of_sight(tree: SceneTree, pos: Vector3) -> bool:
	var world := (tree.current_scene as Node3D).get_world_3d() if tree.current_scene is Node3D else null
	if world == null:
		return true
	var space := world.direct_space_state
	var excl: Array = []
	for p in tree.get_nodes_in_group("players"):
		excl.append(p.get_rid())
	for p in tree.get_nodes_in_group("players"):
		# Her eyes, and the camera over her shoulder (what the phone shows).
		var eyes: Array = [p.global_position + Vector3.UP * 1.6, p.global_position + Vector3.UP * 2.2]
		var cam = p.get("camera")
		if cam is Camera3D and cam.is_inside_tree():
			eyes.append(cam.global_position)
		for eye in eyes:
			for up in [0.3, 1.2]:
				var pt: Vector3 = pos + Vector3.UP * up
				if eye.distance_to(pt) > 45.0:
					continue
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, pt, 1, excl)).is_empty():
					return false
	return true
