class_name Player
extends CharacterBody3D
## Third-person over-the-shoulder survivor. Each player's own phone simulates
## its movement (authority = owning peer); position/aim sync to the partner.
## Damage to enemies is resolved on the host.

signal health_changed(hp: float, max_hp: float)
signal weapon_changed(id: String)
signal ammo_changed(in_mag: int, reserve: int)
signal interact_prompt(text: String)
signal inventory_changed
signal died

const WALK_SPEED := 2.0
const RUN_SPEED := 4.0
const AIM_SPEED := 1.7   # walking while aiming (and shooting) still keeps pace
const GRAVITY := 18.0
const SHOULDER_OFFSET := Vector3(0.55, 1.55, 0.0)
const CAM_DIST := 2.4
const CAM_DIST_AIM := 1.15
const CAM_DIST_GUARD := 1.9

@export var peer_id := 1
@export var character := "zegan"

var max_hp := 100.0
var hp := 100.0
var inventory := Inventory.new()
var move_input := Vector2.ZERO    # from virtual stick / WASD
var look_delta := Vector2.ZERO    # accumulated swipe
var aiming := false
var running := false
var fire_held := false
var yaw := 0.0
var pitch := -0.1
var _cooldown := 0.0
var _reloading := 0.0
var _burst_left := 0
var _focus: Node = null
var _prompt_text := ""   # what the interact prompt shows now
var downed := false
var pinned := false
var pinned_by: Node = null
var slowed_for := 0.0
var _burn_t := 0.0
var _struggle := 0
var _downed_t := 0.0
const REVIVE_WINDOW := 30.0
var rescue_area: Area3D
## Set by Cutscenes while a scene plays: no moving, aiming or shooting.
var input_locked := false
## Set by a story scene that is animating this body itself (standing up from
## the wreck, a gesture): the usual idle/walk playback leaves it alone.
var cutscene_pose := false
## A chore at a machine (cranking the Undercroft generator, "crank"): she
## stays put, plays that clip with the weapon put away and the camera free.
## Moving the stick, rolling, a real blow or going down stops it.
var working := ""
signal work_stopped

# Synced to the partner.
@export var sync_yaw := 0.0
@export var sync_pitch := 0.0
@export var sync_aiming := false
@export var sync_anim := "idle"
@export var sync_speed := 0.0   # real ground speed, so the partner's legs match too
var dead := false               # bled out / killed: the game-over sequence is running
@export var sync_weapon := ""
## Dodge roll: a dive along the stick (or the way she faces) that carries her
## ROLL_DIST metres in about a second and comes up running. Blows pass
## through her for the first ROLL_IFRAMES of it, it can be started out of a
## flinch, and it is how she breaks out of a crowd.
const ROLL_DIST := 3.4
const ROLL_PLAYBACK := CharacterModel.ROLL_PLAYBACK
const ROLL_IFRAMES := 0.7
var rolling := false
@export var dodging := false   # inside the roll's invulnerable part (the host's zombies check it)
var _roll_t := 0.0
var _roll_dir := Vector3.ZERO
var _roll_cd := 0.0
var _roll_key := false

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var body: Node3D
var model: CharacterModel
var flashlight: SpotLight3D
## Render layer of the survivor's own meshes (the host's survivor on layer
## 11, the partner's on 12): lit and seen as usual, but left out of her own
## chest lamp's shadows. A mesh casts into a light's shadow when any of its
## layers is in the light's caster mask, so her meshes are on this layer
## only. The partner's body still casts into her beam.
const SELF_LAYER := 1 << 10
var self_layer := SELF_LAYER
var _tag_t := 0.0
const LAMP_ENERGY := 3.4
const LAMP_RANGE := 22.0
## Within this distance a surface straight ahead dims the lamp (down to
## LAMP_NEAR_DIM of full), the way eyes adjust to a wall lit up close.
const LAMP_NEAR := 2.6
const LAMP_NEAR_DIM := 0.45
## How far the beam may turn from her chest toward where the camera looks.
const LAMP_TURN := 0.6
## Light the beam throws back off whatever it lands on (see _aim_flashlight).
const BOUNCE_REACH := 7.0
const BOUNCE_ENERGY := 1.3
var lamp_bounce: SpotLight3D
## The lamp's aim relative to her body (pitch, yaw), so the partner's phone
## points her beam the same way.
@export var sync_lamp := Vector2(-0.25, 0.0)
var muzzle: Node3D
var interact_ray: RayCast3D
var held: HeldWeapon

## Knife combo and hatchet chop: [clip, playback speed, clip time when the
## blade meets the target]. The contact times are where the hand sweeps
## through the front of the body at full speed (traced from the clips), so the
## hit, the blood and the sound land on the frame the blade does.
const MELEE_MOVES := {
	"knife": [["slash", 1.6, 0.46], ["slash_back", 1.6, 0.46], ["thrust", 1.5, 0.19]],
	"hatchet": [["chop", 1.25, 1.0]],
}
const THROW_SPEED := 1.3
const THROW_RELEASE := 0.74   # seconds into the throw clip at that speed
var _swing_t := -1.0      # until the current swing lands
var _hip_t := 0.0         # gun raised from the hip after FIRE without AIM
const HIP_HOLD := 0.7     # how long the gun stays up after a hip shot
var _throw_t := -1.0      # until the grenade leaves the hand
var _attack_lock := 0.0   # feet planted while swinging or throwing
var _hit_stun := 0.0      # a beat after taking a hit: the feet stop with the flinch
var _knock := Vector3.ZERO   # shove from the blow, decays fast
var _shake := 0.0
var _combo := 0
var _combo_window := 0.0
var _lock_target: Node3D = null
var _face_yaw := 0.0
var _inv_dirty := false
var _inv_sync_t := 0.0

