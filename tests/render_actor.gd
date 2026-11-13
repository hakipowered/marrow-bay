extends SceneTree
## Renders a story actor (or any character GLB) for a look.
##   godot --path . --rendering-driver opengl3 --script tests/render_actor.gd -- <id> <out.png> [clip] [time] [yaw_deg] [dist]
## <id> is a folder under assets/characters (hardass, tallyman, hardass_riot, ...).
var f := 0
var actor: Node3D
func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	f += 1
	var a := OS.get_cmdline_user_args()
	if f == 2:
		actor = StoryActor.new(a[0])
		root.add_child(actor)
		var yaw := float(a[4]) if a.size() > 4 else 0.0
		actor.rotation_degrees.y = yaw
		var cam := Camera3D.new()
		root.add_child(cam)
		var dist := float(a[5]) if a.size() > 5 else 3.6
		cam.position = Vector3(0, 1.05, -dist)
		cam.look_at(Vector3(0, 0.95, 0))
		cam.fov = 45
		cam.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 160, 0)
		sun.light_energy = 1.4
		root.add_child(sun)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.32, 0.34, 0.38)
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
		root.add_child(we)
	if f == 4 and a.size() > 2 and a[2] != "-":
		actor.play(a[2], 0.0)
		var anim: AnimationPlayer = actor.get("_anim")
		if anim and a.size() > 3:
			anim.seek(float(a[3]), true)
	if f == 14:
		root.get_texture().get_image().save_png(a[1])
		quit(0)
	return false
