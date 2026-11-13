extends SceneTree
## Kills every kind of infected in many different ways in a test yard (open
## ground, a wall right behind, a ledge, a doorway) and checks how they go
## down:
##  - kills in a row don't all use the same death; the death fits the blow
##    (shot in the back falls forward, a blast or a shotgun at arm's length
##    throws it, a burning one writhes, a crawler slumps flat, one playing
##    dead stays down),
##  - no part of the body ends up in a wall or hanging over a drop,
##  - the body lies on the floor: nothing sunk into it, not floating.
## Prints DEATHS OK, or DEATHS FAIL with the reasons.
##   godot --headless --path . --fixed-fps 60 --script tests/death_variety.gd
## With a display, "shots <dir>" also saves each death at 4 moments
## (<dir>/death_<n>.png strips, then python3 -c ... to sheet them):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 480x360 \
##     --fixed-fps 60 --script tests/death_variety.gd -- shots /tmp/deaths

## variant, look, weapon, zone, where the shot comes from (degrees off its
## face: 0 in front, 180 behind), shooter distance, setting
const CASES := [
	["shambler", "office", "p9", "torso", 0, 6.0, "open"],
	["shambler", "nurse", "p9", "head", 0, 6.0, "open"],
	["shambler", "cop", "p9", "torso", 180, 6.0, "open"],
	["shambler", "mechanic", "p9", "torso", 90, 6.0, "open"],
	["shambler", "mechanic", "m12", "torso", 0, 2.5, "open"],
	["runner", "jogger", "p9", "torso", 0, 6.0, "rushing"],
	["shambler", "office", "gl", "torso", 20, 3.0, "open"],
	["shambler", "cop", "flamer", "torso", 0, 4.0, "open"],
	["screamer", "screamer", "p9", "torso", 0, 6.0, "open"],
	["brute", "brute", "bastion", "torso", 0, 6.0, "open"],
	["bloater", "bloated", "p9", "torso", -60, 6.0, "open"],
	["spitter", "spitter", "p9", "torso", 0, 6.0, "open"],
	["riot", "riot", "p9", "torso", 180, 6.0, "open"],
	["crawler", "office", "p9", "head", 0, 4.0, "open"],
	["shambler", "nurse", "hatchet", "torso", 0, 1.5, "open"],
	["burner", "burnt", "p9", "leg", 0, 6.0, "open"],
	["shambler", "jogger", "p9", "torso", 0, 6.0, "wall_behind"],
	["shambler", "office", "m12", "torso", 0, 2.5, "wall_behind"],
	["shambler", "mechanic", "p9", "torso", 180, 6.0, "wall_ahead"],
	["shambler", "cop", "p9", "torso", 0, 6.0, "ledge"],
	["shambler", "nurse", "gl", "torso", 0, 3.0, "corner"],
	["possum", "suit", "p9", "torso", 0, 5.0, "open"],
	["shambler", "office", "knife", "torso", 0, 1.5, "open"],
	["shambler", "mechanic", "p9", "torso", 0, 6.0, "open"],
	["shambler", "cop", "p9", "torso", -90, 6.0, "open"],
]
const SETTLE := 7.0
const SHOT_TIMES := [0.2, 0.6, 1.3, SETTLE - 0.2]
const SPACING := 7.0

var frames := 0
var stage := 0
var t := 0.0
var arena: Node3D
var zs: Array = []          # [zombie, case, stand position]
var shooter: Node3D
var shots_dir := ""
var shot_i := 0
var cams: Array = []
var cam_i := 0
var fails := []

const STUB := """extends Node3D
@rpc("authority", "reliable", "call_local")
func spawn_pickup(_i: String, _p: Vector3, _a: int) -> void:
	pass
@rpc("authority", "reliable", "call_local")
func spawn_hazard(_k: String, _p: Vector3, _r: float, _d: float) -> void:
	pass
@rpc("authority", "reliable", "call_local")
func spawn_zombie_synced(_n: String, _p: Vector3, _v := "shambler") -> void:
	pass
"""
const PLAYER_STUB := """extends Node3D
var downed := false
var pinned := false
func apply_damage(_d: float, _from = null) -> void:
	pass
"""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2 and a[0] == "shots":
		shots_dir = a[1]
		DirAccess.make_dir_recursive_absolute(shots_dir)

