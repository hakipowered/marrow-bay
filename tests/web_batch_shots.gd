extends SceneTree
## Checks that the browser version's static batching (scripts/world/
## static_batch.gd) doesn't change the picture: renders the same views of a
## level before and after merging, saves both, and prints how far apart they
## are (mean difference per pixel, 0..255, and the share of pixels that moved
## by more than 24). Rain and flickering lights are stilled so only the
## batching shows (BATCH_LIGHTS_CHANGED says when a light still moved). Each
## view is also shot a second time before batching (CONTROL_DIFF): that's how
## far two renders of the same scene drift on their own.
##
## Known (Undercroft "corridor_w"): before batching, the safe room's desk lamp
## leaks a glow into the corridor through a hairline crack in its shadow
## round the closed lodge door; the batched walls close the crack. With the
## door open both light the corridor the same.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x800 \
##     --script tests/web_batch_shots.gd -- <out_dir> [level res path]
var frames := 0
var out := "/tmp/batch_shots"
var level := ""
var shots := {
	"res://scenes/levels/archive_hub.tscn": [
		["street", Vector3(-4, 1.7, -20), Vector3(14, 1.2, -27)],
		["street_signs", Vector3(-10, 1.7, -22), Vector3(-4, 2.8, -29.5)],
		["street_east", Vector3(-14, 1.8, -24), Vector3(15, 2.0, -20)],
		["diner", Vector3(5.0, 1.6, -27.5), Vector3(7.0, 1.0, -33.5)],
		["courtyard", Vector3(0, 1.7, -12.5), Vector3(0, 1.5, -2)],
		["great_hall", Vector3(3, 1.8, -1.0), Vector3(-4, 2.2, 12)],
		["great_hall_north", Vector3(2, 1.8, 13), Vector3(-2, 4.0, -2)],
		["reading_room", Vector3(-14, 1.7, 3), Vector3(-22, 1.2, -5)],
		["safe_room", Vector3(13, 1.7, 2.6), Vector3(18, 0.9, 1)],
		["vault", Vector3(-8, 1.7, 17.5), Vector3(0, 1.0, 24)],
	],
	"res://scenes/levels/undercroft.tscn": [
		["lift", Vector3(5.8, 1.7, 4.8), Vector3(0.5, 1.4, 2.6)],
		["corridor_w", Vector3(8.0, 1.7, 3.0), Vector3(30.0, 1.4, 3.0)],
		["lodge", Vector3(13.8, 1.7, 9.8), Vector3(9.0, 1.0, 6.5)],
		["survey", Vector3(19.5, 1.8, -0.2), Vector3(12.0, 1.6, -8.5)],
		["gallery", Vector3(33.5, 1.8, -0.5), Vector3(25.0, 2.2, -9.0)],
		["muster", Vector3(26.1, 1.8, 5.4), Vector3(26.0, 1.0, 13.5)],
	],
}
var cam: Camera3D
var list: Array = []
var idx := 0
var phase := 0   # 0 = before batching, 1 = the same again (control), 2 = after
var before := {}
var t := 0
## Every light as it was when the scene was stilled: [light, energy, visible].
## Some lights are driven by other scripts (the battery lamps' slow failing),
## so they're put back before every shot.
var _held: Array = []

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	level = a[1] if a.size() > 1 else "res://scenes/levels/archive_hub.tscn"
	list = shots.get(level, [])
	DirAccess.make_dir_recursive_absolute(out)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("GameState").reset_run()
		root.get_node("GameState").set_flag("story_intro")
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(level)
	if frames == 40:
		if root.get_node("Cutscenes").active:
			root.get_node("Cutscenes")._on_skip_pressed()
		for z in get_nodes_in_group("zombies"):
			z.process_mode = Node.PROCESS_MODE_DISABLED
		for p in current_scene.find_children("*", "GPUParticles3D", true, false):
			p.visible = false
		# The horror director's scares black out and flicker nearby lights.
		var hd := current_scene.get_node_or_null("HorrorDirector")
		if hd:
			hd.process_mode = Node.PROCESS_MODE_DISABLED
		for l in current_scene.find_children("*", "Light3D", true, false):
			l.set_process(false)
			_held.append([l, l.light_energy, l.visible])
		for h in get_nodes_in_group("hud"):
			h.visible = false
		for n in root.find_children("*", "CanvasLayer", true, false):
			n.visible = false
		cam = Camera3D.new()
		cam.fov = 70
		current_scene.add_child(cam)
		cam.make_current()
		t = frames
	if frames < 41 or list.is_empty():
		if frames > 41:
			quit(0)
		return false
	# One shot every 12 frames (time for shaders to compile on first sight).
	var k := frames - t
	for h in _held:
		if is_instance_valid(h[0]):
			h[0].light_energy = h[1]
			h[0].visible = h[2]
	if k % 12 == 1:
		var s: Array = list[idx]
		cam.global_position = s[1]
		cam.look_at(s[2])
	elif k % 12 == 0:
		var s: Array = list[idx]
		var img := root.get_texture().get_image()
		var tag: String = ["before", "again", "after"][phase]
		img.save_png("%s/%s_%s.png" % [out, s[0], tag])
		var lit := _lights_near(cam.global_position)
		if phase == 0:
			before[s[0]] = img
			before[s[0] + ":lights"] = lit
		else:
			var d := _diff(before[s[0]], img)
			# "again" is the same view re-rendered without batching: how much
			# the renderer itself moves between two visits (shadow atlas
			# slots handed out in a different order, and so on). Only what
			# "after" adds on top of that is the batching's doing.
			print("%s %s mean=%.2f moved=%.2f%%" % ["CONTROL_DIFF" if phase == 1 else "BATCH_DIFF", s[0], d[0], d[1] * 100.0])
			if lit != before[s[0] + ":lights"]:
				# Not the batching: a light changed between the two shots.
				print("BATCH_LIGHTS_CHANGED %s\n  before %s\n  now    %s" % [s[0], before[s[0] + ":lights"], lit])
		idx += 1
		if idx >= list.size():
			idx = 0
			phase += 1
			if phase == 2:
				print("BATCH ", preload("res://scripts/world/static_batch.gd").run(current_scene))
			elif phase == 3:
				quit(0)
	return false

## The lights within 12 m of the camera, as text (on/off, energy, shadow).
func _lights_near(at: Vector3) -> String:
	var parts := PackedStringArray()
	for l in current_scene.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or l.global_position.distance_to(at) > 12.0:
			continue
		parts.append("%s:%s:%.2f:%s" % [l.name, "on" if l.is_visible_in_tree() else "off", l.light_energy, "sh" if l.shadow_enabled else "-"])
	return " ".join(parts)

func _diff(a: Image, b: Image) -> Array:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var tot := 0.0
	var moved := 0
	var n := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var dd := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			tot += dd
			if dd > 24.0:
				moved += 1
			n += 1
	return [tot / n, float(moved) / n]