func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("players")
	# Gesture when this survivor calls out: wave over, or a full-body shout.
	CallOuts.callout_played.connect(func(speaker: int, _c: String, _id: String, _t: String, scream: bool):
		if speaker == peer_id and model:
			model.play_once("shout" if scream else "call", 0.15, 2.2))
	Cheats.changed.connect(_on_cheat)
	collision_layer = 2
	collision_mask = 1 | 4 | Door.BARS_LAYER
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	shape.shape = cap
	shape.position.y = 0.89
	add_child(shape)

	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	model = CharacterModel.new()
	model.character = character
	model.customization = GameState.customization_by_peer.get(peer_id, GameState.default_customization(character))
	body.add_child(model)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.22, 1.4, -0.6)
	body.add_child(muzzle)

	# Chest lamp: a torch beam aimed at whatever is under the crosshair
	# (_lamp_aim, synced to the partner's phone as sync_lamp). The beam
	# pattern (assets/textures/fx/flashlight_cookie.png, drawn by
	# tools/fx/make_flashlight_cookie.py) is a real torch's: a bright hot spot,
	# a faint reflector ring and a wide dim spill that fades out softly, so
	# it reads as a beam, not a hard disc. It sits inside her chest (never
	# poking through a wall she's pressed against), her own body and gun
	# don't shadow it, it reaches well down a corridor (gentle falloff), and
	# it eases off on a wall right in front of her instead of blowing it out.
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.position = Vector3(0.1, 1.45, -0.12)
	flashlight.rotation.x = -0.25
	flashlight.spot_range = LAMP_RANGE
	flashlight.spot_angle = 38.0   # half-angle: a 76° cone, mostly soft spill
	flashlight.spot_attenuation = 0.35
	flashlight.spot_angle_attenuation = 1.5   # even across the cone; the pattern does the falloff
	flashlight.light_projector = preload("res://assets/textures/fx/flashlight_cookie.png")
	flashlight.light_energy = LAMP_ENERGY
	flashlight.light_specular = 0.6
	flashlight.light_color = Color(1.0, 0.95, 0.86)
	flashlight.shadow_enabled = true
	self_layer = SELF_LAYER if peer_id == 1 else SELF_LAYER << 1
	flashlight.shadow_caster_mask = 0xFFFFF & ~self_layer
	body.add_child(flashlight)
	# Bounce: a torch on a wall lights up the space around it too, her
	# included. A soft, shadowless light at the spot the beam lands on,
	# shining back out of that surface (so never through the wall into the
	# next room), strongest when the surface is close.
	lamp_bounce = SpotLight3D.new()
	lamp_bounce.name = "LampBounce"
	lamp_bounce.top_level = true
	lamp_bounce.spot_angle = 80.0
	lamp_bounce.spot_range = 5.0
	lamp_bounce.spot_attenuation = 1.0
	lamp_bounce.spot_angle_attenuation = 1.0
	lamp_bounce.light_energy = 0.0
	lamp_bounce.light_specular = 0.0
	lamp_bounce.light_color = Color(1.0, 0.9, 0.78)
	lamp_bounce.shadow_enabled = false
	lamp_bounce.visible = false
	add_child(lamp_bounce)
	model.outfit_loaded.connect(func(_o): _tag_self.call_deferred())

	pivot = Node3D.new()
	pivot.position = Vector3(0, SHOULDER_OFFSET.y, 0)
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = CAM_DIST
	spring.collision_mask = 1
	spring.margin = 0.15
	spring.position.x = SHOULDER_OFFSET.x
	var s := SphereShape3D.new()
	s.radius = 0.18
	spring.shape = s
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	spring.add_child(camera)

	held = HeldWeapon.new()
	held.name = "HeldWeapon"
	held.model = model
	add_child(held)

	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0, 0, -2.2)
	interact_ray.collision_mask = 16
	interact_ray.collide_with_areas = true
	# Pressed right up against a door she is inside its interact box; without
	# this the ray started inside it and found nothing until she stepped back.
	interact_ray.hit_from_inside = true
	interact_ray.position.y = 1.1
	body.add_child(interact_ray)

	rescue_area = Area3D.new()
	rescue_area.collision_layer = 0
	rescue_area.collision_mask = 0
	rescue_area.monitoring = false
	var rcs := CollisionShape3D.new()
	var rs := SphereShape3D.new()
	rs.radius = 0.8
	rcs.shape = rs
	rcs.position.y = 0.6
	rescue_area.add_child(rcs)
	rescue_area.set_script(preload("res://scripts/world/interact_proxy.gd"))
	rescue_area.target = self
	add_child(rescue_area)

	_setup_sync()
	inventory.from_dict(GameState.inventories.get(character, {}))
	inventory.changed.connect(func(): _inv_dirty = true; inventory_changed.emit())
	if not inventory.has_weapon(inventory.equipped):
		inventory.equipped = _fallback_weapon()
	_show_weapon(inventory.equipped)
	if is_multiplayer_authority():
		camera.make_current()
	else:
		camera.current = false