func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func _box(pos: Vector3, size: Vector3, color := Color(0.35, 0.33, 0.3)) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	b.add_child(mi)
	b.position = pos   # placed before it enters the world (arena sits at the origin)
	arena.add_child(b)

func _build() -> void:
	arena = Node3D.new()
	arena.name = "DeathYard"
	arena.set_script(_script(STUB))
	root.add_child(arena)
	current_scene = arena
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.06, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	arena.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	arena.add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.28, 0.27, 0.26))
	shooter = Node3D.new()
	shooter.set_script(_script(PLAYER_STUB))
	shooter.add_to_group("players")
	arena.add_child(shooter)
	shooter.global_position = Vector3(0, 0, 400)   # far off until a case needs it close
	var zscript = load("res://scripts/enemies/zombie.gd")
	for i in CASES.size():
		var c: Array = CASES[i]
		var stand := Vector3((i % 5) * SPACING, 0, (i / 5) * SPACING)
		# The round travels along +X; the infected faces `from` degrees off
		# the direction it came from.
		var to_shooter := Vector3(-1, 0, 0)
		var face := to_shooter.rotated(Vector3.UP, deg_to_rad(float(c[4])))
		var setting: String = c[6]
		if setting == "ledge":
			# Standing at the edge of a 1.2 m drop that's right behind it.
			_box(stand + Vector3(-1.5, 0.6, 0), Vector3(3.6, 1.2, 4.0))
			stand += Vector3(0.15, 1.2, 0)
			stand.x -= 0.6
		var z = zscript.new()
		z.name = "Z%02d_%s" % [i, c[0]]
		z.variant = c[0]
		z.look = c[1]
		z.position = stand
		z.rotation.y = atan2(-face.x, -face.z)
		arena.add_child(z)
		z.drop_table = "none"
		match setting:
			"wall_behind":
				_box(stand + Vector3(0.75, 1.5, 0), Vector3(0.3, 3.0, 5.0))
			"wall_ahead":
				_box(stand + Vector3(-0.8, 1.5, 0), Vector3(0.3, 3.0, 5.0))
			"corner":
				_box(stand + Vector3(0.9, 1.5, 0), Vector3(0.3, 3.0, 4.0))
				_box(stand + Vector3(0, 1.5, 1.0), Vector3(4.0, 3.0, 0.3))
		zs.append([z, c, stand])
	if shots_dir != "":
		for e in zs:
			var cam := Camera3D.new()
			cam.fov = 50
			arena.add_child(cam)
			var st: Vector3 = e[2]
			# Over the shooter's shoulder, high, like the game camera.
			cam.look_at_from_position(st + Vector3(-4.6, 3.4, 2.2), st + Vector3(0.3, 0.45, 0), Vector3.UP)
			cams.append(cam)

func _kill(e: Array) -> void:
	var z = e[0]
	var c: Array = e[1]
	var dir := Vector3(1, 0, 0)
	var dist: float = c[5]
	shooter.global_position = z.global_position - dir * dist
	if c[6] == "rushing":
		z.state = z.S.CHASE
		z.velocity = -z.global_transform.basis.z * 2.8
	if c[0] == "possum":
		z.state = z.S.PLAY_DEAD
	if c[2] == "flamer":
		root.get_node("Effects").ignite(z, 4.0)
	var dmg := 999.0
	if c[2] == "gl":
		dir = Vector3(1.0, 0.0, 0.25).normalized()   # the blast went off a little to one side
		dmg = 540.0
	z.take_hit(dmg, c[2], c[3], dir)
	shooter.global_position = Vector3(0, 0, 400)

func _process(d: float) -> bool:
	frames += 1
	if frames == 3:
		_build()
		return false
	if frames < 8:
		return false
	match stage:
		0:
			# Possums need a frame to lie down before they're shot.
			for e in zs:
				if e[1][0] == "possum":
					e[0].state = e[0].S.PLAY_DEAD
			if frames > 14:
				for e in zs:
					_kill(e)
				stage = 1
				t = 0.0
		1:
			t += d
			if shots_dir != "" and shot_i < SHOT_TIMES.size() and t >= SHOT_TIMES[shot_i]:
				paused = true
				stage = 2
				cam_i = 0
			elif t >= SETTLE:
				_check()
				return true
		2:
			# Paused: every camera takes its picture of the same moment.
			if cam_i > 0:
				var img := root.get_texture().get_image()
				img.save_png("%s/death_%02d_%d.png" % [shots_dir, cam_i - 1, shot_i])
			if cam_i < cams.size():
				(cams[cam_i] as Camera3D).make_current()
				cam_i += 1
			else:
				paused = false
				shot_i += 1
				stage = 1
	return false

