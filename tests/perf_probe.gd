extends SceneTree
## Frame cost probe for the Compatibility (WebGL 2) renderer the browser
## version uses. Loads chapter 1 solo, puts the survivor at a few spots with
## her own camera, and prints per spot (and per variant): wall-clock frame
## time, physics time, draw calls, objects, primitives, and how many lights /
## shadowed lights are on. Under --headless it measures the CPU side only
## (scripts, animation, physics: "process_ms").
##
##   xvfb-run -a -s "-screen 0 1100x920x24" godot --path . \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --resolution 1088x906 --script tests/perf_probe.gd -- [opts]
##
## opts (comma list):
##   variants=a+b+c   measure each spot once per variant (a&b: both at once):
##                    base, noshadow
##                    (lamp/window shadows off), nosun (moon shadow off),
##                    noglow, nopost (screen grade off), norain, half (3D at
##                    half scale), msaa0, noanim (animation players paused),
##                    nozombie (the infected switched off), nohud (UI not
##                    processed), near15 / near25 (geometry beyond 15 / 25 m
##                    hidden: what distance culling would save), b0..b4 / b6
##                    (the browser's shadow budget at that many lights; it
##                    starts at SHADOW_START), web (the
##                    browser profile, WebQuality; keep it last, it changes
##                    global shadow settings)
##   web              apply the browser profile from the start
##   live             leave the infected awake (chasing, attacking; she has
##                    god mode) instead of frozen in place
##   spots=a+b        only these spots
##   cell=<m>         the browser batching's chunk size (static_batch.gd CELL)
##   shots=<dir>      save the last frame of each spot / variant as a PNG
##   lightlist        print the shadow budget's lights near each spot (their
##                    importance, whether the shadow is on)
##   frames=<n>, warm=<n>
var frames := 0
var stage := 0
var opts := {}
var spots := [
	# name, player position, yaw (radians; 0 looks down -Z)
	["street_start", Vector3(0, 0.15, -24), -PI / 2],
	["street_west", Vector3(8, 0.15, -22), PI / 2],
	["courtyard", Vector3(0, 0.15, -12.5), PI],
	["great_hall", Vector3(3, 0.15, -1.0), PI * 0.85],
	["reading_room", Vector3(-14, 0.15, 3), PI * 0.25],
	["safe_room", Vector3(13, 0.15, 2.6), -PI / 2],
	["vault", Vector3(-8, 0.15, 17.5), -PI * 0.65],
]
var variants: Array = ["base"]
var spot_i := 0
var var_i := 0
var acc := {}
var last_us := 0
var player: Node
var results: Array = []
var _shadow_orig := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=")
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if opts.has("spots"):
		var keep: PackedStringArray = opts["spots"].split("+")
		spots = spots.filter(func(s): return s[0] in keep)
	if opts.has("variants"):
		variants = Array(opts["variants"].split("+"))