func _setup_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":sync_yaw", ":sync_pitch", ":sync_aiming", ":sync_anim", ":sync_speed", ":sync_weapon", ":downed", ":pinned", ":dodging", ":sync_lamp"]:
		cfg.add_property(NodePath(prop))
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 30.0
	add_child(sync)
	sync.set_multiplayer_authority(peer_id)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		if cutscene_pose:
			return
		body.rotation.y = lerp_angle(body.rotation.y, sync_yaw, 0.35)
		if sync_weapon != held.weapon_id:
			_show_weapon(sync_weapon)
		held.stowed = sync_anim in WORK_CLIPS
		_downed_t = _downed_t + delta if downed else 0.0
		model.move_speed = sync_speed
		model.play(sync_anim, sync_aiming)
		_aim_flashlight(delta, sync_lamp)
		return
	_sync_inventory(delta)
	rescue_area.collision_layer = 16 if (downed or pinned) else 0
	if _burn_t > 0:
		_burn_t -= delta
		if fmod(_burn_t, 0.5) < delta:
			apply_damage(3.0)
	slowed_for = max(slowed_for - delta, 0.0)
	_roll_cd = maxf(_roll_cd - delta, 0.0)
	if downed or pinned or input_locked:
		rolling = false
		dodging = false
	if downed:
		_downed_t += delta
		sync_anim = "downed"
		sync_speed = 0.0
		model.play("downed", false)
		_tick_death_cam(delta)
		if not dead and _downed_t > REVIVE_WINDOW:
			_die()
		return
	if pinned:
		velocity = Vector3.ZERO
		sync_anim = "hit"
		model.play("hit", false)
		return
	if input_locked:
		move_input = Vector2.ZERO
		look_delta = Vector2.ZERO
		fire_held = false
		aiming = false
		velocity = Vector3.ZERO
		sync_aiming = false
		sync_anim = "idle"
		if not cutscene_pose:
			model.play("idle", false)
		return
	if working != "":
		_tick_work(delta)
		return
	_read_keyboard()
	# Look
	yaw -= look_delta.x * 0.0045
	pitch = clamp(pitch - look_delta.y * 0.0035, -1.2, 0.9)
	look_delta = Vector2.ZERO
	pivot.rotation = Vector3(pitch, yaw, 0)
	# Guns zoom in over the shoulder. The knife guard and a grenade wind-up
	# stay wider, or the hand holding them drops out of the bottom of the shot.
	var gun_aim := aiming and (held == null or held.hold == "gun")
	var near := CAM_DIST_AIM if gun_aim else (CAM_DIST_GUARD if aiming else CAM_DIST)
	spring.spring_length = lerp(spring.spring_length, near, 10 * delta)
	camera.fov = lerp(camera.fov, 52.0 if gun_aim else (62.0 if aiming else 68.0), 10 * delta)

	if rolling:
		_tick_roll(delta)
		_tick_shake(delta)
		return
	# Move relative to camera
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := basis_y * Vector3(move_input.x, 0, move_input.y)
	var speed := AIM_SPEED if aiming else (RUN_SPEED if running else WALK_SPEED)
	_hip_t = maxf(_hip_t - delta, 0.0)
	if _hip_t > 0.0:
		speed = minf(speed, WALK_SPEED)   # no sprinting with the gun up
	if slowed_for > 0:
		speed *= 0.4
	if _attack_lock > 0.0:
		_attack_lock -= delta
		speed *= 0.12
	if _hit_stun > 0.0:
		_hit_stun -= delta
		speed *= 0.15
	if Cheats.on("noclip"):
		global_position += (pivot.global_transform.basis * Vector3(move_input.x, 0, move_input.y)) * RUN_SPEED * 2 * delta
		return
	velocity.x = dir.x * speed + _knock.x
	velocity.z = dir.z * speed + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_tick_shake(delta)

	if _attack_lock > 0.0:
		body.rotation.y = lerp_angle(body.rotation.y, _face_yaw, 22 * delta)
	elif aiming or fire_held or _hip_t > 0.0:
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 18 * delta)
	elif dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 10 * delta)

	sync_yaw = body.rotation.y
	sync_pitch = pitch
	var raised := aiming or _hip_t > 0.0
	sync_aiming = raised
	# The clip follows how fast she really moves (a wall, an ankle grab, a
	# flinch or the gun up all slow her), so she never runs on the spot or
	# glides; the clip's playback speed matches her ground speed too.
	var rv := get_real_velocity() - Vector3(_knock.x, 0.0, _knock.z)
	var gs := Vector2(rv.x, rv.z).length() if dir.length() > 0.1 else 0.0
	# Backing off with the gun up: the walk plays in reverse.
	var backing := raised and gs > 0.2 and (-body.global_transform.basis.z).dot(dir.normalized()) < -0.35
	sync_speed = -gs if backing else gs
	sync_anim = "run" if (gs > 2.8 and _hip_t <= 0.0) else ("walk" if gs > 0.2 else "idle")
	if _reloading > 0.0 and gs <= 0.2:
		sync_anim = "reload"
	model.move_speed = sync_speed
	model.play(sync_anim, raised)

	_tick_weapon(delta)
	_update_focus()
	sync_lamp = _lamp_aim()
	_aim_flashlight(delta, sync_lamp)

## Where her lamp points, relative to her body: at whatever is under the
## crosshair (so the beam lights what she's looking at and aiming at, not a
## spot beside her shoulder), turning at most LAMP_TURN from straight ahead
## and never up into the ceiling.
func _lamp_aim() -> Vector2:
	var space := get_world_3d().direct_space_state
	var eye := camera.global_position
	var look := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(eye, eye + look * 25.0, 1 | 4, [get_rid()])
	var hit := space.intersect_ray(q)
	var at: Vector3 = hit["position"] if not hit.is_empty() else eye + look * 25.0
	var local := body.global_basis.inverse() * (at - body.global_transform * flashlight.position)
	if local.length() < 0.3 or local.z > -0.2:
		# The crosshair is on her, beside her or behind her: straight ahead.
		return Vector2(clampf(pitch * 0.85 - 0.14, -1.0, 0.35), 0.0)
	local = local.normalized()
	return Vector2(clampf(asin(local.y), -1.0, 0.35), clampf(atan2(-local.x, -local.z), -LAMP_TURN, LAMP_TURN))

## Points the lamp (on both phones; the partner's follows the synced aim),
## eases it off when the beam lands on something right in front of her, and
## moves the bounce light to where the beam lands.
func _aim_flashlight(delta: float, aim: Vector2) -> void:
	var k := minf(12.0 * delta, 1.0)
	flashlight.rotation.x = lerp_angle(flashlight.rotation.x, aim.x, k)
	flashlight.rotation.y = lerp_angle(flashlight.rotation.y, aim.y, k)
	var bounce := 0.0
	if flashlight.visible and is_inside_tree():
		var from := flashlight.global_position
		var dir := -flashlight.global_basis.z
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * BOUNCE_REACH, 1 | 4, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var d: float = BOUNCE_REACH if hit.is_empty() else from.distance_to(hit["position"])
		var e := LAMP_ENERGY * lerpf(LAMP_NEAR_DIM, 1.0, smoothstep(0.25, LAMP_NEAR, d))
		flashlight.light_energy = lerpf(flashlight.light_energy, e, minf(8.0 * delta, 1.0))
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			bounce = BOUNCE_ENERGY * (1.0 - smoothstep(0.6, BOUNCE_REACH, d)) * clampf(-dir.dot(n), 0.3, 1.0)
			var p: Vector3 = hit["position"] + n * 0.1
			var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
			lamp_bounce.global_transform = Transform3D(Basis.looking_at(n, up), p)
	lamp_bounce.light_energy = lerpf(lamp_bounce.light_energy, bounce, minf(6.0 * delta, 1.0))
	lamp_bounce.visible = lamp_bounce.light_energy > 0.01
	_tag_t -= delta
	if _tag_t <= 0.0:
		_tag_t = 1.0
		_tag_self()

func _tag_self() -> void:
	# The gun in her hands lives under `held`, outside the body: tag it too,
	# or the barrel, pointing at the spot the beam lands on, throws a hard
	# wedge of shadow out of the middle of the beam.
	for root in [body, held]:
		if root == null:
			continue
		for n in root.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).layers = self_layer