func _bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	var b := sk.find_bone(bone)
	return sk.global_transform * sk.get_bone_global_pose(b).origin if b >= 0 else Vector3.INF

## Lowest point of the posed body: the skinned mesh, every 9th vertex.
func _lowest(sk: Skeleton3D) -> float:
	var low := INF
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var mats: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			var bb := sk.find_bone(mi.skin.get_bind_name(i))
			mats.append(sk.global_transform * sk.get_bone_global_pose(bb) * mi.skin.get_bind_pose(i))
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for i in range(0, v.size(), 9):
			var y := 0.0
			for j in 4:
				if w[i * 4 + j] > 0.0:
					y += w[i * 4 + j] * (mats[bi[i * 4 + j]] * v[i]).y
			low = minf(low, y)
	return low

func _check() -> void:
	var space := arena.get_world_3d().direct_space_state
	var used := {}
	var open_used := {}
	for e in zs:
		var z = e[0]
		var c: Array = e[1]
		var tag := "%s/%s %s %s from %d %s" % [c[0], c[1], c[2], c[3], c[4], c[6]]
		var m = z.model
		var clip: String = m._death_name.trim_prefix("deaths/")
		used[clip] = used.get(clip, 0) + 1
		if c[6] == "open":
			open_used[clip] = true
		var plan: Dictionary = m._death
		print("  %-44s -> %-11s yaw %+.2f k %.2f push %.2f floor %+.2f" % [tag, clip, plan.get("y", 0.0), plan.get("k", 1.0), (plan.get("p", Vector3.ZERO) as Vector3).length(), plan.get("f", 0.0)])
		if z.state != z.S.DEAD:
			fails.append("%s: not dead" % tag)
			continue
		if m._skel == null:
			continue
		var sk: Skeleton3D = m._skel
		var chest: Vector3 = z.global_position + Vector3.UP * 0.9
		for bone in ["Head", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Spine"]:
			var p := _bone_pos(sk, bone)
			var q := PhysicsRayQueryParameters3D.create(chest, p + Vector3.UP * 0.12, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				fails.append("%s: %s went into a wall (%s)" % [tag, bone, clip])
		var hips := _bone_pos(sk, "Hips")
		var q2 := PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.5, hips + Vector3.DOWN * 2.0, 1)
		var floor_hit := space.intersect_ray(q2)
		if floor_hit.is_empty():
			fails.append("%s: nothing under the body" % tag)
			continue
		var fy: float = floor_hit.position.y
		var low := _lowest(sk)
		var hip_h := hips.y - fy
		if c[0] != "possum" and (low < fy - 0.05 or low > fy + 0.07):
			fails.append("%s: body %s the floor by %.2f m (%s)" % [tag, "sinks into" if low < fy else "floats over", absf(low - fy), clip])
		if hip_h > 0.55:
			fails.append("%s: still up (hips %.2f m) (%s)" % [tag, hip_h, clip])
		# The fit to the blow.
		match c[6]:
			"ledge":
				if fy < z.global_position.y - 0.3:
					fails.append("%s: fell off the ledge" % tag)
		if c[2] in ["gl"] and c[6] == "open" and not clip in ["flip", "blown_back", "sweep"]:
			fails.append("%s: a blast didn't throw it (%s)" % [tag, clip])
		if c[4] == 180 and c[6] == "open" and clip in ["fall_back", "slow_back", "sit_back", "blown_back", "flip"]:
			fails.append("%s: shot in the back but fell backwards (%s)" % [tag, clip])
		if c[2] == "flamer" and clip != "convulse" and clip != "knees_face" and clip != "gut":
			fails.append("%s: burning but %s" % [tag, clip])
		if c[0] == "crawler" and hip_h > 0.4:
			fails.append("%s: crawler got up to die" % tag)
	print("deaths used: ", used)
	if open_used.size() < 8:
		fails.append("only %d different deaths across %d open-ground kills" % [open_used.size(), CASES.size()])
	if fails.is_empty():
		print("DEATHS OK")
	else:
		for f in fails:
			print("  ", f)
		print("DEATHS FAIL")
	quit(0 if fails.is_empty() else 1)
