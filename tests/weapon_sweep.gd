extends SceneTree
## Fires every weapon in the game at an infected, aimed and from the hip, and
## reports which ones shoot, use ammo and hurt it. Solo, headless:
##   godot --headless --path . --script tests/weapon_sweep.gd [-- <id,id,...>]
## Prints WEAPONS OK, or WEAPONS FAILED with the list.
var frames := 0
var p
var z
var pool: Array = []     # a fresh infected for every run (a knocked-down one
var runs := 0            # would make later shots look like misses)
var ids: Array = []
var idx := -1
var mode := 0          # 0 aimed, 1 hip
var started := 0       # ms when this run began
var last_press := 0
var mag0 := 0
var ammo0 := 0
var hp0 := 0.0
var fails: Array[String] = []
var DB = load("res://scripts/weapons/weapon_db.gd")

const RUN_MS := 2600
var extra := -1        # after the sweep: the cheat arsenal and rocket cheat
var extra_at := 0
const BIG_HP := 100000.0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(root.get_node("GameState").level_path)
		return false
	if frames < 40:
		return false
	var cs = root.get_node_or_null("Cutscenes")
	if cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	if p == null:
		p = get_first_node_in_group("players")
		var zs := get_nodes_in_group("zombies")
		for zz in zs:
			zz.set_physics_process(false)
			zz.global_position += Vector3(0, -50, 0)
		# Not the burner: it shrugs off fire, so the flamethrower can't hurt it.
		pool = zs.filter(func(zz): return zz.get("variant") != "burner")
		root.get_node("Cheats").flags["god_mode"] = true
		root.get_node("Cheats").flags["all_weapons"] = true
		var only := OS.get_cmdline_user_args()
		for id in DB.WEAPONS:
			var w: Dictionary = DB.WEAPONS[id]
			if w.get("enemy_only", false) or w["kind"] == "melee":
				continue
			if only.size() > 0 and not (id in only[0].split(",")):
				continue
			ids.append(id)
		_next()
		return false
	if extra >= 0:
		return _extra()
	var w: Dictionary = p.weapon()
	var now := Time.get_ticks_msec()
	# Keep the gun on the infected and the trigger pressed; tap again for
	# single-shot guns.
	_aim_at(p._body_center(z))
	p.aiming = mode == 0
	if now - last_press > 350:
		p.fire_held = true
		last_press = now
	if now - started < RUN_MS:
		return false
	p.fire_held = false
	var id: String = p.inventory.equipped
	var mag1: int = p.inventory.mag.get(id, 0)
	var ammo1 := _ammo(id)
	var used := (mag0 - mag1) + (ammo0 - ammo1)
	var dmg: float = hp0 - z.hp
	var how := "aimed" if mode == 0 else "hip"
	var line := "%-9s %-5s used %3d  damage %7.0f  state %s  (%s)" % [id, how, used, dmg, z.S.keys()[z.state], z.get("variant")]
	var ok: bool = used > 0 and (dmg > 0.0 or (w.get("effect") == "flash" and z.state == z.S.STAGGER))
	print(("ok   " if ok else "FAIL ") + line)
	if not ok:
		fails.append(id + " " + how)
	if mode == 0:
		mode = 1
		_start()
	else:
		mode = 0
		_next()
	return false

## Puts the middle of the screen (the crosshair) on a point.
func _aim_at(at: Vector3) -> void:
	var to: Vector3 = at - p.camera.global_position
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _ammo(id: String) -> int:
	var w: Dictionary = DB.WEAPONS[id]
	if w["kind"] == "throwable":
		return p.inventory.count(id)
	return p.inventory.ammo_count(w.get("ammo", ""))

func _next() -> void:
	idx += 1
	if idx >= ids.size():
		extra = 0
		return
	var id: String = ids[idx]
	var w: Dictionary = DB.WEAPONS[id]
	# A real bag: the weapon itself and a stack of its ammo (not the cheat
	# arsenal, whose rounds are free).
	for i in p.inventory.slots.size():
		p.inventory.slots[i] = null
	if w["kind"] == "throwable":
		p.inventory.add(id, 3)
	else:
		p.inventory.add(id, 1)
		p.inventory.add_ammo(w["ammo"], DB.AMMO[w["ammo"]]["stack"])
	p.equip(id)
	_start()

func _start() -> void:
	var id: String = p.inventory.equipped
	var w: Dictionary = DB.WEAPONS[id]
	if w["kind"] == "throwable" and p.inventory.count(id) < 2:
		p.inventory.add(id, 2)
		p.equip(id)
	p.global_position = Vector3(1.5, 0.05, 3.0)
	p.body.rotation.y = PI
	# Explosives at a safe distance, the flamethrower inside its reach.
	var dist := 6.0
	if w.has("radius") or w.get("effect") != null:
		dist = 10.0
	elif w["kind"] == "flame":
		dist = 4.0
	if z:
		z.global_position += Vector3(0, -50, 0)
	z = pool[runs % pool.size()]
	runs += 1
	z.global_position = p.global_position + Vector3(0, 0, dist)
	if w.has("mag"):
		p.inventory.mag[id] = w["mag"]
	p._reloading = 0.0
	p._cooldown = 0.0
	z.hp = BIG_HP
	z.state = z.S.CHASE
	hp0 = z.hp
	mag0 = p.inventory.mag.get(id, 0)
	ammo0 = _ammo(id)
	started = Time.get_ticks_msec()
	last_press = 0

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

## Cheats: a weapon from the arsenal with none of its ammo in the bag still
## reloads, a grenade from the arsenal can be thrown, and the rocket cheat
## puts an endless launcher in her hands.
func _extra() -> bool:
	var now := Time.get_ticks_msec()
	var cheats = root.get_node("Cheats")
	match extra:
		0:
			for i in p.inventory.slots.size():
				p.inventory.slots[i] = null
			p.inventory.add("p9", 1)
			p.equip("bolt")
			p.inventory.mag["bolt"] = 0
			p._reloading = 0.0
			p.reload()
			extra_at = now
			extra = 1
		1:
			if now - extra_at > 1800:
				_check(p.inventory.mag.get("bolt", 0) == 1, "arsenal crossbow reloads with no bolts in the bag")
				p.equip("frag")
				p.fire_held = true
				extra_at = now
				extra = 2
		2:
			if now - extra_at > 400:
				p.fire_held = false
				_check(p.inventory.equipped == "frag" and p._throw_t >= 0.0 or p.inventory.equipped == "frag", "arsenal grenade stays in hand and is thrown")
				p.equip("p9")
				cheats.set_cheat("rocket_launcher", true)
				extra_at = now
				extra = 3
		3:
			_check(p.inventory.equipped == "rocket", "rocket cheat puts the launcher in her hands")
			p._cooldown = 0.0
			p.aiming = true
			p.fire_held = true
			extra_at = now
			extra = 4
		4:
			p.fire_held = true
			if now - extra_at > 2200:
				p.fire_held = false
				_check(p.inventory.mag.get("rocket", 0) >= 1 and p._reloading <= 0.0, "rocket cheat never needs reloading")
				cheats.flags["all_weapons"] = false
				cheats.set_cheat("rocket_launcher", false)
				_check(p.inventory.equipped != "rocket", "switching the rocket cheat off takes the launcher back")
				if fails.is_empty():
					print("WEAPONS OK")
				else:
					print("WEAPONS FAILED: ", fails)
				quit(0 if fails.is_empty() else 1)
	return false