## Starts a dodge roll (the HUD's ROLL button, Space on a keyboard).
func roll() -> void:
	if rolling or _roll_cd > 0.0 or downed or pinned or input_locked or cutscene_pose or dead:
		return
	if working != "":
		stop_work()
	if model._anim == null or not model._anim.has_animation("combat/roll"):
		return
	var d := Basis(Vector3.UP, yaw) * Vector3(move_input.x, 0, move_input.y)
	if d.length() < 0.2:
		d = -body.global_transform.basis.z
	_roll_dir = (d * Vector3(1, 0, 1)).normalized()
	body.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
	rolling = true
	dodging = true
	_roll_t = 0.0
	_hit_stun = 0.0
	_knock = Vector3.ZERO
	_attack_lock = 0.0
	fire_held = false
	Sfx.play_at("roll_whoosh", global_position + Vector3.UP, "", -5.0, 4.0)

func _tick_roll(delta: float) -> void:
	var anim := model._anim
	var length := anim.get_animation("combat/roll").length
	var total := CombatClips.travel(anim, "roll", length)
	var k := ROLL_DIST / total if total > 0.5 else 0.0
	var t0 := _roll_t * ROLL_PLAYBACK
	_roll_t += delta
	var t1 := minf(_roll_t * ROLL_PLAYBACK, length)
	var step := (CombatClips.travel(anim, "roll", t1) - CombatClips.travel(anim, "roll", t0)) * k
	if k == 0.0:
		step = ROLL_DIST / (length / ROLL_PLAYBACK) * delta
	velocity.x = _roll_dir.x * step / delta
	velocity.z = _roll_dir.z * step / delta
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	body.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
	sync_yaw = body.rotation.y
	sync_pitch = pitch
	sync_aiming = false
	sync_anim = "roll"
	sync_speed = 0.0
	model.play("roll", false)
	if t0 < length * 0.42 and t1 >= length * 0.42:
		Sfx.play_at("body_fall", global_position + Vector3.UP * 0.4, "", -9.0, 4.0)   # shoulder meets the floor
	dodging = t1 < length * ROLL_IFRAMES
	if t1 >= length - 0.06:
		rolling = false
		dodging = false
		_roll_cd = 0.25

## The clips that are chores (Player.working): the weapon is put away.
const WORK_CLIPS := ["crank"]

func start_work(clip: String, face_yaw: float) -> void:
	if downed or dead or rolling:
		return
	working = clip
	move_input = Vector2.ZERO
	aiming = false
	fire_held = false
	_reloading = 0.0
	body.rotation.y = face_yaw
	sync_yaw = face_yaw
	held.stowed = true

func stop_work() -> void:
	if working == "":
		return
	working = ""
	held.stowed = false
	sync_anim = "idle"
	work_stopped.emit()

func _tick_work(delta: float) -> void:
	_read_keyboard()
	if working == "":
		return   # rolled out of it
	yaw -= look_delta.x * 0.0045
	pitch = clamp(pitch - look_delta.y * 0.0035, -1.2, 0.9)
	look_delta = Vector2.ZERO
	pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = lerp(spring.spring_length, CAM_DIST, 10 * delta)
	camera.fov = lerp(camera.fov, 68.0, 10 * delta)
	velocity = Vector3.ZERO
	aiming = false
	fire_held = false
	sync_aiming = false
	sync_speed = 0.0
	sync_yaw = body.rotation.y
	sync_anim = working
	model.move_speed = 0.0
	model.play(working, false)
	_tick_shake(delta)
	sync_lamp = _lamp_aim()
	_aim_flashlight(delta, sync_lamp)
	if move_input.length() > 0.5:
		stop_work()

func _read_keyboard() -> void:
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	if space and not _roll_key:
		roll()
	_roll_key = space
	# Desktop testing; touch HUD writes the same fields.
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if k != Vector2.ZERO:
		move_input = k.normalized()
		running = Input.is_physical_key_pressed(KEY_SHIFT)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_delta += event.relative
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			fire_held = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: interact()
			KEY_R: reload()
			KEY_Q: CallOuts.call_partner(false)
			KEY_Z: CallOuts.call_partner(true)
			KEY_TAB, KEY_I:
				var hud := get_tree().get_first_node_in_group("hud")
				if hud and hud.has_method("toggle_inventory"):
					hud.toggle_inventory()
					get_viewport().set_input_as_handled()

# ---------- Weapons ----------

func weapon() -> Dictionary:
	return WeaponDB.WEAPONS.get(inventory.equipped, {})

func equip(id: String) -> void:
	if not inventory.has_weapon(id):
		return
	var changed := id != inventory.equipped
	inventory.equipped = id
	if not inventory.mag.has(id) and weapon().has("mag"):
		inventory.mag[id] = weapon()["mag"]
	_reloading = 0.0
	_burst_left = 0
	_show_weapon(id)
	if changed and is_inside_tree():
		if get_tree().paused:
			Sfx.ui("equip", -4.0)
		else:
			Sfx.play_at("equip", global_position + Vector3.UP, "", -6.0, 4.0)
	weapon_changed.emit(id)
	_emit_ammo()
	_inv_dirty = true

func _show_weapon(id: String) -> void:
	held.set_weapon(id)
	_tag_self.call_deferred()
	model.hold = held.hold if held.hold != "" else "gun"
	if is_multiplayer_authority():
		sync_weapon = id

## Something to hold when the equipped weapon is gone (thrown the last
## grenade, discarded the gun).
func _fallback_weapon() -> String:
	var list := inventory.weapon_list()
	for id in list:
		if ItemInfo.kind(id) == "weapon" and WeaponDB.WEAPONS[id]["kind"] != "melee":
			return id
	return list[0] if not list.is_empty() else ""

## HUD readout: rounds in the gun / rounds carried. Melee shows nothing
## (-1, -1); grenades show only how many are left (-1, n).
func _emit_ammo() -> void:
	_inv_dirty = true
	var w := weapon()
	match w.get("kind", ""):
		"melee", "":
			ammo_changed.emit(-1, -1)
		"throwable":
			ammo_changed.emit(-1, 99 if _free_reserve() else inventory.ammo_count(inventory.equipped))
		_:
			ammo_changed.emit(inventory.mag.get(inventory.equipped, 0), 99 if _free_reserve() else inventory.ammo_count(w.get("ammo", "")))

