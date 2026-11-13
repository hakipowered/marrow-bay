extends SceneTree
## The street hound in the real level, through the game camera: feeding on its
## kill, then it notices her, gallops in and leaps, she shoots it down.
## Saves feeding/charge/leap/dead PNGs and logs what happened (states, the
## bite, the hits by zone). Also a headless check: run without a renderer and
## it only logs.
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x1200 --fixed-fps 30 --script tests/hound_scene.gd -- <out_dir>
var out := "/tmp"
var frames := 0
var p: Node = null
var h: Node = null
var stage := 0
var t := 0.0
var shots := {}
var states := []
var hp0 := 0.0
var zone_hits := {}
var fail := ""
var skipped := {}
var _logged_stage := -1

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]

func _shot(name: String) -> void:
	if shots.has(name) or DisplayServer.get_name() == "headless":
		shots[name] = true
		return
	shots[name] = true
	var path := "%s/hound_%s.png" % [out, name]
	root.get_texture().get_image().save_png(path)
	print("saved ", path)

## Software rendering is slow, so the frames between the shots aren't drawn
## (only once the level is up: switched off while it loads, the view stays black).
func _render(on: bool) -> void:
	if DisplayServer.get_name() != "headless" and RenderingServer.render_loop_enabled != on:
		RenderingServer.render_loop_enabled = on

func _aim_at(pt: Vector3) -> void:
	var d: Vector3 = (pt - p.camera.global_position).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1.0, 1.0))

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(root.get_node("GameState").level_path)
		return false
	if frames < 40:
		return false
	if frames == 40:
		p = get_first_node_in_group("players")
		h = current_scene.get_node_or_null("Z_street_hound")
		if h == null:
			print("FAIL no street hound in the level")
			quit(1)
			return true
		print("hound at ", h.global_position, " state ", h.state, " hitboxes ", h._hitboxes.size())
		# Only the hound: no other infected walking into the fight or the shots.
		for z in get_nodes_in_group("zombies"):
			if z != h:
				z.queue_free()
		# Stand her up the street from it, looking at it.
		p.global_position = h.global_position + Vector3(4.8, 0, 1.4)
		hp0 = p.hp
	var cuts = root.get_node("Cutscenes")
	if cuts.active:
		# Skip the story scenes like a player who has seen them.
		if not skipped.has(cuts.current):
			skipped[cuts.current] = true
			cuts._on_skip_pressed()
		return false
	t += delta
	if h == null or not is_instance_valid(h):
		return false
	if stage != _logged_stage:
		_logged_stage = stage
		print("%.2f stage %d player hp %.0f" % [t, stage, p.hp])
	if states.is_empty() or states[-1] != h.state:
		states.append(h.state)
		print("%.2f hound state %d pace %.1f" % [t, h.state, h.velocity.length()])
	match stage:
		0:   # watch it feed
			_aim_at(h.global_position + Vector3.UP * 0.4)
			if t > 1.6:
				_shot("feeding")
				stage = 1
		1:   # step closer until it notices
			_render(false)
			_aim_at(h.global_position + Vector3.UP * 0.4)
			if t > 1.7 and t < 1.8:
				p.global_position = h.global_position + Vector3(3.9, 0, 1.2)
			if t > 30.0:
				fail = "it never noticed her 4 m away"
				stage = 9
			if h.state == 2:   # CHASE
				p.move_input = Vector2.ZERO
				p.global_position = h.global_position + (p.global_position - h.global_position).normalized() * 6.5
				stage = 2
				t = 0.0
		2:   # it comes at her
			_render(true)
			_aim_at(h.global_position + Vector3.UP * 0.5)
			if frames % 15 == 0:
				print("  %.2f dist %.2f pace %.1f state %d at %s" % [t, h.global_position.distance_to(p.global_position), h.velocity.length(), h.state, h.global_position])
			if h.velocity.length() > 3.0 and t > 0.6:
				_shot("charge")
			if h.state == 3:   # ATTACK
				if h._attack_t > 0.2:
					_shot("leap")
				if h._attack_t > 0.42:
					stage = 3
					t = 0.0
			if t > 12.0:
				fail = "never attacked"
				stage = 9
		3:   # shoot it
			_render(false)
			var boxes: Array = h._hitboxes
			var aim: Vector3 = boxes[0].global_position if boxes.size() > 0 else h.global_position + Vector3.UP * 0.5
			_aim_at(aim)
			p.aiming = true
			p.fire_held = t > 0.3
			if h.state == 6:   # DEAD
				p.fire_held = false
				p.aiming = false
				stage = 4
				t = 0.0
			if t > 15.0:
				fail = "couldn't kill it"
				stage = 9
		4:
			_aim_at(h.global_position + Vector3.UP * 0.2)
			_render(t > 1.5)
			if t > 2.0:
				_shot("dead")
				stage = 9
		9:
			print("states seen: ", states)
			print("player hp %.0f -> %.0f" % [hp0, p.hp])
			print("hound hp %.0f dead %s" % [h.hp, h.state == 6])
			if fail != "":
				print("FAIL ", fail)
			elif p.hp >= hp0:
				print("FAIL the hound never bit her")
			else:
				print("PASS hound fed, charged, bit and died")
			quit(0 if fail == "" and p.hp < hp0 else 1)
			return true
	return false
