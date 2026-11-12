extends Node
## Positional sound effects. Looks for res://assets/audio/sfx/<id>.ogg, then
## <fallback>.ogg, and supports numbered variants (<id>_1.ogg, <id>_2.ogg...)
## so repeated sounds (groans, footsteps, shots) don't loop identically.

var _cache: Dictionary = {}

func _variants(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out := []
	var base := "res://assets/audio/sfx/%s" % id
	if ResourceLoader.exists(base + ".ogg"):
		out.append(load(base + ".ogg"))
	for i in range(1, 9):
		var p := "%s_%d.ogg" % [base, i]
		if ResourceLoader.exists(p):
			out.append(load(p))
	_cache[id] = out
	return out

func play_at(id: String, pos: Vector3, fallback := "", volume_db := 0.0, unit := 10.0) -> AudioStreamPlayer3D:
	var v := _variants(id)
	if v.is_empty() and fallback != "":
		v = _variants(fallback)
	if v.is_empty() or get_tree().current_scene == null:
		return null
	var a := AudioStreamPlayer3D.new()
	a.stream = v.pick_random()
	a.volume_db = volume_db
	a.unit_size = unit
	a.pitch_scale = randf_range(0.93, 1.07)
	a.bus = "SFX"
	get_tree().current_scene.add_child(a)
	a.global_position = pos
	a.play()
	a.finished.connect(a.queue_free)
	return a

func attach(id: String, parent: Node3D, volume_db := 0.0, unit := 8.0) -> AudioStreamPlayer3D:
	var v := _variants(id)
	if v.is_empty():
		return null
	var a := AudioStreamPlayer3D.new()
	a.stream = v.pick_random()
	a.volume_db = volume_db
	a.unit_size = unit
	a.pitch_scale = randf_range(0.9, 1.1)
	a.bus = "SFX"
	parent.add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
	return a

## Interface sounds (bag open, select, combine). Not positional, and they
## play while the game is paused.
func ui(id: String, volume_db := -6.0) -> void:
	var v := _variants(id)
	if v.is_empty():
		return
	var a := AudioStreamPlayer.new()
	a.stream = v.pick_random()
	a.volume_db = volume_db
	a.bus = "SFX"
	a.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
