extends SceneTree
## Builds res://assets/characters/enemies/<id>/<id>_deaths.res for every
## infected body: the death clips (falling back, knees then face, blown off
## the feet, shot in the back, choking, clutching the gut, convulsing in
## flames ...), played by ZombieModel as "deaths/<clip>".
##
## The clips come from ONE Meshy rig of the mechanic with the death presets
## (job ids in the project files, infected/model_jobs.txt). Download each
## clip's animation GLB to build_tmp/deaths/src/m<preset>.glb, then:
##
##   godot --headless --path . --script tools/import_death_clips.gd [-- <id> ...]
##   godot --headless --path . --script tools/import_death_clips.gd -- analyze
##
## For each body the clip is
##  - retargeted onto its skeleton (same formula as CombatClips: every bone
##    turns by the same amount in the world, hips travel scaled by leg length),
##  - trimmed: the standing or walking lead-in Meshy puts before the hit is
##    cut, so the death starts on the frame the round lands,
##  - re-rooted: the hips start over the feet, and how far the fall carries
##    the body is scaled per clip (Meshy's blown-back slides 4.4 m),
##  - grounded on this body's own mesh: the skinned vertices are posed over
##    the clip and the hips are raised wherever any part of the body would
##    go through the floor, and at the end the body lies exactly on it (a fat
##    belly or a big man's shoulders don't sink, a thin one doesn't hover).
## Metadata kept for the game (positions in the model's own space, metres):
##   end_<clip>     key points of the body at rest on the floor (head, hands,
##                  feet, hips, chest), used to check a fall clears the walls
##   travel_<clip>  hips (t, x, z) over the clip, so the game can shorten a
##                  fall against a wall or add a blast's push
##   land_<clip>    seconds into the clip when the body is down