## The rocket launcher cheat puts the launcher in her hands (and takes it
## back when it's switched off, unless she really carries one).
func _on_cheat(cheat: String, value: bool) -> void:
	if cheat != "rocket_launcher" or not is_multiplayer_authority() or inventory == null:
		return
	if value:
		inventory.mag["rocket"] = WeaponDB.WEAPONS["rocket"]["mag"]
		equip("rocket")
	elif inventory.equipped == "rocket" and not inventory.has_weapon("rocket"):
		equip(_fallback_weapon())

## Reserve rounds that cost nothing: the infinite-ammo cheat, the rocket
## launcher cheat, and a weapon taken from the cheat arsenal that isn't in the
## bag. (Arsenal guns used to stop after one magazine, which for the crossbow,
## grenade launcher and rocket launcher is one shot, and arsenal grenades
## couldn't be thrown at all.)
func _free_reserve(id := "") -> bool:
	if id == "":
		id = inventory.equipped
	if Cheats.on("infinite_ammo") or (id == "rocket" and Cheats.on("rocket_launcher")):
		return true
	return Cheats.on("all_weapons") and inventory.count(id) == 0

## Shots that don't empty the magazine (no reloading at all).
func _endless_mag(id := "") -> bool:
	if id == "":
		id = inventory.equipped
	return Cheats.on("infinite_ammo") or (id == "rocket" and Cheats.on("rocket_launcher"))

func reload() -> void:
	var w := weapon()
	if not w.has("mag") or _reloading > 0:
		return
	var reserve: int = inventory.ammo_count(w["ammo"])
	if _free_reserve():
		reserve = 999
	if inventory.mag.get(inventory.equipped, 0) >= w["mag"] or reserve <= 0:
		return
	_reloading = 0.05 if Cheats.on("no_reload") else w["reload"]
	var snd := "reload_shell" if w.get("reload_per_shell", false) else ("reload_pistol" if w.get("slot") == "sidearm" else "reload_rifle")
	Sfx.play_at(snd, global_position + Vector3.UP, "", -3.0, 5.0)

func _finish_reload() -> void:
	var w := weapon()
	if not w.has("mag"):
		return
	var need: int = w["mag"] - inventory.mag.get(inventory.equipped, 0)
	if w.get("reload_per_shell", false):
		need = min(need, 1)
	var n: int = need if _free_reserve() else inventory.take_ammo(w["ammo"], need)
	inventory.mag[inventory.equipped] = inventory.mag.get(inventory.equipped, 0) + n
	_emit_ammo()
	if w.get("reload_per_shell", false) and inventory.mag[inventory.equipped] < w["mag"] and (_free_reserve() or inventory.ammo_count(w["ammo"]) > 0):
		_reloading = w["reload"]
		Sfx.play_at("reload_shell", global_position + Vector3.UP, "", -3.0, 5.0)

func _tick_weapon(delta: float) -> void:
	_cooldown -= delta
	_combo_window -= delta
	if _swing_t >= 0.0:
		_swing_t -= delta
		if _swing_t < 0.0:
			# The infected she swung at may be gone by the time the blade lands.
			Combat.melee_hit(self, inventory.equipped, _lock_target if is_instance_valid(_lock_target) else null)
	if _throw_t >= 0.0:
		_throw_t -= delta
		if _throw_t < 0.0:
			_release_throw()
	if _reloading > 0:
		_reloading -= delta
		if _reloading <= 0:
			_finish_reload()
		return
	var w := weapon()
	if w.is_empty():
		return
	var melee: bool = w["kind"] == "melee"
	# Without AIM a gun fires from the hip: the gun comes up, she turns to
	# where the camera looks, and the shot goes once she faces it.
	if fire_held and not aiming and not melee:
		_hip_t = HIP_HOLD
	var facing: bool = aiming or melee or absf(angle_difference(body.rotation.y, yaw)) < deg_to_rad(20.0)
	var wants: bool = fire_held and facing
	if _burst_left > 0 and _cooldown <= 0:
		_fire_once(w)
		_burst_left -= 1
		_cooldown = w["rate"] if _burst_left > 0 else w.get("burst_gap", w["rate"])
		return
	if not wants or _cooldown > 0:
		return
	if melee:
		_start_swing(w)
		fire_held = false
		return
	if w["kind"] == "throwable":
		_start_throw(w)
		fire_held = false
		return
	if inventory.mag.get(inventory.equipped, 0) <= 0:
		if inventory.ammo_count(w["ammo"]) <= 0 and not _free_reserve():
			Sfx.play_at("dry_fire", muzzle.global_position, "", -4.0, 4.0)
			_cooldown = 0.35
			fire_held = false
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("Out of ammo")
		else:
			reload()
		return
	_burst_left = w.get("burst", 1) - 1
	_fire_once(w)
	_cooldown = w["rate"]
	if not w.get("auto", false) and w.get("burst", 1) == 1:
		fire_held = false

func _fire_once(w: Dictionary) -> void:
	if inventory.mag.get(inventory.equipped, 0) <= 0:
		return
	if not _endless_mag():
		inventory.mag[inventory.equipped] -= 1
	_emit_ammo()
	var origin := camera.global_position
	var aim_dir := -camera.global_transform.basis.z
	# The amber dot is a promise: with it on a drum, the round goes in.
	var on_drum := _dot_on_explosive(origin, aim_dir)
	if not aiming and not on_drum:
		aim_dir = _hip_assist(origin, aim_dir)
	var shots := []
	var pellets: int = w.get("pellets", 1)
	for i in pellets:
		if i == 0 and (pellets > 1 or on_drum):
			# The middle of a shotgun's pattern goes right where the dot is,
			# so a drum (or a head) under the dot is always hit.
			shots.append(aim_dir)
			continue
		var spread := deg_to_rad(w.get("spread", 0.0)) * (1.0 if aiming else 2.0)
		var d := aim_dir.rotated(camera.global_transform.basis.x, randf_range(-spread, spread) * 0.5)
		d = d.rotated(camera.global_transform.basis.y, randf_range(-spread, spread) * 0.5)
		shots.append(d.normalized())
	var from := _muzzle_pos()
	held.fired(_recoil(w))
	Combat.fire(self, inventory.equipped, origin, shots, from)
	_rpc_action.rpc("shot", inventory.equipped, 1.0)

