extends SceneTree
## Builds res://assets/characters/<id>/<id>_roll.res: whole-body moves for
## the survivors (the dodge roll), from Meshy rigs of the base models with
## animation preset 159 Roll_Dodge_1 (a dive roll out of a run that comes up
## running). Download the clip GLB to build_tmp/roll/<id>/r1.glb (job ids in
## the project files, weapons/model_jobs.txt), then:
##
##   godot --headless --path . --script tools/import_move_clips.gd -- zegan obcera
##
## Like the melee clips, the library keeps the rig's bone rest as metadata and
## CombatClips merges it into the "combat" library, retargeted onto whichever
## skeleton plays it (every outfit). (<id>_moves.res is a different library:
## a survivor's own loops, tools/import_moves.gd.)
## The hips are pinned in place; how far the roll carries the body forward
## over time is kept as metadata ("travel", seconds -> metres) so the player
## controller can move the capsule along the same curve.

const CLIPS := {"r1": "roll"}

func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		_build(id)
	quit(0)

func _build(id: String) -> void:
	var lib := AnimationLibrary.new()
	var rest_q := {}
	var rest_o := {}
	var parents := {}
	var hip_y := 0.0
	for f in CLIPS:
		var path := "res://build_tmp/roll/%s/%s.glb" % [id, f]
		if not ResourceLoader.exists(path):
			printerr("missing ", path)
			continue
		var scene: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var unit := 1.0   # skeleton units -> metres (the armature is scaled 0.01)
		var up: Node = sk
		while up != null and up != root:
			if up is Node3D:
				unit *= (up as Node3D).scale.y
			up = up.get_parent()
		if rest_q.is_empty():
			for i in sk.get_bone_count():
				var n := sk.get_bone_name(i)
				rest_q[n] = sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
				rest_o[n] = sk.get_bone_rest(i).origin
				parents[n] = sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else ""
			hip_y = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = null
		for n in ap.get_animation_list():
			if n != "RESET":
				anim = ap.get_animation(n).duplicate(true)
				break
		var clip: String = CLIPS[f]
		anim.loop_mode = Animation.LOOP_NONE
		var travel := PackedVector2Array()
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := anim.track_get_path(t).get_concatenated_subnames()
			if anim.track_get_type(t) == Animation.TYPE_SCALE_3D or bone == "":
				anim.remove_track(t)
				continue
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
				var z0: float = anim.position_track_interpolate(t, 0.0).z
				var steps := int(ceil(anim.length * 30.0))
				for i in steps + 1:
					var tm := anim.length * i / steps
					travel.append(Vector2(tm, (anim.position_track_interpolate(t, tm).z - z0) * unit))
				var home: Vector3 = rest_o["Hips"]
				for k in anim.track_get_key_count(t):
					var v: Vector3 = anim.track_get_key_value(t, k)
					anim.track_set_key_value(t, k, Vector3(home.x, v.y, home.z))
		lib.add_animation(clip, anim)
		lib.set_meta("travel_" + clip, travel)
		print("  ", id, " ", clip, " len=", snappedf(anim.length, 0.01), " travel=", snappedf(travel[travel.size() - 1].y, 0.01), " m tracks=", anim.get_track_count())
		scene.queue_free()
	lib.set_meta("rest_q", rest_q)
	lib.set_meta("rest_o", rest_o)
	lib.set_meta("parents", parents)
	lib.set_meta("hip_y", hip_y)
	var out := "res://assets/characters/%s/%s_roll.res" % [id, id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("saved ", out, " ", error_string(err), " ", lib.get_animation_list())
