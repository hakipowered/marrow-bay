extends SceneTree
## The hound's deaths. In 0.13 every hound just rolled over stiff as a board.
## Shoots a hound down in the Great Hall from each side, from behind, at a
## gallop, and with a wall where it would fall, and checks that:
##  1. It falls away from the shot: hit from its left it ends on its right
##     side, and the other way round.
##  2. Shot from behind its hind legs go first (the slump).
##  3. Cut down at a gallop it ploughs in and skids on ahead.
##  4. A wall where it would fall turns it the other way.
##  5. It doesn't lie there stiff: on the ground its legs paddle, then stop,
##     and its back ends near the floor.
## Prints HOUND DEATHS OK, or HOUND DEATHS FAIL with the reasons.
const AT := Vector3(-1.0, 0.0, 6.5)
## [name, round's direction (its own frame), galloping, wall on its right]
const CASES := [
	["from its left", Vector3(1, 0, 0), false, false],
	["from its right", Vector3(-1, 0, 0), false, false],
	["from behind", Vector3(0, 0, -1), false, false],
	["at a gallop", Vector3(0, 0, 1), true, false],
	["from its left, wall on its right", Vector3(1, 0, 0), false, true],
]
var frames := 0
var stage := 0
var t := 0.0
var i := 0
var p: Node = null
var lvl: Node = null
var h: Node = null
var sk: Skeleton3D = null
var wall: StaticBody3D = null
var fails := []
var notes := []
var paw_track := []
var spine_y0 := 0.0

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and stage < 30 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				p = get_first_node_in_group("players")
				lvl = get_first_node_in_group("level")
				p.global_position = Vector3(0, 0.1, -8.0)   # out in the courtyard
				stage = 2
		2:
			_spawn()
			stage = 3
			t = 0.0
		3:
			# one frame on its feet, then the shot
			t += d
			if t > 0.2:
				var c: Array = CASES[i]
				if c[2]:
					h.state = h.S.CHASE
					h.velocity = Vector3(0, 0, -3.2)
				h.take_hit(500.0, "pistol", "torso", c[1])
				paw_track.clear()
				spine_y0 = _bone("spine2").y
				stage = 4
				t = 0.0
		4:
			t += d
			if t > 1.1 and t < 2.0:
				paw_track.append(_bone("fpaw_L") - h.global_position)
			if t > 3.6:
				_judge()
				i += 1
				stage = 2 if i < CASES.size() else 30
		30:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("HOUND DEATHS OK")
			else:
				print("HOUND DEATHS FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _spawn() -> void:
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	if wall:
		wall.queue_free()
		wall = null
	var n := "HoundT%d" % i
	lvl.spawn_zombie_synced(n, AT, "hound")
	h = lvl.get_node(n)
	h.rotation.y = 0.0   # facing -Z: its right is +X
	h.state = h.S.IDLE
	h.velocity = Vector3.ZERO
	sk = h.model.find_children("*", "Skeleton3D", true, false)[0]
	if CASES[i][3]:
		wall = StaticBody3D.new()
		wall.collision_layer = 1
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.3, 2.0, 3.0)
		cs.shape = b
		wall.add_child(cs)
		lvl.add_child(wall)
		wall.global_position = AT + Vector3(0.5, 1.0, 0.0)

func _bone(n: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n))).origin

func _judge() -> void:
	var c: Array = CASES[i]
	var clip: String = h.model._anim.assigned_animation
	var back: Vector3 = _bone("spine2") - h.global_position
	var moved := 0.0
	for q in paw_track:
		moved = maxf(moved, (q as Vector3).distance_to(paw_track[0]))
	notes.append("%s: %s, back ends at %s (was %.2f m up), front paw moves %.2f m on the ground" % [c[0], clip, str(back.snapped(Vector3.ONE * 0.01)), spine_y0 - h.global_position.y, moved])
	if not clip.begins_with("death"):
		fails.append("%s: no death clip (%s)" % [c[0], clip])
		return
	if back.y > 0.3:
		fails.append("%s: still up off the floor (back %.2f m up)" % [c[0], back.y])
	var left := clip.ends_with("_left")
	if c[2]:
		if not clip.begins_with("death_collapse"):
			fails.append("at a gallop it didn't plough in (%s)" % clip)
		elif back.z > -0.4:
			fails.append("at a gallop it didn't skid on (back at z %.2f)" % back.z)
		return
	if clip.begins_with("death_collapse"):
		fails.append("%s: skidded though it was standing (%s)" % [c[0], clip])
	if c[3]:
		if not left or back.x > -0.1:
			fails.append("fell into the wall on its right (%s, back x %.2f)" % [clip, back.x])
		return
	if c[1].x > 0.5 and (left or back.x < 0.15):
		fails.append("%s: fell toward the shot (%s, back x %.2f)" % [c[0], clip, back.x])
	if c[1].x < -0.5 and (not left or back.x > -0.15):
		fails.append("%s: fell toward the shot (%s, back x %.2f)" % [c[0], clip, back.x])
	if c[1].z < -0.5 and not clip.begins_with("death_slump"):
		fails.append("from behind its hind legs didn't go first (%s)" % clip)
	if clip.begins_with("death") and not clip.begins_with("death_slump") and moved < 0.08:
		fails.append("%s: lay there stiff (front paw moved %.2f m)" % [c[0], moved])
