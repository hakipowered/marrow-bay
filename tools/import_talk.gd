extends SceneTree
## Builds res://assets/characters/<id>/<id>_talk.res: the acting clips the
## story scenes use (talking with the hands, listening, sitting in a chair,
## standing up and sitting down, handing something over), from Meshy rigs of
## each character's base model with animation presets. The Meshy jobs and the
## preset ids are in the project files (story-scenes/model_jobs.txt); each
## clip GLB goes to build_tmp/talk/<id>/<clip>.glb, then:
##
##   godot --headless --path . --script tools/import_talk.gd -- hardass zegan obcera
##
## Like the "moves" library, the rig's bone rest is kept as metadata and
## CombatClips.attach(..., "talk") retargets the clips onto whatever skeleton
## plays them (the story actor, the survivors' base model, every outfit).
## Clips play as "talk/<clip>".
##
## Where the hips go matters for acting clips, so each clip says how they are
## placed (the actor's origin is the spot they stand on):
##   standing clips start right over the origin and keep their sway;
##   "sit_to_stand" ends standing on the origin, "stand_to_sit" starts there;
##   the seated loops all put the hips where "stand_to_sit" ends, so the
##   chair sits behind the mark (SEAT_BACK) and every seated clip uses it.
## MIRROR clips are played with left and right swapped (Hardass's bitten hand
## is his right; Meshy's preset pulls back the left).

## Clips that loop. Everything else plays once.
const LOOPS := ["sit_idle", "sit_talk", "sit_arms_crossed", "sit_head_back", "listen", "idle", "talk_angry"]
const SEATED := ["sit_idle", "sit_talk", "sit_arms_crossed", "sit_head_back", "sit_drink"]
## Clips not worth shipping (walk off, or not used by any scene).
const SKIP := ["catch_breath", "chat", "sit_drink", "idle5", "idle12", "scratch_head"]
## Clip files shipped under another name: Hardass's own standing loop is
## "talk/idle", which StoryActor plays in place of the shared idle.
const RENAME := {"idle9": "idle"}
const MIRROR := {"hardass": ["hand_pull"]}
## Clips that walk away from the mark: the hips stay on it (the story script
## moves the actor instead) but keep their bob and sway.
const PIN_XZ := ["hand_pull", "agree"]
const FPS := 30.0

func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		_build(id)
	quit(0)