## Hip-fire on a phone: a shot within a few degrees of an infected's body
## bends onto it, so firing without aiming still lands. Aimed shots go
## exactly where the dot is.
##
## Explosives come first: with the dot on a drum the round goes into the
## drum, not the infected standing next to it (that's the moment to shoot
## it). A drum within a few degrees of the dot draws the shot too.
func _hip_assist(origin: Vector3, dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var dot := _dot_hit(origin, dir)
	var on_enemy: bool = not dot.is_empty() and dot.collider.has_meta("hit_zone")
	var best := dir
	var best_ang := deg_to_rad(7.0)
	for b in get_tree().get_nodes_in_group("breakables"):
		if on_enemy or b.broken or not b.explosive():
			continue
		var at: Vector3 = b.global_transform * b.center
		var ang := dir.angle_to(at - origin)
		if ang > deg_to_rad(4.0) or ang > best_ang or origin.distance_to(at) > 22.0:
			continue
		var lq := PhysicsRayQueryParameters3D.create(origin, at, Combat.HITBOX_MASK, [get_rid()])
		lq.collide_with_areas = true
		if Breakable.of(space.intersect_ray(lq).get("collider")) == b:
			best_ang = ang
			best = (at - origin).normalized()
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or z.get("state") in [Zombie.S.DEAD, Zombie.S.HIDDEN, Zombie.S.PLAY_DEAD]:
			continue
		var rough: Vector3 = z.global_position + Vector3.UP * 0.7 - origin
		if rough.length() > 23.0 or dir.angle_to(rough) > deg_to_rad(30.0):
			continue
		var to := _body_center(z) - origin
		if to.length() > 22.0:
			continue
		var ang := dir.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = to.normalized()
	return best

## The first thing a round fired along the camera line would hit.
func _dot_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0, Combat.HITBOX_MASK, [get_rid()])
	q.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(q)

## The crosshair dot is on a drum, gas bottle or fuel can that's still whole
## (the crosshair shows it amber).
func _dot_on_explosive(origin: Vector3, dir: Vector3) -> bool:
	var b := Breakable.of(_dot_hit(origin, dir).get("collider"))
	return b != null and not b.broken and b.explosive()

## The middle of an infected's body: its torso hitbox, which for a crawler or
## a hound is down near the floor (aiming at chest height went over them).
func _body_center(z: Node3D) -> Vector3:
	var boxes = z.get("_hitboxes")
	if boxes is Array:
		for a in boxes:
			if is_instance_valid(a) and a.get_meta("hit_zone", "") == "torso":
				return a.global_position
	return z.global_position + Vector3.UP * (0.35 if z.get("crippled") else 1.2)

## Where shots leave: the gun's muzzle when one is in hand.
func _muzzle_pos() -> Vector3:
	if held and held.visible and held.hold == "gun":
		return held.muzzle_global()
	return muzzle.global_position

func _recoil(w: Dictionary) -> float:
	if w["kind"] == "flame":
		return 0.05
	return clampf(float(w.get("damage", 20)) * float(w.get("pellets", 1)) / 160.0, 0.12, 1.0)

## Knife combo: slash, backhand, stab. Snaps to the nearest infected in
## front first, so swings connect on a phone without precise aiming.
func _start_swing(w: Dictionary) -> void:
	var moves: Array = MELEE_MOVES.get(inventory.equipped, MELEE_MOVES["knife"])
	if _combo_window <= 0.0:
		_combo = 0
	var m: Array = moves[_combo % moves.size()]
	_combo += 1
	_lock_target = _melee_target(float(w.get("range", 1.8)) + 1.4)
	_face_toward(_lock_target)
	var lands: float = m[2] / m[1]   # seconds from now
	model.play_combat(m[0], m[1], m[2] + 0.14 * m[1])
	_swing_t = lands
	_attack_lock = lands + 0.14
	_combo_window = lands + 0.6
	_cooldown = maxf(float(w["rate"]), lands + 0.08)
	Combat.play_shot_sound(inventory.equipped, global_position + Vector3.UP * 1.3)
	_rpc_action.rpc("swing", m[0], m[1])

func _start_throw(w: Dictionary) -> void:
	if inventory.ammo_count(inventory.equipped) <= 0 and not _free_reserve():
		equip(_fallback_weapon())
		return
	_face_yaw = yaw
	model.play_combat("throw", THROW_SPEED, 1.1 * THROW_SPEED)
	_throw_t = THROW_RELEASE
	_attack_lock = THROW_RELEASE + 0.1
	_cooldown = maxf(float(w.get("rate", 1.0)), THROW_RELEASE + 0.3)
	_rpc_action.rpc("swing", "throw", THROW_SPEED)

func _release_throw() -> void:
	var id := inventory.equipped
	if ItemInfo.kind(id) != "throwable":
		return
	if not _free_reserve(id) and inventory.take_ammo(id, 1) == 0:
		return
	var aim_dir := -camera.global_transform.basis.z
	var from: Vector3 = held.hand_global() if held.visible else muzzle.global_position
	# Leave the hand a little ahead of the body so it never hits the thrower.
	from += Vector3(aim_dir.x, 0.0, aim_dir.z).normalized() * 0.45
	Combat.fire(self, id, camera.global_position, [aim_dir], from)
	_emit_ammo()
	if inventory.ammo_count(id) <= 0 and not _free_reserve(id):
		equip(_fallback_weapon())

## Nearest standing infected within reach and roughly ahead (where the
## camera looks when aiming, else where the survivor faces or is moving).
func _melee_target(reach: float) -> Node3D:
	var fwd := -body.global_transform.basis.z
	if aiming:
		fwd = -camera.global_transform.basis.z
	elif move_input.length() > 0.2:
		fwd = Basis(Vector3.UP, yaw) * Vector3(move_input.x, 0, move_input.y)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Node3D = null
	var best_score := INF
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or z.get("state") in [Zombie.S.DEAD, Zombie.S.HIDDEN]:
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 0.01:
			continue
		var ang := fwd.angle_to(to / d)
		if ang > deg_to_rad(75.0):
			continue
		var score := d + ang * 1.5
		if score < best_score:
			best_score = score
			best = z
	return best

