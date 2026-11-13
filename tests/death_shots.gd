extends SceneTree
## Pictures of infected dying in the real first area, over her shoulder:
## each round four of them walk at her and are killed at the same moment in
## different ways, and the frame is saved at five moments of the fall.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x720 \
##     --fixed-fps 15 --script tests/death_shots.gd -- <out_dir> [rounds e.g. 12]
## Saves <out_dir>/round<r>_<k>.png. Timing is by game time, so a low
## --fixed-fps renders the same moments much faster in software GL.

## variant, look, weapon, zone, shot from behind?
const ROUNDS := [
	[["shambler", "office", "p9", "torso", false], ["shambler", "nurse", "p9", "head", false],
		["shambler", "cop", "m12", "torso", false], ["shambler", "mechanic", "hatchet", "torso", false]],
	[["screamer", "screamer", "p9", "torso", false], ["brute", "brute", "bastion", "torso", false],
		["bloater", "bloated", "p9", "torso", false], ["spitter", "spitter", "p9", "torso", true]],
	[["shambler", "office", "gl", "torso", false], ["shambler", "cop", "flamer", "torso", false],
		["riot", "riot", "p9", "torso", true], ["runner", "jogger", "p9", "leg", false]],
]
const TIMES := [0.12, 0.45, 0.9, 1.6, 4.5]
var out := "/tmp"
var frames := 0
var stage := 0
var t := 0.0
var p: Node3D
var lvl: Node
var fwd := Vector3.FORWARD
var side := Vector3.RIGHT
var round_i := 0
var zs: Array = []
var shot := 0
var cam: Camera3D
var rounds: Array = []
var t2 := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	for ch in (a[1] if a.size() > 1 else "012"):
		rounds.append(int(ch))
	round_i = rounds[0]
	DirAccess.make_dir_recursive_absolute(out)

func _open_direction() -> Vector3:
	var space := p.get_world_3d().direct_space_state
	var best := Vector3.FORWARD
	var best_d := 0.0
	for i in 24:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 24.0)
		var worst := INF
		for off in [-2.0, 0.0, 2.0]:
			var o: Vector3 = p.global_position + Vector3.UP * 1.0 + d.cross(Vector3.UP) * float(off)
			var q := PhysicsRayQueryParameters3D.create(o, o + d * 12.0, 1)
			var hit := space.intersect_ray(q)
			worst = minf(worst, 12.0 if hit.is_empty() else o.distance_to(hit.position))
		if worst > best_d:
			best_d = worst
			best = d
	print("open direction ", best, " clear ", best_d, " m")
	return best

func _spawn_round() -> void:
	for z in zs:
		if is_instance_valid(z):
			z.queue_free()
	zs.clear()
	var zscript = load("res://scripts/enemies/zombie.gd")
	var r: Array = ROUNDS[round_i]
	for i in r.size():
		var c: Array = r[i]
		var z = zscript.new()
		z.name = "Shot%d_%d" % [round_i, i]
		z.variant = c[0]
		z.look = c[1]
		z.position = p.global_position + fwd * 5.2 + side * (i - 1.5) * 1.7
		z.rotation.y = atan2(fwd.x, fwd.z)   # facing her
		lvl.add_child(z)
		z.drop_table = "none"
		z.state = z.S.CHASE
		zs.append(z)

func _kill_round() -> void:
	var r: Array = ROUNDS[round_i]
	for i in zs.size():
		var z = zs[i]
		var c: Array = r[i]
		var dir: Vector3 = (z.global_position - p.global_position)
		dir.y = 0.0
		dir = dir.normalized()
		if c[4]:
			# Her partner got it from behind.
			z.rotation.y += PI
		if c[2] == "flamer":
			root.get_node("Effects").ignite(z, 4.0)
		z.take_hit(540.0 if c[2] == "gl" else 999.0, c[2], c[3], dir)

func _process(d: float) -> bool:
	frames += 1
	var gs = root.get_node("GameState")
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(gs.level_path)
				stage = 1
				frames = 0
		1:
			if frames > 60:
				p = get_first_node_in_group("players")
				lvl = get_first_node_in_group("level")
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				fwd = _open_direction()
				side = fwd.cross(Vector3.UP).normalized()
				p.input_locked = true
				cam = Camera3D.new()
				cam.fov = 62
				lvl.add_child(cam)
				cam.look_at_from_position(p.global_position - fwd * 1.6 + Vector3.UP * 2.6 + side * 0.4,
					p.global_position + fwd * 5.5 + Vector3.UP * 0.4, Vector3.UP)
				cam.make_current()
				stage = 2
				frames = 0
		2:
			t2 += d
			if frames == 2:
				_spawn_round()
				t2 = 0.0
			if frames > 2 and t2 >= 0.8:
				_kill_round()
				t = 0.0
				shot = 0
				stage = 3
		3:
			t += d
			if shot < TIMES.size() and t >= TIMES[shot]:
				root.get_texture().get_image().save_png("%s/round%d_%d.png" % [out, round_i, shot])
				shot += 1
			if shot >= TIMES.size():
				for z in zs:
					print(z.name, " ", z.variant, " -> ", z.model._death_name, " ", z.model._death)
				rounds.pop_front()
				if rounds.is_empty():
					quit(0)
				round_i = rounds[0]
				stage = 2
				frames = 0
	return false
