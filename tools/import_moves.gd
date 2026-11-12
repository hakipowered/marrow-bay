extends SceneTree
## Builds res://assets/characters/<id>/<id>_moves.res: a survivor's own
## looping clips (so far Obcera's standing idle, so the two survivors don't
## stand in the same loop), from a Meshy rig of the base model:
## build_tmp/moves/<id>/<clip>.glb becomes the clip "moves/<clip>".
##
## Like the combat clips, the rig's bone rest is kept with the library and
## CombatClips.attach(..., "moves") retargets the clips at load time onto the
## base model or any outfit model. CharacterModel plays "moves/idle" in place
## of the shared "idle" when it exists.
##
## godot --headless --path . --script tools/import_moves.gd -- obcera

func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		_build(id)
	quit(0)

func _build(id: String) -> void:
	var dir := "res://build_tmp/moves/%s" % id
	var lib := AnimationLibrary.new()
	var rest_q := {}
	var rest_o := {}
	var parents := {}
	var hip_y := 0.0
	for fn in DirAccess.get_files_at(dir):
		if fn.get_extension() != "glb":
			continue
		var clip := fn.get_basename()
		var scene: Node = (load("%s/%s" % [dir, fn]) as PackedScene).instantiate()
		root.add_child(scene)
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		if rest_q.is_empty():
			for i in sk.get_bone_count():
				var n := sk.get_bone_name(i)
				rest_q[n] = sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
				rest_o[n] = sk.get_bone_rest(i).origin
				parents[n] = sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else ""
			hip_y = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var src: Animation = null
		for n in ap.get_animation_list():
			if n != "RESET":
				src = ap.get_animation(n)
				break
		var anim: Animation = src.duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := anim.track_get_path(t).get_concatenated_subnames()
			if anim.track_get_type(t) == Animation.TYPE_SCALE_3D or bone == "":
				anim.remove_track(t)
				continue
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
			# The hips keep their sway but stay centred on the capsule.
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
				var n_keys := anim.track_get_key_count(t)
				var mean := Vector3.ZERO
				for k in n_keys:
					mean += anim.track_get_key_value(t, k)
				mean /= maxf(n_keys, 1)
				var home: Vector3 = rest_o["Hips"]
				for k in n_keys:
					var v: Vector3 = anim.track_get_key_value(t, k)
					anim.track_set_key_value(t, k, Vector3(home.x + v.x - mean.x, v.y, home.z + v.z - mean.z))
		lib.add_animation(clip, anim)
		print("  ", id, " ", clip, " len=", snappedf(anim.length, 0.01), " tracks=", anim.get_track_count())
		scene.queue_free()
	lib.set_meta("rest_q", rest_q)
	lib.set_meta("rest_o", rest_o)
	lib.set_meta("parents", parents)
	lib.set_meta("hip_y", hip_y)
	var out := "res://assets/characters/%s/%s_moves.res" % [id, id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("saved ", out, " ", error_string(err), " ", lib.get_animation_list())