func _face_toward(t: Node3D) -> void:
	if t == null:
		_face_yaw = body.rotation.y if not aiming else yaw
		if move_input.length() > 0.2:
			var d := Basis(Vector3.UP, yaw) * Vector3(move_input.x, 0, move_input.y)
			_face_yaw = atan2(-d.x, -d.z)
		return
	var to := t.global_position - global_position
	_face_yaw = atan2(-to.x, -to.z)

## Lets the partner's phone see and hear this survivor's swings, throws and
## shots (damage itself is resolved by the host).
@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_action(kind: String, what: String, speed: float) -> void:
	match kind:
		"swing":
			model.play_combat(what, speed)
			if what != "throw":
				Combat.play_shot_sound(held.weapon_id if held.weapon_id != "" else "knife", global_position + Vector3.UP * 1.3)
		"shot":
			var w: Dictionary = WeaponDB.WEAPONS.get(what, {})
			if not w.is_empty():
				held.fired(_recoil(w))
				Combat.play_shot_sound(what, _muzzle_pos())
				# The partner's shot as seen here: along where the body faces,
				# tipped by the synced aim pitch.
				var right := body.global_transform.basis.x.normalized()
				var aim := (-body.global_transform.basis.z).normalized().rotated(right, sync_pitch)
				Combat.remote_shot_fx(self, what, _muzzle_pos(), aim)

## Inventory changes reach the partner's copy of this player (and so the
## host's saves) a moment later; mag counts ride along with the next change.
func _sync_inventory(delta: float) -> void:
	_inv_sync_t -= delta
	if not _inv_dirty or _inv_sync_t > 0.0:
		return
	_inv_dirty = false
	_inv_sync_t = 0.5
	var d := inventory.to_dict()
	GameState.inventories[character] = d
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_rpc_inventory.rpc(d)

@rpc("authority", "call_remote", "reliable")
func _rpc_inventory(d: Dictionary) -> void:
	inventory.from_dict(d)
	GameState.inventories[character] = d
	inventory_changed.emit()

## The partner handed something over. Whatever doesn't fit lands at our feet.
@rpc("any_peer", "call_local", "reliable")
func receive_item(id: String, n: int, rounds: int, from_name: String) -> void:
	if not is_multiplayer_authority():
		return
	var got := 0
	if ItemInfo.kind(id) == "weapon":
		if inventory.count(id) == 0 and inventory.add(id) == 1:
			inventory.mag[id] = rounds
			got = 1
	else:
		got = inventory.add(id, n)
	var hud := get_tree().get_first_node_in_group("hud")
	if got < n:
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("request_drop"):
			level.request_drop(Pickup.item_string(id), global_position + body.global_transform.basis.z * -0.5, n - got)
		if hud:
			hud.toast("%s gave you %s, but your bag is full. It's on the floor." % [from_name, ItemInfo.display_name(id)])
	elif hud:
		hud.toast("%s gave you %s" % [from_name, ItemInfo.display_name(id) + (" x%d" % n if n > 1 else "")])
	_emit_ammo()

# ---------- Health ----------

func apply_damage(amount: float, from: Node = null) -> void:
	if Cheats.on("god_mode") or downed:
		return
	if dodging and (amount >= 9.0 or from is Zombie):
		return   # rolled through it
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl and lvl.get("game_over"):
		return
	hp = max(hp - amount, 0.0)
	health_changed.emit(hp, max_hp)
	# A real blow (a bite, a swipe, acid, a blast) staggers; burn and gas
	# ticks only sting, or the survivor would be stuck flinching in a fire.
	var blow := amount >= 9.0 or from is Zombie
	if blow:
		stop_work()
	_feel_hit(amount, from, blow)
	if blow:
		_rpc_hurt_fx.rpc(amount)
	if hp <= 0.0:
		stop_work()
		downed = true
		_downed_t = 0.0
		pinned = false
		died.emit()
		Sfx.play_at("body_fall", global_position + Vector3.UP * 0.3, "", 2.0, 8.0)
		var partner_up := false
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and not p.downed:
				partner_up = true
		if Net.is_coop() and partner_up:
			# Down, not out: the partner has REVIVE_WINDOW seconds to reach her.
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("You're down! Call %s, they have %d seconds to reach you." % [GameState.partner_character(character).capitalize(), int(REVIVE_WINDOW)])
			_rpc_down_notice.rpc()
		else:
			_die()

## What taking a hit feels like on this phone: the flinch, a shove away from
## whatever hit you, a red flash from that side of the screen, a camera jolt,
## a buzz, the thud and a pained grunt.
func _feel_hit(amount: float, from: Node, blow: bool) -> void:
	var src := Vector3.INF
	if from is Node3D and is_instance_valid(from):
		src = (from as Node3D).global_position
	var heavy := amount >= 30.0
	if blow:
		model.flinch(heavy)
		_hit_stun = 0.42 if heavy else 0.28
		if src != Vector3.INF:
			var away := (global_position - src) * Vector3(1, 0, 1)
			if away.length() > 0.01:
				_knock = away.normalized() * (3.6 if heavy else 2.2)
		_shake = max(_shake, 0.9 if heavy else 0.55)
		Sfx.play_at("player_hit", global_position + Vector3.UP * 1.3, "flesh_hit", 3.0, 6.0)
		_grunt(heavy)
		if WebPlatform.can_vibrate():
			Input.vibrate_handheld(170 if heavy else 90, 1.0 if heavy else 0.7)
	var post := get_tree().get_first_node_in_group("horror")
	if post and post.get("post_fx"):
		post.post_fx.hit_flash(clampf(amount / 25.0, 0.25, 1.0) * (1.0 if blow else 0.5), _screen_dir(src))

## The partner's phone sees and hears the blow land on this survivor.
@rpc("authority", "call_remote", "unreliable")
func _rpc_hurt_fx(amount: float) -> void:
	model.flinch(amount >= 30.0)
	Sfx.play_at("player_hit", global_position + Vector3.UP * 1.3, "flesh_hit", 3.0, 8.0)
	_grunt(amount >= 30.0)

