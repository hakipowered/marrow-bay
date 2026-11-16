extends SceneTree
## Loads a level headless and lists its signs and any floating Label3D left.
##   godot --headless --path . --script tests/sign_check.gd -- [res://scenes/levels/<level>.tscn]
var f := 0
func _process(_d):
	f += 1
	if f == 3:
		var gs = root.get_node("GameState")
		var a := OS.get_cmdline_user_args()
		gs.level_path = a[0] if a.size() > 0 else "res://scenes/levels/undercroft.tscn"
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
	if f == 40:
		var labels := current_scene.find_children("*", "Label3D", true, false)
		print("LABEL3D left: ", labels.size())
		for l in labels:
			print("  ", current_scene.get_path_to(l), " ", (l as Label3D).text.replace("\n", " | "))
		var n := 0
		for mi in current_scene.find_children("*", "MeshInstance3D", true, false):
			var m = (mi as MeshInstance3D).mesh
			if m and m.get_surface_count() > 0 and m.surface_get_material(0) is ShaderMaterial and str((m.surface_get_material(0) as ShaderMaterial).shader.resource_path).contains("sign_"):
				n += 1
		print("SIGNS: ", n)
		quit(0)
