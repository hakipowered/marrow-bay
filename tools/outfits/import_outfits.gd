extends SceneTree
## Builds each outfit's clip library from the base character's clips.
##
## Outfit models are rigged by Meshy with the same bone names as the base
## model but their own bone rest (shoulders a little higher, arms at a
## slightly different angle...). Every rotation key is retargeted so the
## bone turns by the same amount in the world as on the base model:
##   q_out = Gout(parent)^-1 * Gbase(parent) * q_base * Gbase(bone)^-1 * Gout(bone)
## (G = the bone's global rest rotation). Position keys keep their offset
## from rest, scaled by the hip height. The body shaping centres are moved
## onto the outfit's skeleton the same way and stored as library metadata.
##
## godot --headless --path . --script tools/outfits/import_outfits.gd -- [character:outfit ...]
## With no arguments it does every outfit model found under
## res://assets/characters/<character>/outfits/.

func _initialize() -> void:
	var wanted := OS.get_cmdline_user_args()
	if wanted.is_empty():
		for c in ["zegan", "obcera"]:
			var d := DirAccess.open("res://assets/characters/%s/outfits" % c)
			if d:
				for o in d.get_directories():
					wanted.append("%s:%s" % [c, o])
	var failed := false
	for w in wanted:
		if not _build(w.get_slice(":", 0), w.get_slice(":", 1)):
			failed = true
	quit(1 if failed else 0)

func _skeleton(scene: Node) -> Skeleton3D:
	var all := scene.find_children("*", "Skeleton3D", true, false)
	return all[0] if not all.is_empty() else null

func _build(character: String, id: String) -> bool:
	var base: Node = (load("res://assets/characters/%s/%s.glb" % [character, character]) as PackedScene).instantiate()
	var out_path := "res://assets/characters/%s/outfits/%s/%s.glb" % [character, id, id]
	if not ResourceLoader.exists(out_path):
		printerr("missing ", out_path)
		return false
	var fit: Node = (load(out_path) as PackedScene).instantiate()
	root.add_child(base)
	root.add_child(fit)
	var sb := _skeleton(base)
	var so := _skeleton(fit)
	var ok := true
	for i in sb.get_bone_count():
		if so.find_bone(sb.get_bone_name(i)) < 0:
			printerr(id, ": outfit skeleton has no bone ", sb.get_bone_name(i))
			ok = false
	if not ok:
		base.free()
		fit.free()
		return false
	var skel_path := str(fit.get_path_to(so))
	var src: AnimationLibrary = load("res://assets/characters/%s/%s_anims.res" % [character, character])
	var lib := AnimationLibrary.new()
	var hip_b := sb.get_bone_global_rest(sb.find_bone("Hips")).origin.y
	var hip_o := so.get_bone_global_rest(so.find_bone("Hips")).origin.y
	var ratio := hip_o / hip_b if hip_b > 0.0 else 1.0
	for clip in src.get_animation_list():
		var a: Animation = src.get_animation(clip).duplicate(true)
		for t in a.get_track_count():
			var tp := a.track_get_path(t)
			var bone_name := tp.get_concatenated_subnames()
			a.track_set_path(t, NodePath("%s:%s" % [skel_path, bone_name]))
			var bb := sb.find_bone(bone_name)
			var bo := so.find_bone(bone_name)
			if bb < 0 or bo < 0:
				continue
			var pb := sb.get_bone_parent(bb)
			var po := so.get_bone_parent(bo)
			var gb := sb.get_bone_global_rest(bb).basis.get_rotation_quaternion()
			var go := so.get_bone_global_rest(bo).basis.get_rotation_quaternion()
			var gpb := sb.get_bone_global_rest(pb).basis.get_rotation_quaternion() if pb >= 0 else Quaternion.IDENTITY
			var gpo := so.get_bone_global_rest(po).basis.get_rotation_quaternion() if po >= 0 else Quaternion.IDENTITY
			var pre := gpo.inverse() * gpb
			var post := gb.inverse() * go
			match a.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					for k in a.track_get_key_count(t):
						var q: Quaternion = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, (pre * q * post).normalized())
				Animation.TYPE_POSITION_3D:
					var rb := sb.get_bone_rest(bb).origin
					var ro := so.get_bone_rest(bo).origin
					for k in a.track_get_key_count(t):
						var p: Vector3 = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, ro + pre * ((p - rb) * ratio))
		lib.add_animation(clip, a)
	# Body shaping centres, carried from the base bone to the outfit bone.
	var centers := []
	for def in CharacterModel.REGIONS.get(character, []):
		var bb := sb.find_bone(def["bone"])
		var bo := so.find_bone(def["bone"])
		centers.append(so.get_bone_global_rest(bo) * (sb.get_bone_global_rest(bb).affine_inverse() * def["c"]))
	lib.set_meta("region_centers", centers)
	var save_path := "res://assets/characters/%s/outfits/%s/%s_anims.res" % [character, id, id]
	var err := ResourceSaver.save(lib, save_path, ResourceSaver.FLAG_COMPRESS)
	print("%s:%s  %d clips  hip ratio %.3f  -> %s (%s)" % [character, id, lib.get_animation_list().size(), ratio, save_path, error_string(err)])
	base.free()
	fit.free()
	return err == OK
