extends SceneTree
## Counts the level's mesh instances: how many, how many could be merged
## (static, no script anywhere above them), and how many distinct materials.
var frames := 0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("GameState").reset_run()
		root.get_node("GameState").set_flag("story_intro")
		root.get_node("Net").start_solo("obcera")
		var a := OS.get_cmdline_user_args()
		change_scene_to_file(a[0] if a.size() > 0 else root.get_node("GameState").level_path)
	if frames == 40 and OS.get_cmdline_user_args().has("web"):
		load("res://scripts/world/web_quality.gd").apply_level(current_scene, true)
	if frames == 45:
		var lvl := current_scene
		var all := lvl.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.layers != 0)
		var static_ok := 0
		var mats := {}
		var by_parent_script := {}
		var reasons := {}
		for mi in all:
			var why := _blocker(mi, lvl)
			if why == "":
				static_ok += 1
				var m: Material = mi.material_override
				if m == null and mi.mesh and mi.mesh.get_surface_count() > 0:
					m = mi.get_active_material(0)
				mats[m] = mats.get(m, 0) + 1
			else:
				reasons[why] = reasons.get(why, 0) + 1
		print("CENSUS meshes=%d mergeable=%d materials=%d" % [all.size(), static_ok, mats.size()])
		var r := reasons.keys()
		r.sort_custom(func(x, y): return reasons[x] > reasons[y])
		for k in r.slice(0, 25):
			print("  blocked by ", k, ": ", reasons[k])
		var top := mats.keys()
		top.sort_custom(func(x, y): return mats[x] > mats[y])
		for m in top.slice(0, 15):
			print("  mat ", m.resource_path if m else "null", " ", m.get_class() if m else "", ": ", mats[m])
		var lights := lvl.find_children("*", "Light3D", true, false)
		var flick := 0
		for l in lights:
			if l.get_script():
				flick += 1
		print("CENSUS lights=%d scripted=%d decals=%d particles=%d probes=%d" % [lights.size(), flick,
			lvl.find_children("*", "Decal", true, false).size(),
			lvl.find_children("*", "GPUParticles3D", true, false).size(),
			lvl.find_children("*", "ReflectionProbe", true, false).size()])
		quit(0)
	return false

## Why this mesh can't be merged into a static batch ("" if it can).
func _blocker(mi: MeshInstance3D, lvl: Node) -> String:
	if mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
		return "skinned"
	var n: Node = mi
	while n and n != lvl:
		if n.get_script():
			return "script:" + str(n.get_script().resource_path).get_file()
		if n is AnimationPlayer or n is Skeleton3D:
			return "animated"
		n = n.get_parent()
	return ""
