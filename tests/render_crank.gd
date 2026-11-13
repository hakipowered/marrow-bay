extends SceneTree
## Renders a survivor cranking the Undercroft generator at moments through
## one heave, for a look at the hands on the grip.
##   godot --path . --rendering-driver opengl3 --script tests/render_crank.gd -- <zegan|obcera> <out_dir> [view: side|front|back]
var f := 0
var cm: CharacterModel
var gen: Node3D
var cam: Camera3D
var times := [0.1, 0.5, 0.8, 1.1, 1.5, 1.9, 2.3]
var k := 0
var who := "zegan"
var out := "/tmp"
var view := "side"

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		who = a[0]
		out = a[1]
		view = a[2] if a.size() > 2 else "side"
		var world := Node3D.new()
		root.add_child(world)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.25, 0.27, 0.3)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
		world.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -40, 0)
		world.add_child(sun)
		gen = load("res://scripts/world/generator_set.gd").new()
		world.add_child(gen)
		gen.set_process(false)
		cm = CharacterModel.new()
		cm.character = who
		world.add_child(cm)
		cm.position = gen.SPOT
		cm.rotation.y = atan2(-1.0, 0.0)
		cam = Camera3D.new()
		world.add_child(cam)
		cam.fov = 45
		var focus := Vector3(-1.8, 0.9, 0)
		match view:
			"side": cam.position = focus + Vector3(0.2, 0.4, 3.2)
			"front": cam.position = focus + Vector3(1.6, 0.9, 2.2)
			"back": cam.position = focus + Vector3(-2.6, 1.0, 1.4)
		cam.look_at(focus)
		cam.make_current()
	if f == 6:
		gen._crank.visible = true
		cm.play("crank", false)
		cm.hands_on(gen._grip_l, gen._grip_r)
	if f > 40 and k < times.size():
		var ph := (f - 41) % 5
		if ph == 0:
			cm._anim.seek(times[k], true)
			cm._anim.pause()
			gen._crank.rotation.x = -gen._heave_angle(times[k])
		elif ph == 4:
			root.get_texture().get_image().save_png("%s/%s_%s_%d.png" % [out, who, view, k])
			k += 1
	if k >= times.size():
		quit(0)
	return false
