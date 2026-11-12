extends SceneTree
## Screenshot of the outfit and body screen as it looks on the phone.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 2176x1812 \
##   --script tests/render_customize.gd -- <character> <outfit> <out.png> [turn_degrees] [full|upper|face] [idle|walk|run]
var f := 0
var menu: Node

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(menu)
	if f == 5:
		menu._char = a[0]
		menu._custom = root.get_node("GameState").look(a[0])
		menu._custom["outfit"] = a[1]
		menu._customize("solo")
		var screen = menu.get_children().back()
		screen.spin = false
		if a.size() > 3:
			screen._yaw = PI + deg_to_rad(float(a[3]))
		if a.size() > 4:
			screen._set_view(a[4])
			screen._zoom = screen._zoom_target
		if a.size() > 5:
			screen._set_pose(a[5])
	if f == 90:
		root.get_texture().get_image().save_png(a[2])
		quit(0)
	return false