func _build(id: String) -> void:
	var dir := "res://build_tmp/talk/%s" % id
	var lib := AnimationLibrary.new()
	var rest_q := {}
	var rest_o := {}
	var parents := {}
	var hip_y := 0.0
	var raw := {}
	var sk: Skeleton3D = null
	for fn in DirAccess.get_files_at(dir):
		if fn.get_extension() != "glb" or fn.get_basename() in SKIP:
			continue
		var clip: String = RENAME.get(fn.get_basename(), fn.get_basename())
		var scene: Node = (load("%s/%s" % [dir, fn]) as PackedScene).instantiate()
		root.add_child(scene)
		var s: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		if rest_q.is_empty():
			for i in s.get_bone_count():
				var n := s.get_bone_name(i)
				rest_q[n] = s.get_bone_global_rest(i).basis.get_rotation_quaternion()
				rest_o[n] = s.get_bone_rest(i).origin
				parents[n] = s.get_bone_name(s.get_bone_parent(i)) if s.get_bone_parent(i) >= 0 else ""
			hip_y = s.get_bone_global_rest(s.find_bone("Hips")).origin.y
			sk = s.duplicate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():
			if n != "RESET":
				raw[clip] = ap.get_animation(n).duplicate(true)
				break
		scene.queue_free()
	if raw.is_empty():
		push_error("no clips in " + dir)
		return
	var home: Vector3 = rest_o["Hips"]
	for clip in raw:
		var anim: Animation = raw[clip]
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := anim.track_get_path(t).get_concatenated_subnames()
			if anim.track_get_type(t) == Animation.TYPE_SCALE_3D or bone == "":
				anim.remove_track(t)
				continue
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
		if clip in MIRROR.get(id, []):
			anim = _mirrored(anim, sk, rest_q, parents)
		anim.loop_mode = Animation.LOOP_LINEAR if clip in LOOPS else Animation.LOOP_NONE
		raw[clip] = anim
	# Where the seated hips go: the end of sitting down, with that clip's
	# start moved onto the mark.
	var seat := Vector3.ZERO
	if raw.has("stand_to_sit"):
		var a: Animation = raw["stand_to_sit"]
		var ht := _hip_track(a)
		seat = a.position_track_interpolate(ht, a.length) - a.position_track_interpolate(ht, 0.0)
		seat.y = 0.0
		lib.set_meta("seat_back", Vector3(seat.x, 0, seat.z) * 0.01)
	for clip in raw:
		var anim: Animation = raw[clip]
		var ht := _hip_track(anim)
		if ht >= 0:
			var off := Vector3.ZERO
			var first: Vector3 = anim.position_track_interpolate(ht, 0.0)
			var last: Vector3 = anim.position_track_interpolate(ht, anim.length)
			if clip == "sit_to_stand":
				off = Vector3(home.x - last.x, 0, home.z - last.z)
			elif clip in SEATED:
				var mean := Vector3.ZERO
				for k in anim.track_get_key_count(ht):
					mean += anim.track_get_key_value(ht, k)
				mean /= maxf(anim.track_get_key_count(ht), 1)
				off = Vector3(home.x + seat.x - mean.x, 0, home.z + seat.z - mean.z)
			else:
				off = Vector3(home.x - first.x, 0, home.z - first.z)
			for k in anim.track_get_key_count(ht):
				var v: Vector3 = anim.track_get_key_value(ht, k) + off
				if clip in PIN_XZ:
					# Keep the bob, lose the travel: ease the drift back in.
					var drift := Vector3(v.x - home.x, 0, v.z - home.z)
					v -= drift * 0.85
				anim.track_set_key_value(ht, k, v)
		lib.add_animation(clip, anim)
		print("  ", id, " ", clip, " len=", snappedf(anim.length, 0.01), " loop=", anim.loop_mode != Animation.LOOP_NONE, " tracks=", anim.get_track_count())
	lib.set_meta("rest_q", rest_q)
	lib.set_meta("rest_o", rest_o)
	lib.set_meta("parents", parents)
	lib.set_meta("hip_y", hip_y)
	var out := "res://assets/characters/%s/%s_talk.res" % [id, id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("saved ", out, " ", error_string(err), " ", lib.get_animation_list(), " seat_back=", lib.get_meta("seat_back", Vector3.ZERO))
	if sk:
		sk.free()

func _hip_track(a: Animation) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and a.track_get_path(t).get_concatenated_subnames() == "Hips":
			return t
	return -1

static func _mirror_name(n: String) -> String:
	if n.begins_with("Left"):
		return "Right" + n.substr(4)
	if n.begins_with("Right"):
		return "Left" + n.substr(5)
	return n

## A reflection through the body's centre plane (skeleton X): each bone turns
## in the world the way its opposite turned, reflected, measured from the rest
## pose so the two sides' own bone axes don't matter.
func _mirrored(src: Animation, sk: Skeleton3D, rest_q: Dictionary, parents: Dictionary) -> Animation:
	var out := Animation.new()
	out.length = src.length
	var rot := {}
	var hip_t := -1
	for t in src.get_track_count():
		var bone := src.track_get_path(t).get_concatenated_subnames()
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot[bone] = t
		elif src.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
			hip_t = t
	# Bones in parent-first order.
	var order: Array[String] = []
	for i in sk.get_bone_count():
		order.append(sk.get_bone_name(i))
	var new_tracks := {}
	for b in order:
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, NodePath("Skeleton3D:" + b))
		new_tracks[b] = nt
	var hip_nt := -1
	if hip_t >= 0:
		hip_nt = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hip_nt, NodePath("Skeleton3D:Hips"))
	var frames := int(ceil(src.length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, src.length)
		# Source global rotations at this time.
		var g := {}
		for b in order:
			var bi := sk.find_bone(b)
			var local: Quaternion = src.rotation_track_interpolate(rot[b], time) if rot.has(b) else sk.get_bone_rest(bi).basis.get_rotation_quaternion()
			var p: String = parents[b]
			g[b] = (g[p] * local) if p != "" else local
		# Mirrored global rotations, then back to local.
		var gm := {}
		for b in order:
			var srcb := _mirror_name(b)
			if not g.has(srcb):
				srcb = b
			var d: Quaternion = g[srcb] * (rest_q[srcb] as Quaternion).inverse()
			var dm := Quaternion(d.x, -d.y, -d.z, d.w)
			gm[b] = dm * (rest_q[b] as Quaternion)
		for b in order:
			var p: String = parents[b]
			var local: Quaternion = ((gm[p] as Quaternion).inverse() * gm[b]) if p != "" else gm[b]
			out.rotation_track_insert_key(new_tracks[b], time, local.normalized())
		if hip_nt >= 0:
			var v: Vector3 = src.position_track_interpolate(hip_t, time)
			out.position_track_insert_key(hip_nt, time, Vector3(-v.x, v.y, v.z))
	return out