var _grunt_t := 0
func _grunt(heavy: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _grunt_t < 700:
		return
	_grunt_t = now
	Sfx.play_at("%s_pain%s" % [character, "_heavy" if heavy else ""], global_position + Vector3.UP * 1.6, "%s_pain" % character, 0.0, 7.0)

## Where on screen the blow came from (x right, y down), or zero when unknown.
func _screen_dir(src: Vector3) -> Vector2:
	if src == Vector3.INF or camera == null:
		return Vector2.ZERO
	var local := camera.global_transform.basis.inverse() * (src - camera.global_position)
	var d := Vector2(local.x, local.z)
	return d.normalized() if d.length() > 0.01 else Vector2.ZERO

## A jolt of the camera from something big nearby (an engine catching, a
## boss's slam). 0.5 is a hard shove, 1.0 the heaviest hit.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _tick_shake(delta: float) -> void:
	if camera == null:
		return
	_shake = move_toward(_shake, 0.0, delta * 2.6)
	var s := _shake * _shake * 0.09
	camera.h_offset = randf_range(-s, s)
	camera.v_offset = randf_range(-s, s)

## The partner's phone: their survivor just went down.
@rpc("authority", "call_remote", "reliable")
func _rpc_down_notice() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("%s is down! Get to %s and press INTERACT to revive." % [character.capitalize(), "her" if character == "obcera" else "him"])

## Dead: she falls, the camera pulls up and away in slow motion, the music
## dies, and the game-over screen comes up for both players (a co-op game
## ends when either survivor dies, as in a run where you can't leave anyone).
func _die() -> void:
	if dead:
		return
	dead = true
	downed = true
	pinned = false
	_grunt(true)
	if not Net.is_coop():
		Engine.time_scale = 0.35
		get_tree().create_timer(1.5, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("report_death"):
		level.report_death(character)

## Downed or dead: the camera eases back and looks down at her.
func _tick_death_cam(delta: float) -> void:
	if spring == null:
		return
	spring.spring_length = lerpf(spring.spring_length, 5.0 if dead else 3.2, 1.4 * delta)
	pitch = lerpf(pitch, -0.95 if dead else -0.5, 1.1 * delta)
	if dead:
		yaw += 0.16 * delta
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.fov = lerpf(camera.fov, 60.0, 2.0 * delta)
	_tick_shake(delta)

func set_pinned(on: bool, by: Node) -> void:
	pinned = on
	pinned_by = by if on else null
	_struggle = 0
	if on and is_multiplayer_authority():
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Grabbed! Tap INTERACT to struggle, or CALL your partner!")

func set_burning(secs: float) -> void:
	_burn_t = max(_burn_t, secs)

## Rescue interactions from the partner (revive a downed player, break a pin).
func proxy_interact_text(_by: Node, _handle := -1) -> String:
	if downed:
		return "Revive " + character.capitalize()
	if pinned:
		return "Free " + character.capitalize()
	return ""

func proxy_interact(_by: Node, _handle := -1) -> void:
	_rpc_rescue.rpc()

@rpc("any_peer", "reliable", "call_local")
func _rpc_rescue() -> void:
	if downed and not dead:
		downed = false
		_downed_t = 0.0
		hp = max_hp * 0.35
		health_changed.emit(hp, max_hp)
	if pinned and is_instance_valid(pinned_by) and multiplayer.is_server():
		pinned_by.break_pin()

func heal(amount: float) -> void:
	hp = min(hp + amount, max_hp)
	downed = false
	health_changed.emit(hp, max_hp)

func use_item(id: String) -> bool:
	if downed:
		return false   # only the partner can get her back up
	var item: Dictionary = WeaponDB.ITEMS.get(id, {})
	if item.has("heal") and (Cheats.on("infinite_heals") or inventory.take_item(id)):
		heal(item["heal"])
		if get_tree().paused:
			Sfx.ui("heal", -2.0)
		else:
			Sfx.play_at("heal", global_position + Vector3.UP, "", -2.0, 4.0)
		return true
	return false

# ---------- Interaction ----------

## What she can use right now: an item at her feet first (items lie on the
## floor, under the chest-high reach ray that finds doors), else whatever
## that ray meets.
func _update_focus() -> void:
	var target: Node = _nearest_pickup()
	# An item she has no room for doesn't block what she's looking at (a
	# drop by the generator's crank hid "Crank the engine" behind "Bag full").
	if target == null or not target.interact_text(self).begins_with("Pick up"):
		var looked: Node = null
		var hit: Object = interact_ray.get_collider() if interact_ray.is_colliding() else null
		if hit and hit.has_method("interact_text"):
			looked = hit
		elif hit and hit.get_parent() and hit.get_parent().has_method("interact_text"):
			looked = hit.get_parent()
		if looked and (target == null or looked.interact_text(self) != ""):
			target = looked
	# The prompt follows the text, not just the target: a taken item is freed
	# (and a freed node compares equal to null, so a target check alone kept
	# "Pick up ..." on screen), and a door's text changes once it opens.
	_focus = target
	var text: String = target.interact_text(self) if target else ""
	if text != _prompt_text:
		_prompt_text = text
		interact_prompt.emit(text)

const PICKUP_REACH := 1.5

## Closest item within reach, roughly in front (or right underfoot), on this
## floor and not behind a wall.
func _nearest_pickup() -> Node:
	var fwd := -body.global_transform.basis.z
	var eye := global_position + Vector3.UP * 1.0
	var space := get_world_3d().direct_space_state
	var best: Node = null
	var best_score := INF
	for p in get_tree().get_nodes_in_group("pickups"):
		if not (p is Node3D) or p.get("_taken"):
			continue
		var to: Vector3 = p.global_position - global_position
		if to.y < -0.6 or to.y > 1.8:
			continue
		to.y = 0.0
		var d := to.length()
		if d > PICKUP_REACH:
			continue
		var ang := fwd.angle_to(to / d) if d > 0.05 else 0.0
		if d > 0.7 and ang > deg_to_rad(100.0):
			continue
		var score := d + ang * 0.4
		if score >= best_score:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p.global_position + Vector3.UP * 0.15, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		# The shelf or crate an item rests on doesn't hide it (the herb on
		# the office shelf only had a prompt from one odd angle); a wall or
		# anything further off between her and it does.
		if not hit.is_empty() and hit.position.distance_to(p.global_position + Vector3.UP * 0.15) > 0.4:
			continue
		best_score = score
		best = p
	return best

func interact() -> void:
	if pinned:
		_struggle += 1
		if _struggle >= 12 and is_instance_valid(pinned_by):
			_rpc_rescue.rpc()
		return
	if is_instance_valid(_focus) and _focus.has_method("interact"):
		_focus.interact(self)
		_focus = null
		_update_focus()
