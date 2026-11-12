extends SceneTree
## Renders the title screen a few times (video, rain overlay, lightning).
## xvfb-run godot --path . --rendering-driver vulkan --resolution 1600x1332 --script tests/render_menu.gd -- <out_dir>
var out := "/tmp"
var frames := 0
var t := 0.0
var shots := [1.5, 4.0]
var shot := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		change_scene_to_file("res://scenes/main_menu.tscn")
	if frames < 5:
		return false
	t += delta
	if shot == 1 and current_scene and t > shots[1] - 0.05:
		current_scene.set("_flash", 0.8)
	if shot < shots.size() and t >= shots[shot]:
		root.get_texture().get_image().save_png("%s/menu_%d.png" % [out, shot])
		print("saved menu_", shot)
		shot += 1
	if shot >= shots.size():
		quit(0)
	return false
