class_name Rain
## Rain over an outdoor area: lit falling streaks, splashes on the ground and
## the sound of the downpour. The wet look of the ground itself (puddles with
## drop ripples, darker streaked walls) is in the surface shader, turned on
## per room with the "puddles", "rain" and "wall_wet" looks.

const STREAK := preload("res://shaders/rain_streak.gdshader")
const SPLASH := preload("res://shaders/rain_splash.gdshader")
const SOUND := "res://assets/audio/sfx/rain_loop.ogg"
const FALL_SPEED := 15.0

## `top` is the local centre of the emitter (just under the sky), `extents`
## the half-size of the area. `sound` puts the rain loop at the area's centre.
static func add(parent: Node3D, top: Vector3, extents: Vector3, sound := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Rain"
	root.position = top
	parent.add_child(root)
	var area := extents.x * extents.z * 4.0

	var streaks := GPUParticles3D.new()
	streaks.amount = int(clampf(area * 5.5, 600.0, 3600.0))
	streaks.lifetime = (top.y + 0.5) / FALL_SPEED
	streaks.preprocess = streaks.lifetime
	streaks.fixed_fps = 0
	streaks.local_coords = false
	streaks.visibility_aabb = AABB(Vector3(-extents.x - 2, -top.y - 1, -extents.z - 2), Vector3(extents.x * 2 + 4, top.y + 2, extents.z * 2 + 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(extents.x, 0.3, extents.z)
	pm.direction = Vector3(0.12, -1, 0.04)
	pm.spread = 2.0
	pm.initial_velocity_min = FALL_SPEED * 0.9
	pm.initial_velocity_max = FALL_SPEED * 1.1
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	streaks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.6)
	var sm := ShaderMaterial.new()
	sm.shader = STREAK
	q.material = sm
	streaks.draw_pass_1 = q
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(streaks)

	var splashes := GPUParticles3D.new()
	splashes.amount = int(clampf(area * 0.9, 120.0, 700.0))
	splashes.lifetime = 0.32
	splashes.randomness = 0.5
	splashes.preprocess = 0.5
	splashes.local_coords = false
	splashes.position = Vector3(0, -top.y + 0.075, 0)
	splashes.visibility_aabb = AABB(Vector3(-extents.x - 1, -0.5, -extents.z - 1), Vector3(extents.x * 2 + 2, 1.0, extents.z * 2 + 2))
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(extents.x, 0.0, extents.z)
	spm.gravity = Vector3.ZERO
	spm.initial_velocity_min = 0.0
	spm.initial_velocity_max = 0.0
	spm.scale_min = 0.7
	spm.scale_max = 1.3
	splashes.process_material = spm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.17, 0.17)
	var ssm := ShaderMaterial.new()
	ssm.shader = SPLASH
	sq.material = ssm
	splashes.draw_pass_1 = sq
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(splashes)

	if sound and ResourceLoader.exists(SOUND):
		var a := AudioStreamPlayer3D.new()
		var st: AudioStream = load(SOUND)
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		a.stream = st
		a.position = Vector3(0, -top.y + 2.0, 0)
		a.unit_size = maxf(extents.x, extents.z) * 0.9
		a.max_distance = maxf(extents.x, extents.z) * 3.5
		a.volume_db = -4.0
		a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		a.autoplay = true
		root.add_child(a)
	return root
