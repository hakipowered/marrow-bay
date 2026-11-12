class_name Player
extends CharacterBody3D
## Third-person over-the-shoulder survivor. Each player's own phone simulates
## its movement (authority = owning peer); position/aim sync to the partner.
## Damage to enemies is resolved on the host.

signal health_changed(hp: float, max_hp: float)
signal weapon_changed(id: String)
signal ammo_changed(in_mag: int, reserve: int)
signal interact_prompt(text: String)
signal died

const WALK_SPEED := 2.4
const RUN_SPEED := 4.6
const AIM_SPEED := 1.3
const GRAVITY := 18.0
const SHOULDER_OFFSET := Vector3(0.55, 1.55, 0.0)
const CAM_DIST := 2.4
const CAM_DIST_AIM := 1.15

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

# Synced to the partner.
@export var sync_yaw := 0.0
@export var sync_pitch := 0.0
@export var sync_aiming := false
@export var sync_anim := "idle"

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var body: Node3D
var model: CharacterModel
var flashlight: SpotLight3D
var muzzle: Node3D
var interact_ray: RayCast3D

func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("players")
	# Gesture when this survivor calls out: wave over, or a full-body shout.
	CallOuts.callout_played.connect(func(speaker: int, _c: String, _id: String, _t: String, scream: bool):
		if speaker == peer_id and model:
			model.play_once("shout" if scream else "call", 0.15, 2.2))
	collision_layer = 2
	collision_mask = 1 | 4
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

	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.18, 1.45, -0.2)
	flashlight.spot_range = 16.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 2.2
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = true
	body.add_child(flashlight)

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

	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0, 0, -2.2)
	interact_ray.collision_mask = 16
	interact_ray.collide_with_areas = true
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
	if is_multiplayer_authority():
		camera.make_current()
	else:
		camera.current = false

func _setup_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":sync_yaw", ":sync_pitch", ":sync_aiming", ":sync_anim", ":downed", ":pinned"]:
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
		model.play(sync_anim, sync_aiming)
		return
	rescue_area.collision_layer = 16 if (downed or pinned) else 0
	if _burn_t > 0:
		_burn_t -= delta
		if fmod(_burn_t, 0.5) < delta:
			apply_damage(3.0)
	slowed_for = max(slowed_for - delta, 0.0)
	if downed:
		_downed_t += delta
		sync_anim = "downed"
		model.play("downed", false)
		if _downed_t > REVIVE_WINDOW or not Net.is_coop():
			_bleed_out()
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
	_read_keyboard()
	# Look
	yaw -= look_delta.x * 0.0045
	pitch = clamp(pitch - look_delta.y * 0.0035, -1.2, 0.9)
	look_delta = Vector2.ZERO
	pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = lerp(spring.spring_length, CAM_DIST_AIM if aiming else CAM_DIST, 10 * delta)
	camera.fov = lerp(camera.fov, 52.0 if aiming else 68.0, 10 * delta)

	# Move relative to camera
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := basis_y * Vector3(move_input.x, 0, move_input.y)
	var speed := AIM_SPEED if aiming else (RUN_SPEED if running else WALK_SPEED)
	if slowed_for > 0:
		speed *= 0.4
	if Cheats.on("noclip"):
		global_position += (pivot.global_transform.basis * Vector3(move_input.x, 0, move_input.y)) * RUN_SPEED * 2 * delta
		return
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if aiming or fire_held:
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 18 * delta)
	elif dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 10 * delta)

	sync_yaw = body.rotation.y
	sync_pitch = pitch
	sync_aiming = aiming
	sync_anim = "run" if (running and dir.length() > 0.1) else ("walk" if dir.length() > 0.1 else "idle")
	if _reloading > 0.0 and dir.length() <= 0.1:
		sync_anim = "reload"
	model.play(sync_anim, aiming)

	_tick_weapon(delta)
	_update_focus()

func _read_keyboard() -> void:
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

# ---------- Weapons ----------

func weapon() -> Dictionary:
	return WeaponDB.WEAPONS.get(inventory.equipped, {})

func equip(id: String) -> void:
	if not inventory.has_weapon(id):
		return
	inventory.equipped = id
	if not inventory.mag.has(id):
		inventory.mag[id] = weapon().get("mag", 0)
	_reloading = 0.0
	weapon_changed.emit(id)
	_emit_ammo()

func _emit_ammo() -> void:
	var w := weapon()
	ammo_changed.emit(inventory.mag.get(inventory.equipped, 0), inventory.ammo.get(w.get("ammo", ""), 0))

func reload() -> void:
	var w := weapon()
	if not w.has("mag") or _reloading > 0:
		return
	var reserve: int = inventory.ammo.get(w["ammo"], 0)
	if Cheats.on("infinite_ammo"):
		reserve = 999
	if inventory.mag.get(inventory.equipped, 0) >= w["mag"] or reserve <= 0:
		return
	_reloading = 0.05 if Cheats.on("no_reload") else w["reload"]

