extends SceneTree
## Zegan and Obcera side by side in their standing loops, pistol lowered,
## at four moments, so their idles can be compared (they used to share one
## clip and stood in lockstep when a cutscene handed control back).
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1400x800 --script tests/render_idles.gd -- <out_dir> [weapon] [obcera_outfit]
var out := "/tmp/render_idles"
var weapon := "p9"
var outfit := "default"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		weapon = a[1]
	if a.size() > 2:
		outfit = a[2]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.3, 0.33)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, PI + 0.4, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.fov = 32
	var models: Array[CharacterModel] = []
	var x := 0.0
	for who in ["zegan", "obcera"]:
		var m := CharacterModel.new()
		m.character = who
		m.customization = {"outfit": outfit if who == "obcera" else "default"}
		root.add_child(m)
		m.position = Vector3(x, 0, 0)
		x += 1.1
		# Loaded at run time: HeldWeapon uses autoloads (Effects) that a
		# --script main loop can't see while it compiles.
		var h: Node3D = load("res://scripts/player/held_weapon.gd").new()
		h.set("model", m)
		root.add_child(h)
		h.call("set_weapon", weapon)
		m.hold = h.get("hold")
		models.append(m)
	await _frames(3)
	for m in models:
		m.play("idle", false)
	cam.position = Vector3(0.55, 1.05, -4.6)
	cam.look_at(Vector3(0.55, 0.95, 0))
	for k in 4:
		for m in models:
			m._anim.seek(m._anim.current_animation_length * (k / 4.0 + 0.05), true)
		await _frames(4)
		root.get_viewport().get_texture().get_image().save_jpg("%s/idles_%s_%s_%d.jpg" % [out, weapon, outfit, k], 0.85)
	print("playing: ", [models[0]._anim.current_animation, models[1]._anim.current_animation])
	print("IDLES DONE")
	quit(0)
