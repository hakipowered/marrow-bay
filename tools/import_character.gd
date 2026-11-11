extends SceneTree
## Builds res://assets/characters/<id>/<id>_anims.res from the rigged Meshy clips
## dropped in res://build_tmp/anims/<id>/ (walk.glb, run.glb, a0..a9.glb).
## Usage: godot --headless --path . --script tools/import_character.gd -- zegan obcera

const CLIPS := {
	"walk": "walk", "run": "run",
	"a0": "idle", "a1": "aim", "a2": "shoot_walk", "a3": "run_shoot", "a4": "reload",
	"a5": "hit", "a6": "knockdown", "a7": "stand_up", "a8": "call", "a9": "shout",
}
const LOOPING := ["walk", "run", "idle", "aim", "shoot_walk", "run_shoot"]
const IN_PLACE := ["walk", "run", "shoot_walk", "run_shoot"]

func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		_build(id)
	quit(0)

func _build(id: String) -> void:
	var base: Node = (load("res://assets/characters/%s/%s.glb" % [id, id]) as PackedScene).instantiate()
	root.add_child(base)
	var skel: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	var names := []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	print(id, " skeleton path: ", base.get_path_to(skel), " bones: ", names)
	var lib := AnimationLibrary.new()
	for f in CLIPS:
		var path := "res://build_tmp/anims/%s/%s.glb" % [id, f]
		if not ResourceLoader.exists(path):
			print("  missing ", path)
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var src: Animation = null
		for n in ap.get_animation_list():
			if n != "RESET":
				src = ap.get_animation(n)
				break
		var anim: Animation = src.duplicate(true)
		var clip: String = CLIPS[f]
		anim.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		# Retarget track paths so they resolve from the base model's AnimationPlayer root.
		var ap_root: Node = ap.get_node(ap.root_node)
		for t in anim.get_track_count():
			var tp := anim.track_get_path(t)
			var target := ap_root.get_node_or_null(NodePath(str(tp).get_slice(":", 0)))
			if target == null:
				continue
			var rel := scene.get_path_to(target)
			anim.track_set_path(t, NodePath("%s:%s" % [rel, tp.get_concatenated_subnames()]))
			if clip in IN_PLACE and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var bone := tp.get_concatenated_subnames()
				if bone.to_lower().contains("hip") or bone.to_lower().contains("root") or bone.to_lower().contains("pelvis"):
					var first: Vector3 = anim.track_get_key_value(t, 0)
					for k in anim.track_get_key_count(t):
						var v: Vector3 = anim.track_get_key_value(t, k)
						anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
		lib.add_animation(clip, anim)
		print("  ", clip, " len=", snappedf(anim.length, 0.01), " tracks=", anim.get_track_count(), " from ", ap.get_animation_list())
		scene.free()
	ResourceSaver.save(lib, "res://assets/characters/%s/%s_anims.res" % [id, id])
	print("saved ", id, " anims: ", lib.get_animation_list())
	base.queue_free()