func _process(_d: float) -> bool:
	frames += 1
	var now := Time.get_ticks_usec()
	var dt := (now - last_us) / 1000.0
	last_us = now
	match stage:
		0:
			if frames == 3:
				root.get_node("GameState").reset_run()
				root.get_node("GameState").set_flag("story_intro")
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(opts.get("level", root.get_node("GameState").level_path))
				stage = 1
				frames = 0
		1:
			if frames == 30:
				player = get_first_node_in_group("players")
				root.get_node("Cheats").set_cheat("god_mode", true)
				if root.get_node("Cutscenes").active:
					root.get_node("Cutscenes")._on_skip_pressed()
				# Keep the infected where they stand (animated, not chasing)
				# so every run sees the same scene.
				if not opts.has("live"):
					for z in get_nodes_in_group("zombies"):
						z.set_physics_process(false)
				for l in current_scene.find_children("*", "Light3D", true, false):
					_shadow_orig[l] = l.shadow_enabled
				if opts.has("cell"):
					load("res://scripts/world/static_batch.gd").cell = float(opts["cell"])
				# Measure fixed settings: no adapting to the (slow) test machine.
				load("res://scripts/world/web_quality.gd").adaptive = false
				if opts.has("web"):
					load("res://scripts/world/web_quality.gd").apply_level(current_scene, true)
				print("PERF_LOADED")
				stage = 2
				frames = 0
		2:
			if spot_i >= spots.size():
				_report()
				quit(0)
				return false
			var s: Array = spots[spot_i]
			var variant: String = variants[var_i]
			if frames == 1:
				player.global_position = s[1]
				player.velocity = Vector3.ZERO
				player.yaw = s[2]
				player.pitch = -0.08
				player.body.rotation.y = s[2]
				_variant(variant, true)
				acc = {"ms": [], "proc": 0.0, "phys": 0.0, "dc": 0, "obj": 0, "prim": 0, "n": 0}
			var warm := int(opts.get("warm", "12"))
			var n := int(opts.get("frames", "20"))
			if frames > warm and frames <= warm + n:
				acc["ms"].append(dt)
				acc["proc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				acc["phys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				var vp := root.get_viewport_rid()
				acc["dc"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
				acc["obj"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
				acc["prim"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				acc["n"] += 1
			if frames == warm + n + 1:
				var c: int = max(acc["n"], 1)
				var ms: Array = acc["ms"]
				ms.sort()
				var lights := _lights(player.camera.global_position)
				var row := {
					"spot": s[0], "variant": variant, "median_ms": snappedf(ms[ms.size() / 2], 0.1),
					"process_ms": snappedf(acc["proc"] / c, 0.01), "physics_ms": snappedf(acc["phys"] / c, 0.01),
					"draw_calls": acc["dc"] / c, "objects": acc["obj"] / c, "primitives": acc["prim"] / c,
					"lights_on": lights[0], "shadow_lights_on": lights[1], "shadow_lights_within_20m": lights[2],
					"scale": snappedf(root.get_viewport().scaling_3d_scale, 0.01),
					"shadow_budget": load("res://scripts/world/web_quality.gd").shadow_budget,
				}
				results.append(row)
				print("PERF ", JSON.stringify(row))
				if opts.has("lightlist"):
					_print_lights(player.camera)
				if opts.has("shots"):
					DirAccess.make_dir_recursive_absolute(opts["shots"])
					root.get_texture().get_image().save_png("%s/%s_%s.png" % [opts["shots"], s[0], variant.replace("&", "+")])
				_variant(variant, false)
				var_i += 1
				if var_i >= variants.size():
					var_i = 0
					spot_i += 1
				frames = 0
	return false

## Lights switched on, shadowed ones, and shadowed ones within 20 m of the
## camera (the ones whose shadows are actually drawn).
func _lights(cam: Vector3) -> Array:
	var on := 0
	var son := 0
	var snear := 0
	for l in current_scene.find_children("*", "Light3D", true, false):
		if not l.is_visible_in_tree() or l.light_energy <= 0.0:
			continue
		on += 1
		if l.shadow_enabled:
			son += 1
			if l is DirectionalLight3D or l.global_position.distance_to(cam) < 20.0:
				snear += 1
	return [on, son, snear]

## The browser shadow budget's lights near the camera: name, distance,
## reach, whether its shadow is on now (lightlist option).
func _print_lights(cam: Camera3D) -> void:
	for l in current_scene.find_children("*", "Light3D", true, false):
		if not l.has_meta("web_shadow_opacity"):
			continue
		var reach: float = l.omni_range if l is OmniLight3D else l.spot_range
		var d: float = l.global_position.distance_to(cam.global_position)
		if d > reach * 1.5:
			continue
		var fwd := -cam.global_transform.basis.z
		print("  LIGHT %s %s d=%.1f reach=%.1f importance=%.4f e=%.2f on=%s front=%.2f pos=%s" % [l.get_path().get_name(l.get_path().get_name_count() - 1), l.get_class(), d, reach, l.get_meta("web_shadow_imp", 0.0), l.light_energy, l.get_meta("web_shadow_on", false), fwd.dot((l.global_position - cam.global_position).normalized()), l.global_position.snapped(Vector3.ONE * 0.1)])
	print("  PICK_US ", load("res://scripts/world/web_quality.gd").last_pick_us)

## Turn a variant on (on = true) or back off.
func _variant(v: String, on: bool) -> void:
	if "&" in v:
		# Several at once: "moonbig&b2".
		for part in v.split("&"):
			_variant(part, on)
		return
	var vp := root.get_viewport()
	match v:
		"noshadow":
			for l in _shadow_orig:
				if is_instance_valid(l) and not l is DirectionalLight3D:
					l.shadow_enabled = false if on else _shadow_orig[l]
					if not on:
						# Let the browser's shadow budget decide again.
						l.remove_meta("web_shadow_on")
		"nosun":
			for l in _shadow_orig:
				if is_instance_valid(l) and l is DirectionalLight3D:
					l.shadow_enabled = false if on else _shadow_orig[l]
		"noglow":
			for we in current_scene.find_children("*", "WorldEnvironment", true, false):
				we.environment.glow_enabled = not on
		"nopost":
			for n in root.find_children("*", "CanvasLayer", true, false):
				if n.get_script() and str(n.get_script().resource_path).ends_with("post_fx.gd"):
					n.visible = not on
		"norain":
			for p in current_scene.find_children("*", "GPUParticles3D", true, false):
				p.visible = not on
		"half":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.5 if on else 1.0
		"msaa0":
			vp.msaa_3d = Viewport.MSAA_DISABLED if on else Viewport.MSAA_2X
		"noanim":
			# CPU: every AnimationPlayer / AnimationTree paused.
			for a in current_scene.find_children("*", "AnimationMixer", true, false):
				a.active = not on
		"nozombie":
			# CPU: the infected (AI, animation, hitboxes) switched off.
			for z in get_nodes_in_group("zombies"):
				z.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		"nohud":
			for h in root.find_children("*", "CanvasLayer", true, false):
				h.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		"near15", "near25":
			# What drawing only what's near would save: geometry whose box
			# is farther than 15 / 25 m from the camera hidden.
			var lim := 15.0 if v == "near15" else 25.0
			var cam_at: Vector3 = player.camera.global_position
			for g in current_scene.find_children("*", "GeometryInstance3D", true, false):
				if on:
					var box: AABB = g.global_transform * g.get_aabb()
					var d := box.get_center().distance_to(cam_at) - box.size.length() * 0.5
					if d > lim and g.visible:
						g.visible = false
						g.set_meta("probe_hidden", true)
				elif g.has_meta("probe_hidden"):
					g.visible = true
					g.remove_meta("probe_hidden")
		"b0", "b1", "b2", "b3", "b4", "b6":
			# The browser's shadow budget at this many lamps / windows.
			var wq = load("res://scripts/world/web_quality.gd")
			wq.shadow_budget = int(v.substr(1)) if on else wq.SHADOW_START
		"dp":
			# Omni shadows as two paraboloids instead of a six-sided cube.
			for l in current_scene.find_children("*", "OmniLight3D", true, false):
				l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID if on else OmniLight3D.SHADOW_CUBE
		"moonbig":
			# Upper bound for trimming the moon's shadow casters: the batched
			# small pieces on layer 1 move to layer 20 (lit by every light that
			# lights layer 1) and the moon stops taking casters from it.
			var bit := 1 << 19
			for b in current_scene.find_children("StaticBatches", "", true, false):
				for g in b.get_children():
					if on and g.layers == 1:
						g.layers = bit
					elif not on and g.layers == bit:
						g.layers = 1
			for l in current_scene.find_children("*", "Light3D", true, false):
				if l is DirectionalLight3D:
					l.shadow_caster_mask = (0xFFFFFFFF & ~bit) if on else 0xFFFFFFFF
				if on and (l.light_cull_mask & 1):
					l.light_cull_mask |= bit
		"web":
			if on:
				load("res://scripts/world/web_quality.gd").apply_level(current_scene, true)

func _report() -> void:
	var by := {}
	for r in results:
		var k: String = r["variant"]
		by[k] = by.get(k, 0.0) + r["median_ms"]
	for k in by:
		print("PERF_SUMMARY variant=%s mean_median_ms=%.1f" % [k, by[k] / spots.size()])
