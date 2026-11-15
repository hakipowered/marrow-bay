extends SceneTree
## What the browser version still draws from a spot: every mesh the camera's
## frustum takes in (after the browser profile's batching), counted by what
## it is (merged batch, instanced batch, or why a piece was left alone) and by
## distance, plus which lights touch it. Helps decide what to batch or cull
## next. Same spots as tests/perf_probe.gd.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 544x453 \
##     --script tests/view_census.gd -- [spots=a+b]
var frames := 0
var spots := [
	["street_start", Vector3(0, 0.15, -24), -PI / 2],
	["great_hall", Vector3(3, 0.15, -1.0), PI * 0.85],
	["reading_room", Vector3(-14, 0.15, 3), PI * 0.25],
	["vault", Vector3(-8, 0.15, 17.5), -PI * 0.65],
]
var player: Node
var idx := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("spots="):
			var keep := a.substr(6).split("+")
			spots = spots.filter(func(s): return s[0] in keep)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("GameState").reset_run()
		root.get_node("GameState").set_flag("story_intro")
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(root.get_node("GameState").level_path)
	if frames == 30:
		player = get_first_node_in_group("players")
		if root.get_node("Cutscenes").active:
			root.get_node("Cutscenes")._on_skip_pressed()
		for z in get_nodes_in_group("zombies"):
			z.set_physics_process(false)
		load("res://scripts/world/web_quality.gd").apply_level(current_scene, true)
	if frames < 32:
		return false
	var k := frames - 32
	if k % 6 == 0:
		if idx >= spots.size():
			quit(0)
			return false
		var s: Array = spots[idx]
		player.global_position = s[1]
		player.velocity = Vector3.ZERO
		player.yaw = s[2]
		player.pitch = -0.08
		player.body.rotation.y = s[2]
	elif k % 6 == 5:
		_census(spots[idx][0])
		idx += 1
	return false

func _census(spot: String) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var planes := cam.get_frustum()
	var at := cam.global_position
	var cats := {}
	var dist := {"<8": 0, "8-15": 0, "15-25": 0, ">25": 0}
	var lights := []
	for l in current_scene.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or not l.is_visible_in_tree() or l.light_energy <= 0.0:
			continue
		var r: float = l.omni_range if l is OmniLight3D else l.spot_range
		lights.append([l, AABB(l.global_position - Vector3.ONE * r, Vector3.ONE * r * 2.0)])
	var total := 0
	var shadow_touch := 0
	for g in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree() or (gi.layers & cam.cull_mask) == 0:
			continue
		var box: AABB = gi.global_transform * gi.get_aabb()
		if not _in_frustum(box, planes):
			continue
		var surf := 1
		if gi is MeshInstance3D and gi.mesh:
			surf = gi.mesh.get_surface_count()
		elif gi is MultiMeshInstance3D and gi.multimesh and gi.multimesh.mesh:
			surf = gi.multimesh.mesh.get_surface_count()
		var cat := _category(gi)
		cats[cat] = cats.get(cat, 0) + surf
		total += surf
		var d := box.get_center().distance_to(at) - box.size.length() * 0.5
		var b := "<8" if d < 8 else ("8-15" if d < 15 else ("15-25" if d < 25 else ">25"))
		dist[b] += surf
		for lb in lights:
			if lb[0].shadow_enabled and (lb[1] as AABB).intersects(box) and (lb[0].light_cull_mask & gi.layers):
				shadow_touch += surf
	var rows := []
	for c in cats:
		rows.append([cats[c], c])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("VIEW %s surfaces_in_frustum=%d by_distance=%s shadow_light_touches=%d" % [spot, total, dist, shadow_touch])
	for r in rows.slice(0, 18):
		print("VIEW   %5d  %s" % [r[0], r[1]])

func _in_frustum(box: AABB, planes: Array) -> bool:
	for p in planes:
		var pl := p as Plane
		# The planes face out: the box is outside when even its corner
		# farthest inside is in front of one of them.
		var v := box.position
		if pl.normal.x < 0: v.x += box.size.x
		if pl.normal.y < 0: v.y += box.size.y
		if pl.normal.z < 0: v.z += box.size.z
		if pl.distance_to(v) > 0.0:
			return false
	return true

func _category(gi: GeometryInstance3D) -> String:
	var p := gi.get_parent()
	if p and p.name == "StaticBatches":
		return "batch: instanced" if gi is MultiMeshInstance3D else "batch: merged"
	if gi is GPUParticles3D or gi is CPUParticles3D:
		return "particles"
	if gi is MeshInstance3D and (gi as MeshInstance3D).skin:
		return "skinned"
	var n: Node = gi
	while n and n != current_scene:
		if n.get_script():
			return "under script " + str(n.get_script().resource_path).get_file()
		if not n.get_groups().is_empty():
			return "in group " + str(n.get_groups()[0])
		n = n.get_parent()
	var box: AABB = gi.global_transform * gi.get_aabb()
	if box.size.x > 4.0 or box.size.y > 4.0 or box.size.z > 4.0:
		return "big piece (>4 m)"
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		var mat: Material = mi.get_active_material(0)
		if mat is ShaderMaterial:
			return "shader " + str((mat as ShaderMaterial).shader.resource_path).get_file()
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return "see-through"
		if mi.mesh is ArrayMesh:
			var d := RenderingServer.mesh_get_surface(mi.mesh.get_rid(), 0)
			var l = d.get("lods", [])
			if l is Array and l.size() > 0:
				return "one-off scan with LODs"
	return "other " + gi.get_class()
