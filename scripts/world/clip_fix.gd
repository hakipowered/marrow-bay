class_name ClipFix
## Runtime fixes for the rigged Meshy clips, applied once per loaded library.
##
## The "hit" clip in the Meshy set is a stagger that walks the hips about a
## metre sideways and never comes back. On a body whose position is driven by
## the game (the survivors and the infected) that reads as the mesh sliding
## off on its own while the character keeps moving, then snapping back. Here
## the hips keep their height and sway but stay over the feet.

const IN_PLACE := ["hit"]

static func fix_library(lib: AnimationLibrary) -> void:
	if lib == null or lib.has_meta("clip_fix"):
		return
	lib.set_meta("clip_fix", true)
	for clip in IN_PLACE:
		if lib.has_animation(clip):
			in_place(lib.get_animation(clip))

## Pins the hips' horizontal position to the first frame.
static func in_place(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone := anim.track_get_path(t).get_concatenated_subnames().to_lower()
		if not (bone.contains("hip") or bone.contains("pelvis") or bone == "root"):
			continue
		if anim.track_get_key_count(t) == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
