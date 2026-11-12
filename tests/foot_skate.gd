extends SceneTree
## Do her feet stay planted? Moves the survivor across the Great Hall at
## each pace (full stick run, a walk, a slow walk, aiming) and measures how
## fast the planted foot slides along the floor in world space. A foot that
## slides backward means the legs cycle faster than she moves ("running on
## ice"), forward means slower ("gliding"). 0 is perfect.
## godot --headless --fixed-fps 60 --path . --script tests/foot_skate.gd -- [obcera|zegan] [outfit]
## Prints FOOT SKATE OK when every pace slides less than 0.25 m/s.
var who := "obcera"
var outfit := ""
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var fails := []
var cases := [
	{"name": "run", "stick": Vector2(0, -1), "aim": false},
	{"name": "walk", "stick": Vector2(0, -0.85), "aim": false},
	{"name": "slow walk", "stick": Vector2(0, -0.45), "aim": false},
	{"name": "aim walk", "stick": Vector2(0, -1), "aim": true, "one_way": true},
	{"name": "aim back off", "stick": Vector2(0, 1), "aim": true, "one_way": true},
	{"name": "run sideways", "stick": Vector2(1, 0), "aim": false},
]
var ci := 0
var di := 0
const DIRS := [0.0, PI * 0.5, PI, PI * 1.5]
var samples := []
var _prev := {}
var start := Vector3.ZERO

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: who = a[0]
	if a.size() > 1: outfit = a[1]

func _foot(side: String) -> Vector3:
	var sk: Skeleton3D = p.model._skel
	var i := sk.find_bone(side + "Foot")
	return sk.global_transform * sk.get_bone_global_pose(i).origin

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				if outfit != "":
					var gs = root.get_node("GameState")
					var l: Dictionary = gs.look(who)
					l["outfit"] = outfit
					gs.looks[who] = l
				root.get_node("Net").start_solo(who)
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				p = get_first_node_in_group("players")
				for zz in get_nodes_in_group("zombies"):
					zz.queue_free()
				start = p.global_position
				stage = 2
				t = 0.0
		2:
			# Start a case from a clear spot: put her back and face along -Z.
			var c: Dictionary = cases[ci]
			p.global_position = start
			p.velocity = Vector3.ZERO
			p.move_input = (c["stick"] as Vector2).rotated(DIRS[di])
			p.running = c["stick"].length() > 0.92
			p.aiming = c["aim"]
			if di == 0:
				samples.clear()
			_prev.clear()
			stage = 3
			t = 0.0
		3:
			t += d
			for zz in get_nodes_in_group("zombies"):
				zz.queue_free()   # scripted spawns would get in the way
			if t > 0.7:
				var l := _foot("Left")
				var r := _foot("Right")
				var low := "l" if l.y < r.y else "r"
				var pos := l if low == "l" else r
				var body: Vector3 = p.global_position
				if _prev.get("low", "") == low:
					var fv: Vector3 = (pos - _prev["pos"]) / d
					var bv: Vector3 = (body - _prev["body"]) / d
					if Vector2(bv.x, bv.z).length() > 0.3:
						samples.append({"y": pos.y, "fv": Vector2(fv.x, fv.z), "bv": Vector2(bv.x, bv.z), "anim": p.model._current, "sc": p.model._anim.speed_scale})
				_prev = {"low": low, "pos": pos, "body": body}
			if t > 1.6:
				p.move_input = Vector2.ZERO
				p.aiming = false
				di += 1
				if di == DIRS.size() or cases[ci].get("one_way", false):
					_report(cases[ci])
					di = 0
					ci += 1
				stage = 4 if ci < cases.size() else 9
				t = 0.0
		4:
			t += d
			if t > 0.6:
				stage = 2
		9:
			if fails.is_empty():
				print("FOOT SKATE OK")
			else:
				print("FOOT SKATE FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _report(c: Dictionary) -> void:
	if samples.size() < 10:
		fails.append("%s: too few samples" % c["name"])
		return
	var miny := INF
	for s in samples:
		miny = minf(miny, s["y"])
	var slide := 0.0
	var speed := 0.0
	var n := 0
	for s in samples:
		if s["y"] < miny + 0.03:
			var bv: Vector2 = s["bv"]
			var dirv := bv.normalized() if bv.length() > 0.1 else Vector2.ZERO
			slide += (s["fv"] as Vector2).dot(dirv)
			speed += bv.length()
			n += 1
	slide /= maxf(n, 1)
	speed /= maxf(n, 1)
	var anims := {}
	for s in samples:
		anims["%s x%.2f" % [s["anim"], s["sc"]]] = anims.get("%s x%.2f" % [s["anim"], s["sc"]], 0) + 1
	var anim := str(anims)
	var sc := 0.0
	print("%s %s: body %.2f m/s, clips %s%.0s, planted foot slides %+.2f m/s (%d planted frames)" % [who, c["name"], speed, anim, sc, slide, n])
	if absf(slide) > 0.25:
		fails.append("%s foot slides %+.2f m/s" % [c["name"], slide])