func _finish_reload() -> void:
	var w := weapon()
	var need: int = w["mag"] - inventory.mag.get(inventory.equipped, 0)
	if w.get("reload_per_shell", false):
		need = min(need, 1)
	var have: int = 999 if Cheats.on("infinite_ammo") else inventory.ammo.get(w["ammo"], 0)
	var n: int = min(need, have)
	inventory.mag[inventory.equipped] = inventory.mag.get(inventory.equipped, 0) + n
	if not Cheats.on("infinite_ammo"):
		inventory.ammo[w["ammo"]] = have - n
	_emit_ammo()
	if w.get("reload_per_shell", false) and inventory.mag[inventory.equipped] < w["mag"]:
		_reloading = w["reload"]

func _tick_weapon(delta: float) -> void:
	_cooldown -= delta
	if _reloading > 0:
		_reloading -= delta
		if _reloading <= 0:
			_finish_reload()
		return
	var w := weapon()
	if w.is_empty():
		return
	var wants: bool = fire_held and (aiming or w["kind"] == "melee")
	if _burst_left > 0 and _cooldown <= 0:
		_fire_once(w)
		_burst_left -= 1
		_cooldown = w["rate"] if _burst_left > 0 else w.get("burst_gap", w["rate"])
		return
	if wants and _cooldown <= 0:
		if w["kind"] != "melee" and inventory.mag.get(inventory.equipped, 0) <= 0:
			reload()
			return
		_burst_left = w.get("burst", 1) - 1
		_fire_once(w)
		_cooldown = w["rate"]
		if not w.get("auto", false) and w.get("burst", 1) == 1:
			fire_held = false

func _fire_once(w: Dictionary) -> void:
	if w["kind"] != "melee":
		if inventory.mag.get(inventory.equipped, 0) <= 0:
			return
		if not Cheats.on("infinite_ammo"):
			inventory.mag[inventory.equipped] -= 1
		_emit_ammo()
	var origin := camera.global_position
	var aim_dir := -camera.global_transform.basis.z
	var shots := []
	var pellets: int = w.get("pellets", 1)
	for i in pellets:
		var spread := deg_to_rad(w.get("spread", 0.0)) * (1.0 if aiming else 2.0)
		var d := aim_dir.rotated(camera.global_transform.basis.x, randf_range(-spread, spread) * 0.5)
		d = d.rotated(camera.global_transform.basis.y, randf_range(-spread, spread) * 0.5)
		shots.append(d.normalized())
	Combat.fire(self, inventory.equipped, origin, shots, muzzle.global_position)

# ---------- Health ----------

func apply_damage(amount: float, _from: Node = null) -> void:
	if Cheats.on("god_mode") or downed:
		return
	hp = max(hp - amount, 0.0)
	health_changed.emit(hp, max_hp)
	model.flinch()
	if hp <= 0.0:
		downed = true
		_downed_t = 0.0
		pinned = false
		died.emit()
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and is_multiplayer_authority():
			hud.toast("You're down! Your partner has 30 seconds to reach you." if Net.is_coop() else "You died.")

func _bleed_out() -> void:
	# Both players go back to the last shared checkpoint together.
	set_physics_process(false)
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("request_retry"):
		level.request_retry()

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
	if downed:
		downed = false
		hp = max_hp * 0.35
		health_changed.emit(hp, max_hp)
	if pinned and is_instance_valid(pinned_by) and multiplayer.is_server():
		pinned_by.break_pin()

func heal(amount: float) -> void:
	hp = min(hp + amount, max_hp)
	downed = false
	health_changed.emit(hp, max_hp)

func use_item(id: String) -> void:
	var item: Dictionary = WeaponDB.ITEMS.get(id, {})
	if item.has("heal") and (Cheats.on("infinite_heals") or inventory.take_item(id)):
		heal(item["heal"])

# ---------- Interaction ----------

func _update_focus() -> void:
	var hit: Object = interact_ray.get_collider() if interact_ray.is_colliding() else null
	var target: Node = null
	if hit and hit.has_method("interact_text"):
		target = hit
	elif hit and hit.get_parent() and hit.get_parent().has_method("interact_text"):
		target = hit.get_parent()
	if target != _focus:
		_focus = target
		interact_prompt.emit(_focus.interact_text(self) if _focus else "")

func interact() -> void:
	if pinned:
		_struggle += 1
		if _struggle >= 12 and is_instance_valid(pinned_by):
			_rpc_rescue.rpc()
		return
	if _focus and _focus.has_method("interact"):
		_focus.interact(self)
		_focus = null
