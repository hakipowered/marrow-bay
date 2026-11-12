extends SceneTree
## Builds res://assets/characters/<id>/<id>_combat.res: the melee and throw
## clips, from Meshy rigs of the base models (build_tmp/melee/<id>/a0..a5.glb,
## preset ids 219, 240, 97, 237, 421, 89; see tools/weapons/README.md).
##
## Meshy re-rigged the model, so its bone rest differs a little from the
## shipped skeleton. The clips keep their own rest here (stored as library
## metadata) and CombatClips retargets them onto whatever skeleton wears them
## at load time: the base model or any outfit model.
##
## godot --headless --path . --script tools/weapons/import_combat_clips.gd -- zegan obcera

const CLIPS := {
	"a0": "slash",       # 219 Right_Hand_Sword_Slash
	"a1": "thrust",      # 240 Thrust_Slash
	"a2": "slash_back",  # 97 Left_Slash
	"a3": "chop",        # 237 Charged_Axe_Chop
	"a4": "throw",       # 421 Over_Shoulder_Throw
	"a5": "guard",       # 89 Combat_Stance
}
const LOOPING := ["guard"]
## The useful part of each Meshy clip, in seconds (picked from filmstrips:
## the slash wind-up and swing, the stab, the overhead chop after the crouched
## charge, and the over-shoulder throw without the lunge that follows it).
const TRIM := {
	"slash": [0.12, 1.2],
	"slash_back": [0.35, 1.55],
	"thrust": [1.25, 2.45],
	"chop": [3.45, 4.85],
	"throw": [2.45, 3.95],
}

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
		var path := "res://build_tmp/melee/%s/%s.glb" % [id, f]
		if not ResourceLoader.exists(path):
			printerr("missing ", path)
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
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
		var clip: String = CLIPS[f]
		var anim: Animation = _trim(src, TRIM[clip][0], TRIM[clip][1]) if TRIM.has(clip) else src.duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		# Tracks keep only the bone name; CombatClips points them at the
		# skeleton that plays them. Scale tracks are dropped (the body
		# sliders own bone scale).
		for t in range(anim.get_track_count() - 1, -1, -1):
			var tp := anim.track_get_path(t)
			var bone := tp.get_concatenated_subnames()
			if anim.track_get_type(t) == Animation.TYPE_SCALE_3D or bone == "":
				anim.remove_track(t)
				continue
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
			# In place and centred on the capsule: the player controller moves
			# the body. Some presets start mid-lunge (the stab is a metre
			# ahead), so the hips keep only their height.
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
				var home: Vector3 = rest_o["Hips"]
				for k in anim.track_get_key_count(t):
					var v: Vector3 = anim.track_get_key_value(t, k)
					anim.track_set_key_value(t, k, Vector3(home.x, v.y, home.z))
		lib.add_animation(clip, anim)
		print("  ", id, " ", clip, " len=", snappedf(anim.length, 0.01), " tracks=", anim.get_track_count())
		scene.queue_free()
	lib.set_meta("rest_q", rest_q)
	lib.set_meta("rest_o", rest_o)
	lib.set_meta("parents", parents)
	lib.set_meta("hip_y", hip_y)
	var out := "res://assets/characters/%s/%s_combat.res" % [id, id]
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("saved ", out, " ", error_string(err), " ", lib.get_animation_list())

## A copy of src covering [t0, t1], shifted to start at zero, with exact keys
## at both ends.
func _trim(src: Animation, t0: float, t1: float) -> Animation:
	var a := Animation.new()
	a.length = t1 - t0
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var nt := a.add_track(type)
		a.track_set_path(nt, src.track_get_path(t))
		a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		var times := [t0]
		for k in src.track_get_key_count(t):
			var kt := src.track_get_key_time(t, k)
			if kt > t0 + 0.001 and kt < t1 - 0.001:
				times.append(kt)
		times.append(t1)
		for kt in times:
			var v: Variant
			match type:
				Animation.TYPE_ROTATION_3D: v = src.rotation_track_interpolate(t, kt)
				Animation.TYPE_POSITION_3D: v = src.position_track_interpolate(t, kt)
				_: v = src.scale_track_interpolate(t, kt)
			a.track_insert_key(nt, kt - t0, v)
	return a