const SRC := "res://build_tmp/deaths/src"
## clip: [Meshy preset, lead-in to cut (s), travel scale]
const CLIPS := {
	"headshot": [8, 0.12, 1.0],       # head snaps back, stagger, knees, face down
	"back_shot": [180, 0.5, 1.0],   # arches from a round in the back, stumbles, falls
	"convulse": [181, 0.0, 1.0],     # jerks and writhes (burning), then pitches forward
	"blown_back": [182, 0.85, 0.5],  # thrown off the feet backwards (shotgun, blast)
	"fall_back": [183, 1.55, 1.0],   # arms flung as it topples back (its long arms-out stand is cut)
	"knees_face": [184, 0.0, 1.0],   # hit in the chest, crumples to the knees, face down
	"slow_back": [185, 1.2, 1.0],    # head tips back, topples slowly backwards
	"choke": [186, 1.3, 1.0],        # clutches the throat, knees, falls forward
	"flip": [187, 0.0, 0.8],         # legs thrown up over the head, lands spread out
	"gut": [188, 0.0, 1.0],          # clutches the belly, knees, curls up on its side
	"sit_back": [189, 0.35, 1.0],    # hunches, sits down hard, falls back
	"sweep": [190, 0.8, 1.0],        # legs swept out from under it, lands on the back
}
const KEY_BONES := ["Head", "Hips", "Spine", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg"]
const FPS := 30.0
const GROUND_FPS := 15.0
const VERT_STEP := 7

var _src_rest_q := {}
var _src_rest_o := {}
var _src_parent := {}
var _src_hip_y := 0.0
var _src_anims := {}   # clip -> Animation (bone-named tracks, source rig)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_load_sources()
	if args.size() > 0 and args[0] == "analyze":
		_analyze()
		quit(0)
		return
	var ids: Array = args
	if ids.is_empty():
		for d in DirAccess.get_directories_at("res://assets/characters/enemies"):
			if ResourceLoader.exists("res://assets/characters/enemies/%s/%s.glb" % [d, d]):
				ids.append(d)
	for id in ids:
		_build(id)
	quit(0)

func _load_sources() -> void:
	for clip in CLIPS:
		var path := "%s/m%d.glb" % [SRC, CLIPS[clip][0]]
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
			printerr("missing ", path)
			continue
		var scene: Node = doc.generate_scene(st)
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		if _src_rest_q.is_empty():
			for i in sk.get_bone_count():
				var n := sk.get_bone_name(i)
				_src_rest_q[n] = sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
				_src_rest_o[n] = sk.get_bone_rest(i).origin
				_src_parent[n] = sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else ""
			_src_hip_y = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var a: Animation = null
		for n in ap.get_animation_list():
			if n != "RESET":
				a = ap.get_animation(n).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var bone := a.track_get_path(t).get_concatenated_subnames()
			if bone == "" or a.track_get_type(t) not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
				a.remove_track(t)
				continue
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and bone != "Hips":
				a.remove_track(t)   # only the hips move; the rest keep the body's own lengths
				continue
			a.track_set_path(t, NodePath("Skeleton3D:" + bone))
		# Bones Meshy leaves unkeyed (the upper spine, the head tips) hold
		# their rest. Key them, or at run time they'd keep whatever the
		# body's other clips last left in them (the spine bent 15 degrees).
		for i in sk.get_bone_count():
			var bone := sk.get_bone_name(i)
			if _track(a, bone, Animation.TYPE_ROTATION_3D) < 0:
				var t := a.add_track(Animation.TYPE_ROTATION_3D)
				a.track_set_path(t, NodePath("Skeleton3D:" + bone))
				var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
				a.rotation_track_insert_key(t, 0.0, q)
				a.rotation_track_insert_key(t, a.length, q)
		_src_anims[clip] = a
		scene.free()

## Prints, for each source clip, how the upper body and hips move over time,
## to find where the lead-in ends (the CLIPS cut times).
func _analyze() -> void:
	for clip in _src_anims:
		var a: Animation = _src_anims[clip]
		var line := "%-11s len %.2f |" % [clip, a.length]
		var q0 := {}
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				q0[t] = a.rotation_track_interpolate(t, 0.0)
		var tm := 0.0
		while tm <= minf(a.length, 2.4):
			var s := 0.0
			for t in q0:
				var bone := a.track_get_path(t).get_concatenated_subnames()
				if bone in ["Spine", "Spine01", "Spine02", "neck", "Head", "LeftArm", "RightArm"]:
					s += (q0[t] as Quaternion).angle_to(a.rotation_track_interpolate(t, tm))
			line += " %.1f" % s
			tm += 0.1
		print(line)

func _build(id: String) -> void:
	var base: Node3D = (load("res://assets/characters/enemies/%s/%s.glb" % [id, id]) as PackedScene).instantiate()
	var sk: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	var skel_path := str(base.get_path_to(sk))
	# Skeleton space -> model space (the armature is scaled 0.01).
	var to_model := Transform3D()
	var n: Node = sk
	while n != base:
		if n is Node3D:
			to_model = (n as Node3D).transform * to_model
		n = n.get_parent()
	var skin := _skin_data(base, sk)
	var hips := sk.find_bone("Hips")
	var ratio := sk.get_bone_global_rest(hips).origin.y / _src_hip_y
	var lib := AnimationLibrary.new()
	for clip in _src_anims:
		var a := _retarget(_src_anims[clip], sk, ratio)
		a = _trim(a, float(CLIPS[clip][1]))
		_reroot(a, float(CLIPS[clip][2]))
		var info := _ground(a, sk, skin, to_model)
		# Track paths as the model's AnimationPlayer (on the model root) sees them.
		for t in a.get_track_count():
			a.track_set_path(t, NodePath("%s:%s" % [skel_path, a.track_get_path(t).get_concatenated_subnames()]))
		a.loop_mode = Animation.LOOP_NONE
		lib.add_animation(clip, a)
		for k in info:
			lib.set_meta(k + "_" + clip, info[k])
		print("  %s %-11s len=%.2f land=%.2f lift_end=%.3f max_lift=%.3f fall=%s" % [id, clip, a.length, info["land"], info["lift_end"], info["max_lift"], info["fall"]])
	lib.set_meta("clips", PackedStringArray(_src_anims.keys()))
	var out := "res://assets/characters/enemies/%s/%s_deaths.res" % [id, id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("saved ", out, " ", error_string(err))
	base.free()

## CombatClips' retarget: q = Gdst(parent)^-1 * Gsrc(parent) * q * Gsrc(bone)^-1 * Gdst(bone)
func _retarget(src: Animation, sk: Skeleton3D, ratio: float) -> Animation:
	var a: Animation = src.duplicate(true)
	for t in range(a.get_track_count() - 1, -1, -1):
		var bone := a.track_get_path(t).get_concatenated_subnames()
		var bd := sk.find_bone(bone)
		if bd < 0 or not _src_rest_q.has(bone):
			a.remove_track(t)
			continue
		var pd := sk.get_bone_parent(bd)
		var gs: Quaternion = _src_rest_q[bone]
		var gd := sk.get_bone_global_rest(bd).basis.get_rotation_quaternion()
		var gps: Quaternion = _src_rest_q.get(_src_parent.get(bone, ""), Quaternion.IDENTITY)
		var gpd := sk.get_bone_global_rest(pd).basis.get_rotation_quaternion() if pd >= 0 else Quaternion.IDENTITY
		var pre := gpd.inverse() * gps
		var post := gs.inverse() * gd
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			for k in a.track_get_key_count(t):
				a.track_set_key_value(t, k, (pre * (a.track_get_key_value(t, k) as Quaternion) * post).normalized())
		else:
			var rs: Vector3 = _src_rest_o[bone]
			var rd := sk.get_bone_rest(bd).origin
			for k in a.track_get_key_count(t):
				a.track_set_key_value(t, k, rd + pre * (((a.track_get_key_value(t, k) as Vector3) - rs) * ratio))
	return a

## Drops the lead-in and resamples every track at FPS from `from` to the end.
func _trim(src: Animation, from: float) -> Animation:
	var a := Animation.new()
	a.length = src.length - from
	var steps := int(ceil(a.length * FPS))
	for t in src.get_track_count():
		var nt := a.add_track(src.track_get_type(t))
		a.track_set_path(nt, src.track_get_path(t))
		a.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		for i in steps + 1:
			var tm := minf(i / FPS, a.length)
			if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				a.rotation_track_insert_key(nt, tm, src.rotation_track_interpolate(t, from + tm))
			else:
				a.position_track_insert_key(nt, tm, src.position_track_interpolate(t, from + tm))
	return a

## The hips start right over where the body stands; the fall's travel is
## scaled by `travel`.
func _reroot(a: Animation, travel: float) -> void:
	var ht := _track(a, "Hips", Animation.TYPE_POSITION_3D)
	if ht < 0:
		return
	var p0: Vector3 = a.track_get_key_value(ht, 0)
	var home := Vector3(_rest_hips_xz.x, 0, _rest_hips_xz.y)
	for k in a.track_get_key_count(ht):
		var v: Vector3 = a.track_get_key_value(ht, k)
		var d := Vector3(v.x - p0.x, 0, v.z - p0.z) * travel
		a.track_set_key_value(ht, k, Vector3(home.x + d.x, v.y, home.z + d.z))

var _rest_hips_xz := Vector2.ZERO

static func _track(a: Animation, bone: String, type: int) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) == type and a.track_get_path(t).get_concatenated_subnames() == bone:
			return t
	return -1

## Vertices of the body's mesh (every VERT_STEP-th), with their skin
## weights, to pose them over a clip.
func _skin_data(base: Node, sk: Skeleton3D) -> Dictionary:
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var binds: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		var b0 := binds.size()
		for i in mi.skin.get_bind_count():
			var bb := mi.skin.get_bind_bone(i)
			if bb < 0:
				bb = sk.find_bone(mi.skin.get_bind_name(i))
			bind_bone.append(bb)
			binds.append(mi.skin.get_bind_pose(i))
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bi.size() / maxi(v.size(), 1)
			for i in range(0, v.size(), VERT_STEP):
				verts.append(mi.transform * v[i])
				for j in 4:
					bones.append(b0 + bi[i * per + j] if j < per else b0)
					weights.append(w[i * per + j] if j < per else 0.0)
	_rest_hips_xz = Vector2(sk.get_bone_rest(sk.find_bone("Hips")).origin.x, sk.get_bone_rest(sk.find_bone("Hips")).origin.z)
	return {"verts": verts, "bones": bones, "weights": weights, "binds": binds, "bind_bone": bind_bone}

## Global (skeleton space) pose of every bone at time tm.
func _pose(a: Animation, sk: Skeleton3D, tm: float, tracks: Dictionary) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var r := sk.get_bone_rest(b)
		var name := sk.get_bone_name(b)
		var q: Quaternion = a.rotation_track_interpolate(tracks["r:" + name], tm) if tracks.has("r:" + name) else r.basis.get_rotation_quaternion()
		var o: Vector3 = a.position_track_interpolate(tracks["p:" + name], tm) if tracks.has("p:" + name) else r.origin
		var local := Transform3D(Basis(q), o)
		var p := sk.get_bone_parent(b)
		g[b] = g[p] * local if p >= 0 else local
	return g

## Lowest point of the skinned body (model space, metres) for a pose.
func _lowest(g: Array[Transform3D], skin: Dictionary, to_model: Transform3D) -> float:
	var mats: Array[Transform3D] = []
	for i in (skin["binds"] as Array).size():
		var bb: int = skin["bind_bone"][i]
		mats.append(to_model * g[bb] * skin["binds"][i] if bb >= 0 else to_model)
	var verts: PackedVector3Array = skin["verts"]
	var bones: PackedInt32Array = skin["bones"]
	var weights: PackedFloat32Array = skin["weights"]
	var low := INF
	for i in verts.size():
		var v := verts[i]
		var y := 0.0
		for j in 4:
			var w := weights[i * 4 + j]
			if w > 0.0:
				y += w * (mats[bones[i * 4 + j]] * v).y
		low = minf(low, y)
	return low

## Raises the hips wherever the body would sink, and lays it on the floor at
## the end. Returns the metadata for the game.
func _ground(a: Animation, sk: Skeleton3D, skin: Dictionary, to_model: Transform3D) -> Dictionary:
	var tracks := {}
	for t in a.get_track_count():
		var bone := a.track_get_path(t).get_concatenated_subnames()
		tracks[("r:" if a.track_get_type(t) == Animation.TYPE_ROTATION_3D else "p:") + bone] = t
	var ht: int = tracks["p:Hips"]
	var hb := sk.find_bone("Hips")
	var steps := int(ceil(a.length * GROUND_FPS))
	var times := PackedFloat32Array()
	var low := PackedFloat32Array()
	var hip_h := PackedFloat32Array()
	for i in steps + 1:
		var tm := minf(i / GROUND_FPS, a.length)
		var g := _pose(a, sk, tm, tracks)
		times.append(tm)
		low.append(_lowest(g, skin, to_model))
		hip_h.append((to_model * g[hb].origin).y)
	var n := times.size()
	var lift_end := -low[n - 1]
	# The fall: from when the hips start to drop to when they settle.
	var t0 := times[n - 1] * 0.3
	var t1 := times[n - 1] * 0.8
	for i in n:
		if hip_h[i] < hip_h[0] - 0.15:
			t0 = times[i]
			break
	for i in range(n - 1, -1, -1):
		if absf(hip_h[i] - hip_h[n - 1]) > 0.05:
			t1 = times[mini(i + 1, n - 1)]
			break
	t1 = maxf(t1, t0 + 0.2)
	var c := PackedFloat32Array()
	for i in n:
		c.append(maxf(lift_end * smoothstep(t0, t1, times[i]), -low[i]))
	# Smooth the bumps, never letting the body back into the floor.
	var sm := c.duplicate()
	for i in range(1, n - 1):
		sm[i] = maxf((c[i - 1] + c[i] * 2.0 + c[i + 1]) / 4.0, -low[i])
	var max_lift := 0.0
	for v in sm:
		max_lift = maxf(max_lift, v)
	var up := to_model.basis.inverse() * Vector3.UP   # model metres -> skeleton units
	for k in a.track_get_key_count(ht):
		var tm := a.track_get_key_time(ht, k)
		var f := clampf(tm * GROUND_FPS, 0.0, n - 1.0)
		var i0 := int(floor(f))
		var i1 := mini(i0 + 1, n - 1)
		var lift := lerpf(sm[i0], sm[i1], f - i0)
		a.track_set_key_value(ht, k, (a.track_get_key_value(ht, k) as Vector3) + up * lift)
	# What the game needs: the body's key points at rest, the hips' path.
	var g_end := _pose(a, sk, a.length, tracks)
	var pts := PackedVector3Array()
	for b in KEY_BONES:
		var bi := sk.find_bone(b)
		if bi >= 0:
			pts.append(to_model * g_end[bi].origin)
	var travel := PackedVector3Array()
	var h0 := to_model * a.position_track_interpolate(ht, 0.0)
	for i in n:
		var p := to_model * a.position_track_interpolate(ht, times[i])
		travel.append(Vector3(times[i], p.x - h0.x, p.z - h0.z))
	var end_h := to_model * a.position_track_interpolate(ht, a.length)
	return {"end": pts, "travel": travel, "land": t1, "lift_end": lift_end, "max_lift": max_lift,
		"fall": Vector2(end_h.x - h0.x, end_h.z - h0.z)}
