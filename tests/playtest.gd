extends SceneTree
## Playtest bot: plays the first area the way a person does on the phone and
## reports anything that looks wrong, so a build is played end to end before
## it goes out. It walks the real routes (navigation, doors, kerbs), fights
## every infected it meets with real damage on, picks things up, watches the
## cutscenes, saves, dies and continues, and checks the problems reported on
## earlier builds while it plays (see _monitor).
##
## Everything: godot --headless --path . --fixed-fps 60 --script tests/playtest.gd
##   (about 4x faster than real time). One section: add `-- only <name>`:
##   probe   level holes, infected inside props or falling through the
##           floor, items hidden inside props (about 30 s)
##   route   the whole first area solo, room by room (about 90 s), then
##           down the elevator and on through chapter 2 (route2)
##   probe2  the level probe on chapter 2, the Undercroft
##   route2  chapter 2 on its own, from the lift (with about the bag a
##           player has by the end of chapter 1)
##   scares  walks into the scares that bring infected in (the diner
##           shutter, the reading-room ceiling) looking where a player
##           would, and checks they come through their way in and get up
##   weapons, bag, save, death   (under a minute each)
## Every section also watches for infected appearing in plain view out of
##   nowhere and for bodies sunk into the floor (see _check_popin, _floor_checks).
## Before a build: tools/playtest.sh (quick) or tools/playtest.sh full; it
##   also runs the co-op checks (tests/playtest_coop.gd) with two copies of
##   the game through a local relay.
## Frames: add `shots <dir>` and run with a display (xvfb-run, no --headless,
##   --rendering-method mobile) to save a picture at every step and problem.
## Output: "PLAYTEST BUG <area>: <what>" per problem, "PLAYTEST NOTE" for
##   things to look at, then "PLAYTEST DONE <n> bugs"; exit 1 if n > 0.
## The route can log bot-side trouble too ("stuck ... pushing toward" at a
## desk, "couldn't put down" when it can't get a clear shot): read those as
## leads, not verdicts. It warps past a spot it can't get through (logged)
## and, if she dies, presses Continue and finishes in god mode.

const STRIKE_LOS_MASK := 1
## Zombie.S, read at run time: naming the Zombie class here makes Godot
## compile it before the autoloads exist and print a bogus SCRIPT ERROR.
var ZS: Dictionary
var NAT_SPEED: Dictionary
var GS: Node
var NET: Node
var SAVE: Node
var CHEATS: Node
var CUTS: Node
var MUSIC: Node

var p: Node = null
var sim_t := 0.0
var bugs := {}          # key -> text (each problem once)
var notes: Array = []
var shots_dir := ""
var character := "obcera"
var only := ""          # run one section: route, weapons, death, save, bag, outfits
var stop_at := 0.0      # end the run after this much game time (frames runs)
var _shot_n := 0
var _busy_fighting := false
## Rooms of the Archive hub (x, z rectangles), so the bot clears one room at
## a time instead of trying to reach infected behind a closed door.
const AREAS := {
	"street": Rect2(-20, -30, 40, 16), "courtyard": Rect2(-10, -14, 20, 12),
	"hall": Rect2(-12, -2, 24, 18), "corridor": Rect2(-24, 5, 12, 3),
	"reading": Rect2(-26, -7, 14, 12), "office": Rect2(12, 0, 8, 8),
	"vault": Rect2(-10, 16, 14, 10), "boiler": Rect2(4, 16, 10, 10),
	"diner": Rect2(3.4, -35, 7.2, 5),
}
## Rooms of the Undercroft (chapter 2).
const AREAS2 := {
	"lift": Rect2(0, 0, 7, 6), "corridor": Rect2(7, 1.5, 32, 3),
	"lodge": Rect2(8, 4.5, 7, 6), "survey": Rect2(9, -9.5, 12, 11),
	"gallery": Rect2(21, -9.5, 14, 11), "stair": Rect2(31.5, -12.5, 3, 3),
	"muster": Rect2(19, 4.5, 14, 10), "hall": Rect2(39, -6, 16, 18),
	"yard": Rect2(55, -6, 22, 18), "stacks": Rect2(43, 12, 8, 8),
}
const UNDERCROFT := "res://scenes/levels/undercroft.tscn"
## The rooms of the level she's in (AREAS or AREAS2).
var areas: Dictionary = AREAS
var _ammo_used := 0
var _hits_landed := 0
var _dry_at := -1.0

# ---- monitor state
var _prev_hp := 100.0
var _prev_stun := 0.0
var _prev_mag := {}
var _zhp := {}
var _hits: Array = []           # [time, attacker name, wall behind?]
var _struck := {}               # zombie instance id -> was struck last frame
var _legs_bad_t := 0.0
var _legs_bad_worst := {}
var _stuck_ref := Vector3.INF
var _stuck_t := 0.0
var _seen_audio := {}
var _voice_starts: Array = []   # [time, id]
var _music_log := {}            # track -> seconds while fighting ordinary infected
var _fight_kind := ""
var _kills := {}
var _damage_taken := 0.0
var _shots_fired := 0
var _strikes := 0
var _wall_strikes := 0
# Pop-in and floor checks (0.10 feedback).
var _level_ref: Node = null
var _level_t := 0.0
var _fresh: Array = []          # enemies (or bare enemy models) that appeared mid-game
var _orphans: Array = []        # enemy models not on an infected (scripted bodies)
var _floor_checked := {}        # instance id -> sim_t of the last floor check
var _mesh_cache := {}
var _bot_spawning := false
var _popins := 0
var _sunk := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"shots":
				shots_dir = a[i + 1]
				i += 1
			"char":
				character = a[i + 1]
				i += 1
			"only":
				only = a[i + 1]
				i += 1
			"stop_at":
				stop_at = float(a[i + 1])
				i += 1
		i += 1
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	ZS = load("res://scripts/enemies/zombie.gd").S
	NAT_SPEED = load("res://scripts/player/character_model.gd").NATURAL_SPEED
	GS = root.get_node("GameState")
	NET = root.get_node("Net")
	SAVE = root.get_node("SaveSystem")
	CHEATS = root.get_node("Cheats")
	CUTS = root.get_node("Cutscenes")
	MUSIC = root.get_node("Music")
	physics_frame.connect(_monitor)
	node_added.connect(_on_node_added)
	_main.call_deferred()

# ================================================================ helpers

func _bug(area: String, what: String, key := "") -> void:
	var k := key if key != "" else area + ":" + what
	if bugs.has(k):
		return
	bugs[k] = "%s: %s" % [area, what]
	print("PLAYTEST BUG %s: %s   [t=%.1fs]" % [area, what, sim_t])
	_shot("bug_" + area.replace(" ", "_"))

func _note(what: String) -> void:
	notes.append(what)
	print("PLAYTEST NOTE ", what)

func _wait(sec: float) -> void:
	var end := sim_t + sec
	while sim_t < end:
		await physics_frame

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(tag: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	_shot_n += 1
	var img := root.get_viewport().get_texture().get_image()
	if img:
		img.save_jpg("%s/%03d_%s.jpg" % [shots_dir, _shot_n, tag], 0.82)

func _level() -> Node:
	return get_first_node_in_group("level")

func _zombies() -> Array:
	var out := []
	for z in get_nodes_in_group("zombies"):
		if is_instance_valid(z) and z.state != ZS.DEAD and z.global_position.y > -1.0:
			out.append(z)
	return out

func _hud() -> Node:
	return get_first_node_in_group("hud")

func _los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, STRIKE_LOS_MASK, exclude)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _wait_cutscene_end(watch := 2.5, max_t := 200.0) -> String:
	# Watch a moment of every scene (frames for review), then skip it like a
	# player who has seen it before. Returns the scene id.
	var id: String = CUTS.current
	await _wait(watch)
	_shot("cutscene_" + id)
	CUTS._on_skip_pressed()
	var end := sim_t + max_t
	while CUTS.active and sim_t < end:
		await physics_frame
	if CUTS.active:
		_bug("cutscene", "scene '%s' still running %.0fs after Skip" % [id, max_t])
	await _wait(0.5)
	_after_cutscene_checks(id)
	return id

func _after_cutscene_checks(id: String) -> void:
	if p == null:
		return
	if p.input_locked:
		_bug("cutscene", "controls still locked after scene '%s'" % id)
	if p.cutscene_pose:
		_bug("cutscene", "survivor still held in a cutscene pose after '%s'" % id)
	var cam := root.get_viewport().get_camera_3d()
	if cam != p.camera:
		_bug("cutscene", "camera not given back to the player after '%s' (%s)" % [id, cam])
	var hud := _hud()
	if hud and not hud.visible:
		_bug("cutscene", "HUD hidden after scene '%s'" % id)

# ---------------------------------------------------------------- moving

func _steer(dir: Vector3, run := true, turn_cam := true) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		p.move_input = Vector2.ZERO
		return
	dir = dir.normalized()
	if turn_cam and not p.aiming:
		p.yaw = lerp_angle(p.yaw, atan2(-dir.x, -dir.z), 0.12)
		p.pitch = lerpf(p.pitch, -0.12, 0.1)
	var local: Vector3 = Basis(Vector3.UP, p.yaw).inverse() * dir
	p.move_input = Vector2(local.x, local.z).limit_length(1.0)
	p.running = run

func _stop() -> void:
	p.move_input = Vector2.ZERO
	p.running = false
	p.aiming = false
	p.fire_held = false

func _threat(radius := 7.0) -> Node:
	var best: Node = null
	var bd := radius
	for z in _zombies():
		if z.state not in [ZS.CHASE, ZS.ATTACK, ZS.CRAWL, ZS.CHARGE, ZS.PINNING, ZS.STAGGER]:
			continue
		var d: float = z.global_position.distance_to(p.global_position)
		if d < bd and _los(p.global_position + Vector3.UP * 1.3, z.global_position + Vector3.UP * 1.0, [p.get_rid(), z.get_rid()]):
			bd = d
			best = z
	return best

## Walk (navmesh path) to `target`, fighting anything that comes for her.
## The navmesh is baked with the doors shut, so a path through a door ends
## in front of it; from there she walks straight on through the doorway.
func go_to(target: Vector3, timeout := 40.0, run := true, tag := "") -> bool:
	await _recover()
	var end := sim_t + timeout
	var path := _path(target)
	var i := 0
	while sim_t < end:
		if p.downed:
			return false
		var z := _threat()
		if z and not _busy_fighting:
			await fight(z)
			path = _path(target)
			i = 0
			continue
		if i >= path.size():
			break
		var to: Vector3 = path[i] - p.global_position
		to.y = 0.0
		if to.length() < (0.35 if i < path.size() - 1 else 0.45):
			i += 1
			if i < path.size() and i == path.size() - 1 and path.size() >= 2:
				# Straight-on leg (through a doorway): re-path once past it.
				pass
			continue
		_steer(to, run)
		await physics_frame
	_stop()
	var off := Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length()
	if off > 1.2:
		_bug("route", "couldn't walk to %s%s: stopped at %s" % [tag, _v(target), _v(p.global_position)], "route:" + tag)
		return false
	return true

## Through a doorway: walk to the front, then straight on to the back,
## stepping around anything in the way (a lamp post, a zombie).
func cross(front: Vector3, back: Vector3, tag := "") -> bool:
	await go_to(front, 40.0, true, tag + " (front) ")
	await _recover()
	if OS.has_environment("PT_DEBUG"):
		print("PTDBG cross %s from %s t=%.1f" % [tag, _v(p.global_position), sim_t])
	var end := sim_t + 10.0
	var ref: Vector3 = p.global_position
	var ref_t := sim_t
	var dodge := 0.0
	var side := 1.0
	while sim_t < end:
		var z := _threat(3.0)
		if z and not _busy_fighting:
			# Infected coming through the doorway: fight, then walk on with a
			# fresh 10 s (backing off while fighting used up the old one).
			print("PLAYTEST NOTE fighting at %s while crossing %s" % [_v(p.global_position), tag])
			await fight(z)
			end = maxf(end, sim_t + 10.0)
		if CUTS.active:
			await _wait_cutscene_end(2.0)   # a story scene on the threshold
			end += 10.0
		if p.dead:
			break
		var to: Vector3 = back - p.global_position
		to.y = 0
		if to.length() < 0.45:
			_stop()
			if OS.has_environment("PT_DEBUG"):
				print("PTDBG crossed %s at %s t=%.1f" % [tag, _v(p.global_position), sim_t])
			return true
		if sim_t - ref_t > 0.5:
			if p.global_position.distance_to(ref) < 0.1:
				dodge = 0.6
				side = -side
			ref = p.global_position
			ref_t = sim_t
		var dir := to.normalized()
		if dodge > 0.0:
			dodge -= 1.0 / 60.0
			dir = (dir * 0.3 + dir.cross(Vector3.UP) * side).normalized()
		_steer(dir, false)
		await physics_frame
	_stop()
	_bug("route", "couldn't get through %s: stuck at %s" % [tag, _v(p.global_position)], "cross:" + tag)
	await _warp(back, "past " + tag)
	return false

## She died: note where, press Continue like a player would, and finish the
## run in god mode so everything after it still gets covered.
var _deaths := 0
func _recover() -> void:
	if p == null or not is_instance_valid(p) or not p.dead:
		return
	_deaths += 1
	_stop()
	_note("she died in the %s at %s (t=%.0fs, damage taken so far %.0f); pressing Continue, the rest in god mode" % [_area_of(p.global_position), _v(p.global_position), sim_t, _damage_taken])
	var lvl := _level()
	var end := sim_t + 15.0
	while sim_t < end and not lvl.get("game_over"):
		await physics_frame
	if not lvl.get("game_over"):
		_bug("death", "no game over screen after she died")
	await _wait(5.0)
	lvl.vote_continue()
	end = sim_t + 20.0
	while sim_t < end and (_level() == lvl or _level() == null or get_first_node_in_group("players") == null):
		await physics_frame
	if _level() == lvl:
		_bug("death", "Continue didn't reload the checkpoint")
		return
	await _wait(1.0)
	p = get_first_node_in_group("players")
	_prev_hp = p.hp
	_stuck_ref = Vector3.INF
	CHEATS.set_cheat("god_mode", true)
	if CUTS.active:
		await _wait_cutscene_end(2.0)

## Puts her somewhere by hand (after a logged failure), so one stuck spot
## doesn't hide every bug past it.
func _warp(to: Vector3, why: String) -> void:
	_note("warped to %s (%s)" % [_v(to), why])
	p.global_position = to + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	_stuck_ref = Vector3.INF
	await _wait(0.3)

## Nav path to `target`; if the mesh ends short of it (a doorway), the last
## leg goes straight to the target.
func _path(target: Vector3) -> PackedVector3Array:
	var map: RID = p.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, p.global_position, target, true)
	if path.is_empty():
		return PackedVector3Array([target])
	var last: Vector3 = path[path.size() - 1]
	if Vector2(last.x - target.x, last.z - target.z).length() > 0.6:
		# Path stops at a door: walk through, then path again from there.
		path.append(target)
	else:
		path.append(target)
	return path

func _area_of(v: Vector3) -> String:
	for k in areas:
		if areas[k].has_point(Vector2(v.x, v.z)):
			return k
	return "outside"

func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]

## Turn the body to face a point (walk a step toward it, like a player does).
func face(pt: Vector3) -> void:
	var to: Vector3 = pt - p.global_position
	to.y = 0
	p.yaw = atan2(-to.x, -to.z)
	for k in 12:
		_steer(to, false)
		await physics_frame
	_stop()
	for k in 6:
		await physics_frame

## Use whatever is in front of her: checks the prompt first.
func use_thing(expect := "", where := "") -> bool:
	await physics_frame
	var txt: String = p._prompt_text
	if txt == "":
		_bug("interact", "no prompt at %s (expected '%s')" % [where, expect], "noprompt:" + where)
		return false
	if expect != "" and not txt.to_lower().contains(expect.to_lower()):
		_bug("interact", "prompt at %s says '%s', expected '%s'" % [where, txt, expect], "wrongprompt:" + where)
	p.interact()
	await _wait(0.3)
	return true

func open_door(door_id: String, stand: Vector3, at: Vector3) -> bool:
	var d: Node = null
	for x in get_nodes_in_group("doors"):
		if x.door_id == door_id:
			d = x
	if d == null:
		_bug("doors", "door %s missing" % door_id)
		return false
	if d.is_open:
		return true
	await _recover()
	for attempt in 3:
		if not await go_to(stand, 40.0, true, "door " + door_id + " ") and attempt == 1:
			await _warp(stand, "to door " + door_id)
		await face(at)
		if p._prompt_text == "" and attempt < 2:
			continue
		await use_thing("", "door " + door_id)
		await _wait(1.6)
		if d.is_open:
			return true
	_bug("doors", "door %s didn't open (prompt '%s')" % [door_id, p._prompt_text])
	return false

## Walk to an item and pick it up through the real prompt.
func pick_up(pid: String) -> bool:
	var node: Node = null
	for x in get_nodes_in_group("pickups"):
		if x.pickup_id == pid:
			node = x
	if node == null:
		if not GS.has_flag("taken:" + pid):
			_bug("pickups", "item %s missing from the level" % pid)
		return GS.has_flag("taken:" + pid)
	return await pick_up_node(node)

## Where she stands to take an item: 0.7 m out from it on her side if that's
## free, else the nearest free spot turning round the item and stepping
## further out (up to 1.3 m). Walking at a spot inside the desk the item lies
## on had her pushing against the desk, which read as "stuck".
func _stand_spot(stand: Vector3, dir: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = [p.get_rid()]
	for r in [0.7, 0.9, 1.1, 1.3]:
		for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8]:
			var c: Vector3 = stand + dir.rotated(Vector3.UP, k * TAU / 16.0) * r
			q.transform = Transform3D(Basis(), c + Vector3.UP * 0.83)
			if space.intersect_shape(q, 1).is_empty():
				return c
	return stand + dir * 0.7

func pick_up_node(node: Node) -> bool:
	var tag: String = node.pickup_id if node.pickup_id != "" else str(node.name)
	for attempt in 3:
		if not is_instance_valid(node) or node._taken:
			return true
		var pos: Vector3 = node.global_position
		var stand := pos
		stand.y = p.global_position.y
		var from: Vector3 = (p.global_position - stand) * Vector3(1, 0, 1)
		if from.length() < 0.1:
			from = Vector3.BACK
		var spot := _stand_spot(stand, from.normalized())
		if not await go_to(spot, 40.0, true, "item " + tag + " ") and attempt == 1:
			await _warp(spot, "to item " + tag)
		await face(pos)
		await physics_frame
		var prompt: String = p._prompt_text
		# No room for it: the prompt says so, or (beside a door, the crank)
		# gives way to the thing she's looking at.
		if not prompt.begins_with("Pick up") and not p.inventory.can_take(node.item):
			_note("bag full, left %s" % tag)
			return false
		if prompt == "" or not (prompt.begins_with("Pick up") or prompt.begins_with("Bag full")):
			if attempt == 2:
				_bug("pickups", "no 'Pick up' prompt next to %s at %s (prompt '%s', item %.1f m above her feet)" % [tag, _v(pos), prompt, pos.y - p.global_position.y], "noprompt:" + tag)
			continue
		if prompt.begins_with("Bag full"):
			_note("bag full, left %s" % tag)
			return false
		var target: Node = p._focus
		var before: String = JSON.stringify(p.inventory.to_dict())
		p.interact()
		await _wait(0.6)
		if target != null and is_instance_valid(target) and not target._taken:
			_bug("pickups", "pressed INTERACT on '%s' and nothing was taken" % prompt)
			continue
		if p._prompt_text == prompt and is_instance_valid(p._focus) and p._focus == target:
			_bug("pickups", "prompt '%s' still showing after picking it up" % prompt)
		if before == JSON.stringify(p.inventory.to_dict()):
			_bug("pickups", "picked up '%s' but the bag didn't change" % prompt)
		if target != node:
			continue   # took the item next to it first; go again for this one
		return true
	return false

# ---------------------------------------------------------------- fighting

func _aim_point(z: Node, head := false) -> Vector3:
	for a in z._hitboxes:
		if is_instance_valid(a) and a.get_meta("hit_zone", "") == ("head" if head else "torso"):
			return a.global_position
	return z.global_position + Vector3.UP * 1.2

func _aim_at(pt: Vector3) -> float:
	var cam: Vector3 = p.camera.global_position
	var d := (pt - cam).normalized()
	p.yaw = lerp_angle(p.yaw, atan2(-d.x, -d.z), 0.45)
	p.pitch = lerpf(p.pitch, asin(clampf(d.y, -1.0, 1.0)), 0.45)
	var fwd: Vector3 = -p.camera.global_transform.basis.z
	return rad_to_deg(fwd.angle_to(d))

## Would a shot from the camera reach this infected (not a prop or a door)?
func _line_of_fire(z: Node, head: bool) -> bool:
	var from: Vector3 = p.camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, _aim_point(z, head), 1 | 8, [p.get_rid()])
	q.collide_with_areas = true
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.collider is Area3D and hit.collider.get_meta("enemy", null) == z

func _best_gun() -> String:
	var order := ["m12", "p9", "vk18", "longshot", "hornet", "carbine", "bastion", "breacher", "gl", "bolt", "flamer"]
	for id in order:
		if p.inventory.has_weapon(id):
			var w: Dictionary = WeaponDB.WEAPONS[id]
			if p.inventory.mag.get(id, 0) > 0 or p.inventory.ammo_count(w["ammo"]) > 0:
				return id
	return "knife" if p.inventory.has_weapon("knife") else ""

## Fight one infected until it's down (or we give up), with real damage.
func fight(z: Node, weapon := "", max_t := 30.0) -> bool:
	if _busy_fighting or not is_instance_valid(z):
		return false
	if z.is_in_group("boss"):
		return await fight_warden(z)
	_busy_fighting = true
	var kind: String = z.variant
	_fight_kind = kind
	var use := weapon if weapon != "" else _best_gun()
	if use != "" and p.inventory.equipped != use:
		p.equip(use)
	var end := sim_t + max_t
	var hp0: float = z.hp
	var shot_taken := false
	var last_hp: float = z.hp
	var progress_t := sim_t
	while sim_t < end and is_instance_valid(z) and z.state != ZS.DEAD and not p.downed:
		if p.hp < 40.0:
			_heal()
		var melee: bool = WeaponDB.WEAPONS.get(p.inventory.equipped, {}).get("kind", "") == "melee"
		var to: Vector3 = z.global_position - p.global_position
		to.y = 0
		var dist := to.length()
		var head: bool = kind in ["shambler", "possum"] and not melee and dist < 7.0
		var err := _aim_at(_aim_point(z, head))
		p.aiming = true
		if melee:
			if dist > 1.5:
				_steer(to, false, false)
			else:
				p.move_input = Vector2.ZERO
			p.fire_held = dist < 1.9
		else:
			if dist < 2.6:
				_steer(-to, false, false)   # back off while aiming
			elif dist > 11.0 or not _line_of_fire(z, head):
				# Something in the way (a car, a pillar, a door): side-step
				# and close in, as a player would.
				var side := to.cross(Vector3.UP).normalized() * (1.0 if int(sim_t / 2.0) % 2 == 0 else -1.0)
				_steer(to.normalized() + side * 0.8, false, false)
			else:
				p.move_input = Vector2.ZERO
			# Fire only when the dot is on the body (a player wouldn't spray).
			var tol := 3.0 if dist < 4.0 else (1.2 if head else 1.6)
			p.fire_held = err < tol and p._reloading <= 0.0 and _line_of_fire(z, head)
			var w: Dictionary = WeaponDB.WEAPONS.get(p.inventory.equipped, {})
			if w.has("ammo") and p.inventory.mag.get(p.inventory.equipped, 0) == 0 and p.inventory.ammo_count(w["ammo"]) == 0:
				var g := _best_gun()
				if g == "knife" and _dry_at < 0.0:
					_dry_at = sim_t
					_note("out of gun ammo at %.0fs in %s: %d rounds fired, %d hits (%.0f%%)" % [sim_t, _area_of(p.global_position), _ammo_used, _hits_landed, 100.0 * _hits_landed / maxf(_ammo_used, 1)])
				if g == p.inventory.equipped or g == "":
					break
				if g == "knife" and kind in ["bloater", "brute", "burner", "riot", "spitter", "grappler"]:
					break   # no knifing these: leave it
				p.equip(g)
		if z.hp < last_hp:
			last_hp = z.hp
			progress_t = sim_t
		if sim_t - progress_t > 10.0:
			break   # can't get at it from here; move on
		if not shot_taken and dist < 6.0:
			shot_taken = true
			_shot("fight_" + kind)
		await physics_frame
	_stop()
	_busy_fighting = false
	_fight_kind = ""
	if is_instance_valid(z) and z.state == ZS.DEAD:
		_kills[kind] = _kills.get(kind, 0) + 1
		return true
	if is_instance_valid(z) and not p.downed:
		var gw: Dictionary = WeaponDB.WEAPONS.get(p.inventory.equipped, {})
		var why := "mag %d, %d in the bag, %.1f m off, %s" % [p.inventory.mag.get(p.inventory.equipped, 0), p.inventory.ammo_count(gw.get("ammo", "")) if gw.has("ammo") else 0,
			z.global_position.distance_to(p.global_position), "clear shot" if _line_of_fire(z, false) else "no clear shot"]
		_bug("combat", "couldn't put down a %s (%s) in %.0fs: hp %.0f -> %.0f, state %s, weapon %s (%s)" % [kind, z.look, max_t, hp0, z.hp, ZS.keys()[z.state], p.inventory.equipped, why], "nokill:" + kind)
	return false

func _heal() -> void:
	for id in ["herb_mix", "herb_gg", "herb_green", "medkit", "bandage"]:
		if p.inventory.count(id) > 0:
			p.use_item(id)
			return
	# Out of healing: note it and top up so the run can go on.
	if p.hp < 25.0:
		_note("ran out of healing items at %s (hp %.0f), topping up to keep playing" % [_v(p.global_position), p.hp])
		p.heal(60.0)

## Clear every infected in a room (asleep ones too: a player walking through
## wakes them), then pick up what they dropped.
func clear_area(area: String, max_t := 120.0) -> void:
	await _recover()
	var r: Rect2 = areas[area]
	var end := sim_t + max_t
	var tries := {}
	while sim_t < end and not p.downed:
		var best: Node = null
		var bd := INF
		for z in _zombies():
			if z.state == ZS.HIDDEN or not r.has_point(Vector2(z.global_position.x, z.global_position.z)):
				continue
			if tries.get(z.get_instance_id(), 0) >= 2:
				continue
			var dp: float = z.global_position.distance_to(p.global_position)
			if dp < bd:
				bd = dp
				best = z
		if best == null:
			break
		tries[best.get_instance_id()] = tries.get(best.get_instance_id(), 0) + 1
		if bd > 8.0:
			var to: Vector3 = best.global_position - p.global_position
			await go_to(best.global_position - to.normalized() * 6.5, 25.0, false, "near " + str(best.name) + " ")
		await fight(best)
	await collect_drops(area)

## Pick up what the infected dropped in a room, as a player would.
func collect_drops(area: String) -> void:
	var r: Rect2 = areas[area]
	for d in get_nodes_in_group("pickups"):
		if not is_instance_valid(d) or not str(d.name).begins_with("Drop_") or d._taken:
			continue
		if r.has_point(Vector2(d.global_position.x, d.global_position.z)) and p.inventory.can_take(d.item):
			await pick_up_node(d)

# ================================================================ monitor

func _monitor() -> void:
	sim_t += 1.0 / Engine.physics_ticks_per_second
	if stop_at > 0.0 and sim_t > stop_at:
		stop_at = 0.0
		_finish()
		return
	if shots_dir != "" and int(sim_t * 60.0) % 300 == 0:
		_shot("t%04d" % int(sim_t))
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	# 1. Legs follow real speed (0.7 / 0.9 feedback: running on the spot,
	#    fast legs while slow).
	if not p.downed and not p.input_locked and p.model and p.model._anim and not p.model._one_shot:
		var gs: float = p.sync_speed
		var cur: String = p.model._current
		var nat: float = NAT_SPEED.get(cur, 0.0)
		var bad := ""
		if nat > 0.0 and gs > 0.5:
			var foot: float = nat * p.model._anim.speed_scale
			var ratio := foot / gs
			if ratio > 1.3 or ratio < 0.75:
				bad = "'%s' legs move %.1f m/s while she moves %.1f m/s (playback %.2fx)" % [cur, foot, gs, p.model._anim.speed_scale]
		elif cur == "run" and gs < 1.0:
			bad = "run clip playing at %.1f m/s" % gs
		if bad != "":
			_legs_bad_t += dt
			if _legs_bad_t > 0.4:
				_bug("movement", bad, "legs:" + cur)
		else:
			_legs_bad_t = 0.0
	# 2. Infected strikes: never through a wall (0.9 feedback).
	for z in get_nodes_in_group("zombies"):
		if not is_instance_valid(z):
			continue
		var key: int = z.get_instance_id()
		if z.hp < _zhp.get(key, z.hp) - 0.1:
			_hits_landed += 1
		_zhp[key] = z.hp
		var now: bool = z.state == ZS.ATTACK and z.get("_struck") == true   # the Warden has none
		if now and not _struck.get(key, false):
			_strikes += 1
			var hit: bool = p.hp < _prev_hp
			var clear := _los(z.global_position + Vector3.UP * 1.2, p.global_position + Vector3.UP * 1.2, [z.get_rid(), p.get_rid()])
			if hit and not clear:
				_wall_strikes += 1
				_bug("combat", "a %s hit her through a wall (it at %s, her at %s)" % [z.variant, _v(z.global_position), _v(p.global_position)], "wallhit")
		_struck[key] = now
		if z.global_position.y < -2.0:
			_bug("enemies", "%s fell through the floor at %s" % [z.name, _v(z.global_position)], "fall:" + str(z.name))
	# 2b. Infected never pop into view out of thin air (0.10: by the diner),
	#     and no body lies sunk into the floor (0.10: the one from the ceiling).
	var lvl := _level()
	if lvl != _level_ref:
		_level_ref = lvl
		_level_t = sim_t
		_fresh.clear()
	if not _fresh.is_empty():
		var batch := _fresh
		_fresh = []
		for n in batch:
			if is_instance_valid(n) and n.is_inside_tree():
				_check_popin(n)
	if int(sim_t * 60.0) % 15 == 0:
		_floor_checks()
	# 3. Damage taken and stun lock (0.9 feedback: locked when next to an object).
	if p.hp < _prev_hp - 0.5:
		_damage_taken += _prev_hp - p.hp
	if p._hit_stun > 0.2 and _prev_stun <= 0.0:
		var back: Vector3 = p.body.global_transform.basis.z
		var wall := not _los(p.global_position + Vector3.UP, p.global_position + Vector3.UP + back * 0.8, [p.get_rid()])
		_hits.append([sim_t, wall])
	_prev_stun = p._hit_stun
	while not _hits.is_empty() and sim_t - _hits[0][0] > 5.0:
		_hits.pop_front()
	if _hits.size() >= 4:
		var walled := 0
		for h in _hits:
			walled += int(h[1])
		_bug("combat", "stun lock: hit %d times in 5 s%s, hp %.0f" % [_hits.size(), " with something behind her" if walled > 0 else "", p.hp], "stunlock")
	_prev_hp = p.hp
	# Rounds fired and hits landed (ammo economy).
	var eq: String = p.inventory.equipped
	var m: int = p.inventory.mag.get(eq, 0)
	if _prev_mag.get("id", "") == eq and m < _prev_mag.get("n", 0):
		_ammo_used += _prev_mag["n"] - m
	_prev_mag = {"id": eq, "n": m}
	# 4. Stuck: pushing the stick but not moving (kerbs, props, door frames).
	if p.move_input.length() > 0.6 and not p.aiming and p._hit_stun <= 0.0 and p._attack_lock <= 0.0 and not p.input_locked and not p.downed and not p.pinned:
		if _stuck_ref == Vector3.INF:
			_stuck_ref = p.global_position
			_stuck_t = 0.0
		_stuck_t += dt
		if _stuck_t > 1.5:
			if p.global_position.distance_to(_stuck_ref) < 0.2:
				_bug("movement", "stuck at %s pushing toward %s" % [_v(p.global_position), _v(p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(p.move_input.x, 0, p.move_input.y))], "stuck:%d:%d" % [roundi(p.global_position.x), roundi(p.global_position.z)])
			_stuck_ref = p.global_position
			_stuck_t = 0.0
	else:
		_stuck_ref = Vector3.INF
	if p.global_position.y < -1.5:
		_bug("movement", "fell through the floor at %s" % _v(p.global_position), "pfall")
	# 5. Sounds: infected voices fade with distance and don't overlap
	#    non-stop (0.9 feedback).
	var cam := root.get_viewport().get_camera_3d()
	if cam and current_scene:
		_scan_audio(current_scene, cam.global_position)
	# 6. Music while fighting only ordinary infected (no brute, charger or
	#    boss coming for her): the 0.9 feedback wants no tense track there.
	if _fight_kind != "":
		# A scripted big fight (the generator's crank waves) asks for it.
		var heavy: bool = MUSIC._forced_action > 0.0
		for z in _zombies():
			if z.state in [ZS.CHASE, ZS.ATTACK, ZS.CHARGE, ZS.PINNING] and z.global_position.distance_to(p.global_position) < 18.0:
				var zd: Dictionary = z.data
				if zd.get("boss", false) or zd.get("charge", false) or zd.get("bulk", 1.0) >= 1.5:
					heavy = true
		if not heavy:
			var tr: String = MUSIC.current_track()
			var key := "%s in the %s" % [tr if tr != "" else "no music", _area_of(p.global_position)]
			_music_log[key] = _music_log.get(key, 0.0) + dt

func _on_node_added(n: Node) -> void:
	var sc: Script = n.get_script()
	if sc == null:
		return
	var path := sc.resource_path
	var enemy := path.ends_with("enemies/zombie.gd")
	var bare_model := path.ends_with("enemies/zombie_model.gd") and not (n.get_parent() != null and n.get_parent().is_in_group("zombies"))
	if not enemy and not bare_model:
		return
	if bare_model:
		_orphans.append(n)
	if _bot_spawning:
		return
	# Placed with the level (or in its first seconds) is not popping in.
	if _level() == null or _level() != _level_ref or sim_t - _level_t < 2.0:
		return
	_fresh.append(n)

## One that just appeared: can her camera see any of it (feet, chest,
## head) with nothing in between? Then it came out of thin air in view.
## Ones spawned behind a shut door, in a crawlspace or round a corner pass.
func _check_popin(n: Node3D) -> void:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null or CUTS.active or not n.is_visible_in_tree():
		return
	if n.is_in_group("zombies") and n.state == ZS.HIDDEN:
		return
	var excl: Array = []
	for pl in get_nodes_in_group("players"):
		excl.append(pl.get_rid())
	if n is CollisionObject3D:
		excl.append(n.get_rid())
	var space := cam.get_world_3d().direct_space_state
	for h in [0.2, 1.0, 1.6]:
		var pt: Vector3 = n.global_position + Vector3.UP * h
		var d := cam.global_position.distance_to(pt)
		if d > 45.0 or not cam.is_position_in_frustum(pt):
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, pt, 1, excl)).is_empty():
			_popins += int(not bugs.has("popin:" + str(n.name)))
			_bug("enemies", "%s appeared out of thin air in plain view, %.0f m from her, at %s in the %s (spawn out of sight or through a door)" % [n.name, d, _v(n.global_position), _area_of(n.global_position)], "popin:" + str(n.name))
			return

## Bodies sunk into the floor: an infected's feet well under the floor, or
## a lying body (dead, playing dead, just landed) with its skin through it.
## The skin is checked on the posed mesh itself (a sample of its vertices
## skinned to the current pose), so a face or an arm in the floor counts.
func _floor_checks() -> void:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var bodies: Array = []
	for z in get_nodes_in_group("zombies"):
		if is_instance_valid(z) and z.is_inside_tree() and z.state != ZS.HIDDEN:
			bodies.append([z, z.get("model")])   # the Warden has no ZombieModel
	for m in _orphans:
		if is_instance_valid(m) and m.is_inside_tree():
			bodies.append([m, m])
	for e in bodies:
		var b: Node3D = e[0]
		var model: Node3D = e[1]
		if model == null or b.global_position.distance_to(p.global_position) > 40.0:
			continue
		var excl: Array = [b.get_rid()] if b is CollisionObject3D else []
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(b.global_position + Vector3.UP * 0.6, b.global_position + Vector3.DOWN * 3.0, 1, excl))
		if hit.is_empty():
			continue
		var floor_y: float = hit.position.y
		if floor_y - b.global_position.y > 0.25:
			_sunk += int(not bugs.has("sunk:" + str(b.name)))
			_bug("enemies", "%s stands %.0f cm inside the floor at %s" % [b.name, (floor_y - b.global_position.y) * 100.0, _v(b.global_position)], "sunk:" + str(b.name))
			continue
		var key := b.get_instance_id()
		var dead: bool = b.is_in_group("zombies") and b.state == ZS.DEAD
		if dead and _floor_checked.has(key):
			continue   # a corpse settles once; checked after its fall
		if sim_t - _floor_checked.get(key, -10.0) < 1.0:
			continue
		var sk := _skeleton(model)
		if sk == null:
			continue
		var hips := sk.find_bone("Hips")
		if hips >= 0 and (sk.global_transform * sk.get_bone_global_pose(hips).origin).y - floor_y > 0.55:
			continue   # on its feet: the feet do the touching
		if dead and b.get_meta("dead_since", -1.0) < 0.0:
			b.set_meta("dead_since", sim_t)
		if dead and sim_t - float(b.get_meta("dead_since")) < 4.0:
			continue
		_floor_checked[key] = sim_t
		var low := _lowest_skin_y(model)
		if floor_y - low > 0.08:
			_sunk += int(not bugs.has("sunk:" + str(b.name)))
			_bug("enemies", "%s lies %.0f cm into the floor at %s in the %s (%s)" % [b.name, (floor_y - low) * 100.0, _v(b.global_position), _area_of(b.global_position), "dead" if dead else "alive"], "sunk:" + str(b.name))

func _skeleton(model: Node) -> Skeleton3D:
	var s := model.find_children("*", "Skeleton3D", true, false)
	return s[0] if not s.is_empty() else null

## Lowest point of a rigged model's skin in its current pose.
func _lowest_skin_y(model: Node) -> float:
	var low := INF
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null or not mi.is_visible_in_tree():
			continue
		var sk: Skeleton3D = mi.get_node_or_null(mi.skeleton)
		if sk == null:
			continue
		var skin: Skin = mi.skin
		var xf: Array = []
		for i in skin.get_bind_count():
			var bi := skin.get_bind_bone(i)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(i))
			xf.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(i))
		var g: Transform3D = sk.global_transform
		for v in _mesh_sample(mi.mesh):
			var acc := Vector3.ZERO
			for bw in v[1]:
				acc += (xf[bw[0]] * v[0]) * bw[1]
			low = minf(low, (g * acc).y)
	return low

## About 1500 vertices of a skinned mesh with their bone weights (cached).
func _mesh_sample(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out: Array = []
	for si in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones = a[Mesh.ARRAY_BONES]
		var weights = a[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or bones.size() == 0 or verts.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		var step := maxi(1, verts.size() / 1500)
		var i := 0
		while i < verts.size():
			var bw: Array = []
			for k in per:
				if weights[i * per + k] > 0.001:
					bw.append([bones[i * per + k], weights[i * per + k]])
			out.append([verts[i], bw])
			i += step
	_mesh_cache[key] = out
	return out

func _scan_audio(node: Node, listener: Vector3) -> void:
	for c in node.get_children():
		if c is AudioStreamPlayer3D:
			var id := c.get_instance_id()
			if not _seen_audio.has(id) and c.playing and c.stream:
				_seen_audio[id] = true
				var path: String = c.stream.resource_path.get_file().get_basename()
				var d: float = c.global_position.distance_to(listener)
				var db := _heard_db(c, d)
				var voice := path.begins_with("zombie_") or path.begins_with("hound_") or path.begins_with("mutant_") or path.begins_with("brute_") or path.begins_with("screamer")
				if voice:
					_voice_starts.append([sim_t, path, d, db])
					if d > 18.0 and db > -14.0:
						_bug("audio", "infected voice '%s' %.0f m away plays at %.0f dB (as loud as one close by)" % [path, d, db], "loudvoice")
		if c.get_child_count() > 0 and not (c is AudioStreamPlayer3D):
			_scan_audio(c, listener)

## Roughly how loud a 3D sound reaches the listener (Godot's own formula).
func _heard_db(a: AudioStreamPlayer3D, d: float) -> float:
	if a.max_distance > 0.0 and d > a.max_distance:
		return -80.0
	var att := 0.0
	match a.attenuation_model:
		AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE:
			att = linear_to_db(1.0 / (d / a.unit_size + 0.00001))
		AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE:
			var x := d / a.unit_size
			att = linear_to_db(1.0 / (x * x + 0.00001))
		AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC:
			att = -20.0 * log(d / a.unit_size + 0.00001)
	return minf(att + a.volume_db, a.max_db)

func _audio_report() -> void:
	# Groan density: how many infected voice lines started per minute, and
	# how many could be heard (louder than -20 dB) at once.
	if _voice_starts.is_empty():
		_note("no infected voices heard at all")
		return
	# Only the ambient groans (idle / chase) count toward "non-stop": attack,
	# alert and death cries follow what the player does.
	var span: float = maxf(sim_t - _voice_starts[0][0], 1.0)
	var audible := 0
	var groans := 0
	for v in _voice_starts:
		if v[3] > -20.0:
			audible += 1
			var id: String = str(v[1]).get_file()
			# "swipe" is the whoosh of a swinging arm, not a voice.
			if not (id.contains("attack") or id.contains("swipe") or id.contains("alert") or id.contains("death") or id.contains("shriek") or id.contains("slam") or id.contains("roar")):
				groans += 1
	var per_min := audible / span * 60.0
	var groans_min := groans / span * 60.0
	_note("infected voices: %d started, %d audible (> -20 dB), %.0f audible per minute, %.0f of them groans" % [_voice_starts.size(), audible, per_min, groans_min])
	if groans_min > 30.0:
		_bug("audio", "infected groan almost non-stop: %.0f audible groans a minute" % groans_min, "growlrate")

# ================================================================ the run

func _main() -> void:
	await _frames(3)
	if only == "probe":
		await _run_probe()
	if only == "scares":
		await _run_scares()
	if only == "probe2":
		await _run_probe2()
	if only == "warden2":
		await _run_warden2()
	if only in ["", "route"]:
		await _run_route()
	if only in ["", "route", "route2"]:
		await _run_route2()
	if only in ["", "weapons"]:
		await _run_weapons()
	if only in ["", "bag"]:
		await _run_bag()
	if only in ["", "save"]:
		await _run_save()
	if only in ["", "death"]:
		await _run_death()
	_finish()

func _finish() -> void:
	_audio_report()
	if not _music_log.is_empty():
		var parts := []
		for k in _music_log:
			parts.append("%s %.0fs" % [k, _music_log[k]])
		_note("music while fighting ordinary infected: " + ", ".join(parts))
		var tense := 0.0
		var calm := 0.0
		for k in _music_log:
			if str(k).begins_with(MUSIC.FIGHT_TRACK) and MUSIC.FIGHT_TRACK != "":
				tense += _music_log[k]
			else:
				calm += _music_log[k]
		if tense > 10.0:
			_bug("music", "the fight track played %.0f s of %.0f s of fights with only ordinary infected (%s)" % [tense, tense + calm, ", ".join(parts)], "music_action")
	_note("kills: %s; damage taken %.0f; strikes %d (through walls %d); infected appearing in view %d; bodies sunk into the floor %d" % [JSON.stringify(_kills), _damage_taken, _strikes, _wall_strikes, _popins, _sunk])
	print("PLAYTEST DONE %d bugs" % bugs.size())
	for k in bugs:
		print("  - ", bugs[k])
	quit(0 if bugs.is_empty() else 1)

func _start_solo() -> void:
	NET.start_solo(character)
	change_scene_to_file(GS.level_path)
	await _frames(4)
	var end := sim_t + 20.0
	while get_first_node_in_group("players") == null and sim_t < end:
		await physics_frame
	p = get_first_node_in_group("players")
	_prev_hp = p.hp
	areas = AREAS2 if GS.level_path == UNDERCROFT else AREAS

## Level integrity, once per level: places where you can walk off the floor
## into the void (a room side with no wall and nothing next to it), and
## infected placed overlapping props (they get pushed through the floor).
func probe_level() -> void:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var step := 0.25
	var floor_at := {}
	var bounds := Rect2(-28, -36, 52, 64)
	if areas != AREAS:
		bounds = Rect2()
		for k in areas:
			bounds = areas[k] if bounds.size == Vector2.ZERO else bounds.merge(areas[k])
		bounds = bounds.grow(2.0)
	var x := bounds.position.x
	while x < bounds.end.x:
		var z := bounds.position.y
		while z < bounds.end.y:
			# A hair off the grid: a ray exactly on the seam between two
			# floor slabs (x = -20.0) slips between them and reads as void.
			var q := PhysicsRayQueryParameters3D.create(Vector3(x + 0.013, 0.6, z + 0.017), Vector3(x + 0.013, -0.6, z + 0.017), 1)
			floor_at[Vector2i(roundi(x / step), roundi(z / step))] = not space.intersect_ray(q).is_empty()
			z += step
		x += step
	# From every spot on the navmesh, 0.75 m out (past the mesh's 0.45 m
	# margin): no floor there and no wall in between means she can walk off.
	var holes := {}
	var map: RID = p.get_world_3d().navigation_map
	for c in floor_at:
		if not floor_at[c]:
			continue
		var here := Vector3(c.x * step, 0.0, c.y * step)
		if _area_of(here) == "outside":
			continue
		var snap := NavigationServer3D.map_get_closest_point(map, here)
		if Vector2(snap.x - here.x, snap.z - here.z).length() > 0.05:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d * 3
			if floor_at.get(n, true):
				continue
			var there := Vector3(n.x * step, 0.0, n.y * step)
			var blocked := false
			for h in [0.3, 1.0, 1.6]:
				var q2 := PhysicsRayQueryParameters3D.create(here + Vector3.UP * h, there + Vector3.UP * h, 1)
				if not space.intersect_ray(q2).is_empty():
					blocked = true
			if not blocked:
				var k := "%d,%d" % [roundi(here.x), roundi(here.z)]
				holes[k] = here
	if not holes.is_empty():
		var where := []
		for k in holes:
			where.append(_area_of(holes[k]) + " " + _v(holes[k]))
		where.sort()
		_bug("level", "%d spots where you can walk off the floor into the void: %s" % [holes.size(), ", ".join(where.slice(0, 12))], "voidedge")
	for zz in get_nodes_in_group("zombies"):
		var shape: CollisionShape3D = null
		for ch in zz.get_children():
			if ch is CollisionShape3D:
				shape = ch
		if shape:
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = shape.shape
			sq.transform = shape.global_transform
			sq.collision_mask = 1
			sq.margin = -0.02
			var over := space.intersect_shape(sq, 4)
			if not over.is_empty():
				var what := []
				for o in over:
					what.append(str(o.collider.get_parent().name if o.collider.get_parent() else o.collider.name))
				_bug("level", "%s (%s) is placed inside %s at %s" % [zz.name, zz.variant, ", ".join(what), _v(zz.global_position)], "spawnin:" + str(zz.name))
		if zz.global_position.y < -0.3:
			_bug("level", "%s (%s) is below the floor right after the level loads, at %s" % [zz.name, zz.variant, _v(zz.global_position)], "spawnfall:" + str(zz.name))
	# Items sunk into a prop (a crate, a jerrycan) get no 'Pick up' prompt
	# from any side: something blocks her line of sight well short of them
	# (the same rule as Player._nearest_pickup).
	for pk in get_nodes_in_group("pickups"):
		var pos: Vector3 = pk.global_position + Vector3.UP * 0.15
		var seen := 0
		var by := ""
		for k in 8:
			var a := k * TAU / 8.0
			var eye := Vector3(pos.x + cos(a) * 0.8, pk.global_position.y + 1.0 if pk.global_position.y > 0.6 else 1.0, pos.z + sin(a) * 0.8)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, pos, 1, [p.get_rid()]))
			if hit.is_empty() or hit.position.distance_to(pos) <= 0.4:
				seen += 1
			else:
				by = str(hit.collider.get_parent().name if hit.collider.get_parent() else hit.collider.name)
		if seen == 0:
			_bug("level", "item %s at %s is hidden inside %s: no 'Pick up' prompt from any side" % [pk.pickup_id, _v(pk.global_position), by], "pickin:" + str(pk.pickup_id))
	# Scares wired to nothing (0.10: "the dead wake up" in the Great Hall
	# fired with no one lying there): a wake-up needs infected in its group
	# lying in wait, a shutter or a room scare needs that node in the level.
	var lvl := _level()
	for t in lvl.get_children():
		if not str(t.name).begins_with("Scare_"):
			continue
		var sid: String = t.scare_id
		match str(t.kind):
			"wake_dead":
				var lying := 0
				for zz in get_nodes_in_group(t.group):
					if zz.state == ZS.PLAY_DEAD:
						lying += 1
				if lying == 0:
					_bug("level", "scare '%s' wakes the dead in group '%s', but no infected is lying there in that group" % [sid, t.group], "scarewire:" + sid)
			"shutter_burst":
				var sh: Node = lvl.find_child(t.room, true, false)
				if sh == null or not sh.has_method("burst") or t.spots.is_empty():
					_bug("level", "scare '%s' has no shutter '%s' or no infected behind it" % [sid, t.room], "scarewire:" + sid)
			"lights_out":
				if lvl.get_node_or_null(NodePath(t.room)) == null:
					_bug("level", "scare '%s' turns out the lights in '%s', which isn't in the level" % [sid, t.room], "scarewire:" + sid)
	# Infected waiting up in a vent (the ventling): there must be a vent above
	# it, and nothing of it on the floor until it comes out (0.10: an
	# invisible body stood in the West corridor, soaking shots meant for the
	# bloater and waking up unseen).
	for zz in get_nodes_in_group("zombies"):
		if zz.state != ZS.HIDDEN:
			continue
		if zz._vent_above() == null:
			_bug("level", "%s (%s) waits hidden at %s with no vent above it: it would come out of a bare ceiling" % [zz.name, zz.variant, _v(zz.global_position)], "novent:" + str(zz.name))
		var solid: bool = zz.collision_layer != 0
		for hb in zz._hitboxes:
			if is_instance_valid(hb) and hb.collision_layer != 0:
				solid = true
		if solid:
			_bug("level", "%s (%s) is up in its vent, but an invisible body at %s can still be bumped into or shot" % [zz.name, zz.variant, _v(zz.global_position)], "hiddensolid:" + str(zz.name))

## Quick level check (about a minute): the level probe, then 25 s with
## her standing at the start under god mode while the infected settle and
## wander, watching for any that drop through the floor.
func _run_probe() -> void:
	GS.reset_run()
	GS.set_flag("story_intro")
	await _start_solo()
	CHEATS.set_cheat("god_mode", true)
	await _wait(1.0)
	if CUTS.active:
		CUTS._on_skip_pressed()
	probe_level()
	await _wait(25.0)
	CHEATS.set_cheat("god_mode", false)

## The scripted scares that bring infected in (0.10 feedback: three popped
## up out of thin air by the diner; one fell from the ceiling and lay alive
## half inside the floor). She walks into each trigger looking where a
## player would; the monitor flags any infected that appears in her view
## and any body in the floor, and this checks they come in their way and
## get up and come for her.
func _run_scares() -> void:
	GS.reset_run()
	GS.set_flag("story_intro")
	await _start_solo()
	CHEATS.set_cheat("god_mode", true)
	await _wait(1.0)
	if CUTS.active:
		CUTS._on_skip_pressed()
	await _wait(1.5)
	var lvl := _level()
	# 1. The diner: walking east past the shopfronts, eyes on the diner.
	var sh: Node = lvl.find_child("DinerShutter", true, false)
	if sh == null:
		_bug("scares", "the diner has no roller shutter (DinerShutter)")
	await _scare_walk(Vector3(1.0, 0.2, -25.0), Vector3(4.2, 0.2, -25.0), Vector3(7.0, 1.3, -29.8))
	var t0 := sim_t
	var came := await _scare_arrivals("diner_shutter_w", 3, 4.0)
	if sh and not await _until_t(func(): return sh.is_open, 8.0):
		_bug("scares", "the diner shutter never went up")
	_note("diner shutter up %.1f s after she got there" % (sim_t - t0))
	var out := 0
	var end := sim_t + 12.0
	while sim_t < end and out < came.size():
		out = 0
		for z in came:
			if not is_instance_valid(z) or z.state == ZS.DEAD or z.global_position.z > -29.5:
				out += 1
		await physics_frame
	if out < came.size():
		var where := []
		for z in came:
			if is_instance_valid(z) and z.global_position.z <= -29.5:
				where.append(_v(z.global_position))
		_bug("scares", "%d of the %d infected from the diner never came out (still at %s)" % [came.size() - out, came.size(), ", ".join(where)])
	for z in came:
		if is_instance_valid(z) and z.state != ZS.DEAD:
			await fight(z, "", 20.0)
	# 2. The reading room: walking up to the rifle, the ceiling caves in.
	await _scare_walk(Vector3(-15.6, 0.05, 3.4), Vector3(-15.8, 0.05, 1.0), Vector3(-19.0, 1.0, -3.8))
	var drop := await _scare_arrivals("reading_drop_body", 1, 3.0)
	if not drop.is_empty():
		var z: Node = drop[0]
		var landed := await _until_t(func(): return not is_instance_valid(z) or z._drop_phase >= 2 or z._drop_phase == 0, 4.0)
		if not landed:
			_bug("scares", "the infected from the ceiling never landed (at %s)" % _v(z.global_position))
		elif is_instance_valid(z):
			_note("the infected from the ceiling landed at %s" % _v(z.global_position))
			var up := await _until_t(func(): return not is_instance_valid(z) or z.state in [ZS.CHASE, ZS.ATTACK, ZS.STAGGER, ZS.DEAD], 6.0)
			if not up:
				_bug("scares", "the infected from the ceiling lay there and never got up (state %d at %s)" % [z.state, _v(z.global_position)])
			elif is_instance_valid(z) and absf(z.global_position.y) > 0.12:
				_bug("scares", "the infected from the ceiling got up at the wrong height, %s" % _v(z.global_position))
			if is_instance_valid(z) and z.state != ZS.DEAD:
				await fight(z, "", 20.0)
	# 3. The Great Hall: walking toward the vault between two bodies on the
	# floor, both get up at once (the far one is out of its own 2.2 m reach,
	# so only the scare can wake it).
	var dead: Array = get_nodes_in_group("hall_dead")
	if dead.size() < 2:
		_bug("scares", "'the dead wake up' in the Great Hall has %d infected lying there, not 2" % dead.size())
	await _scare_walk(Vector3(-5.0, 0.05, 12.0), Vector3(-8.0, 0.05, 15.2), Vector3(-8.4, 0.4, 13.3))
	var all_up := func() -> bool:
		for z in dead:
			if is_instance_valid(z) and z.state == ZS.PLAY_DEAD:
				return false
		return true
	if not dead.is_empty() and not await _until_t(all_up, 1.5):
		var still := []
		for z in dead:
			if is_instance_valid(z) and z.state == ZS.PLAY_DEAD:
				still.append(str(z.name))
		_bug("scares", "'the dead wake up' in the Great Hall: walking between them, %s stayed lying" % ", ".join(still))
	elif not dead.is_empty():
		_note("the Great Hall dead got up together as she walked between them")
	for z in dead:
		if is_instance_valid(z) and z.state != ZS.DEAD:
			await fight(z, "", 20.0)
	# 4. The West corridor: shooting down it at the bloater doesn't hit (or
	# wake) anything unseen; walking under the vent, the ventling bursts out
	# of it and lands on its feet.
	var vent_z: Node = lvl.get_node_or_null("Z_corr_vent")
	if vent_z == null:
		_bug("scares", "no ventling in the West corridor (Z_corr_vent)")
	else:
		await _scare_walk(Vector3(-11.0, 0.05, 5.7), Vector3(-13.6, 0.05, 6.2), Vector3(-22.0, 1.2, 6.5))
		var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, Vector3(-22.0, 1.2, 6.5), 1 | 4 | 8, [p.get_rid()])
		q.collide_with_areas = true
		var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit.collider == vent_z or hit.collider.get_meta("enemy", null) == vent_z):
			_bug("scares", "a shot down the West corridor hits the ventling while it's still hidden in the vent")
		if vent_z.state != ZS.HIDDEN:
			_bug("scares", "the ventling left its vent before she came near (state %d)" % vent_z.state)
		await _scare_walk(Vector3(-13.6, 0.05, 6.2), Vector3(-16.2, 0.05, 6.4), Vector3(-18.4, 2.6, 6.4))
		if not await _until_t(func(): return not is_instance_valid(vent_z) or vent_z.state != ZS.HIDDEN, 1.5):
			_bug("scares", "walking under the vent, the ventling never came out")
		elif is_instance_valid(vent_z):
			await _wait(1.2)
			if is_instance_valid(vent_z) and vent_z.state != ZS.DEAD:
				if not vent_z.model.visible:
					_bug("scares", "the ventling came out of its vent invisible")
				elif absf(vent_z.model.position.y) > 0.05 or absf(vent_z.global_position.y) > 0.12:
					_bug("scares", "the ventling didn't land on the floor (body %.2f, model %.2f)" % [vent_z.global_position.y, vent_z.model.position.y])
				else:
					_note("the ventling burst out of the corridor vent and landed")
				await fight(vent_z, "", 20.0)
	var bloater: Node = lvl.get_node_or_null("Z_corr_1")
	if is_instance_valid(bloater) and bloater.state != ZS.DEAD:
		await fight(bloater, "", 25.0)
	CHEATS.set_cheat("god_mode", false)

## Stand at `from` looking at `look`, then step to `to` (inside the trigger).
func _scare_walk(from: Vector3, to: Vector3, look: Vector3) -> void:
	await _recover()
	_stop()
	p.global_position = from
	p.velocity = Vector3.ZERO
	var d := look - (to + Vector3.UP * 1.5)
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.6, 0.6)
	await _wait(0.6)
	p.global_position = to
	p.velocity = Vector3.ZERO
	_stuck_ref = Vector3.INF

## The infected a scare brings in (named `prefix`...), once they're there.
func _scare_arrivals(prefix: String, want: int, max_t: float) -> Array:
	var found: Array = []
	var end := sim_t + max_t
	while sim_t < end and found.size() < want:
		found = []
		for z in get_nodes_in_group("zombies"):
			if str(z.name).begins_with(prefix):
				found.append(z)
		await physics_frame
	if found.size() < want:
		_bug("scares", "the '%s' scare brought %d infected, not %d" % [prefix, found.size(), want])
	return found

func _until_t(cond: Callable, max_t: float) -> bool:
	var end := sim_t + max_t
	while sim_t < end:
		if cond.call():
			return true
		await physics_frame
	return false

func _run_route() -> void:
	# A brand-new game, as from Play Solo.
	GS.reset_run()
	await _start_solo()
	# ---- intro
	var end := sim_t + 12.0
	while not CUTS.active and sim_t < end:
		await physics_frame
	probe_level()
	if not CUTS.active:
		_bug("cutscene", "the intro didn't start on a new game")
	else:
		await _wait_cutscene_end(6.0)
	if not GS.has_flag("story_intro"):
		_bug("cutscene", "intro finished but story_intro flag not set")
	_shot("street_start")
	# ---- Ashgrove Street: clear it, pick everything up.
	p.equip("p9")
	await clear_area("street", 180.0)
	await pick_up("street_ammo_1")
	await pick_up("street_herb_1")
	await clear_area("street", 60.0)
	# ---- the gates scene, then the courtyard gate
	await go_to(Vector3(0, 0, -17.0), 40.0, true, "gates ")
	end = sim_t + 6.0
	while not CUTS.active and sim_t < end:
		await physics_frame
	if CUTS.active:
		await _wait_cutscene_end(3.0)
	elif not GS.has_flag("story_gates"):
		_bug("story", "the gates scene didn't start at the Archive gates")
	await open_door("courtyard_gate", Vector3(0, 0, -15.6), Vector3(0, 1, -14))
	await cross(Vector3(0, 0, -15.6), Vector3(0, 0, -12.2), "the courtyard gate")
	_shot("courtyard")
	await clear_area("courtyard", 90.0)
	await pick_up("court_shells")
	await pick_up("court_m12")
	if not p.inventory.has_weapon("m12"):
		_bug("pickups", "no shotgun in the bag after the courtyard pickup")
	# ---- Great Hall
	await open_door("hall_main", Vector3(0, 0, -3.6), Vector3(0, 1, -2))
	await cross(Vector3(0, 0, -3.6), Vector3(0, 0, -0.2), "the hall doors")
	_shot("great_hall")
	await clear_area("hall", 180.0)
	await pick_up("hall_desk_ammo")
	await pick_up("hall_file_1")
	# ---- Office (safe room) and the warden
	await open_door("office_door", Vector3(10.6, 0, 2.6), Vector3(12, 1, 2.6))
	await cross(Vector3(10.6, 0, 2.6), Vector3(13.4, 0, 2.6), "the office door")
	end = sim_t + 6.0
	while not CUTS.active and sim_t < end:
		await physics_frame
	if CUTS.active:
		await _wait_cutscene_end(3.0)
	elif not GS.has_flag("story_warden"):
		_bug("story", "the warden scene didn't start at the office door")
	await go_to(Vector3(16, 0, 4), 20.0, true, "safe room ")
	_shot("safe_room")
	if GS.shared_checkpoint != "safe_office":
		_bug("checkpoint", "safe room checkpoint not reached (still '%s')" % GS.shared_checkpoint)
	if not MUSIC.in_safe_room:
		_bug("music", "safe room music flag not set inside the safe room")
	await pick_up("office_tape")
	await pick_up("brass_quill_key")
	await pick_up("office_red_herb")
	if not p.inventory.key_items.has("brass_quill_key"):
		_bug("pickups", "brass quill key not in key items")
	# ---- West corridor, the Tallyman at the glass, the reading room
	await cross(Vector3(13.4, 0, 2.6), Vector3(10.4, 0, 2.6), "the office door, going out")
	await cross(Vector3(-10.6, 0, 5.7), Vector3(-13.4, 0, 5.7), "the hall's west doorway")
	await clear_area("corridor", 90.0)
	await go_to(Vector3(-15.6, 0, 6.6), 20.0, true, "glass ")
	end = sim_t + 6.0
	while not CUTS.active and sim_t < end:
		await physics_frame
	if CUTS.active:
		await _wait_cutscene_end(3.0)
	elif not GS.has_flag("story_glass"):
		_bug("story", "the Tallyman glass scene didn't start in the corridor")
	await clear_area("corridor", 60.0)
	await open_door("reading_door", Vector3(-15.4, 0, 6.6), Vector3(-15.4, 1, 5))
	await cross(Vector3(-15.4, 0, 6.6), Vector3(-15.4, 0, 3.4), "the reading room door")
	_shot("reading_room")
	await clear_area("reading", 120.0)
	await pick_up("reading_rifle")
	await pick_up("reading_rifle_ammo")
	# ---- Records vault (the co-op door opens alone in solo) and boiler room
	await cross(Vector3(-15.4, 0, 3.4), Vector3(-15.4, 0, 6.6), "the reading room door, going out")
	await cross(Vector3(-13.4, 0, 5.7), Vector3(-10.4, 0, 5.7), "the hall's west doorway, going back")
	# A co-op door has no prompt in the middle, only at its two handles
	# (beside the frame); alone she uses one and it opens.
	await open_door("vault_door", Vector3(-7.35, 0, 14.9), Vector3(-7.35, 1, 16.3))
	await cross(Vector3(-6, 0, 14.6), Vector3(-6, 0, 17.6), "the vault door")
	_shot("vault")
	await clear_area("vault", 240.0)
	await pick_up("vault_gl")
	await pick_up("vault_gl_ammo")
	await open_door("boiler_door", Vector3(2.6, 0, 20.6), Vector3(4, 1, 20.6))
	await cross(Vector3(2.6, 0, 20.6), Vector3(5.6, 0, 20.6), "the boiler room door")
	_shot("boiler")
	await clear_area("boiler", 90.0)
	await pick_up("boiler_fuel")
	await pick_up("boiler_powder")
	# Anyone left standing in the area? (Before the ride: it loads chapter 2,
	# with a new survivor node and chapter 2's infected.)
	var left := []
	for z in _zombies():
		if z.state != ZS.HIDDEN:
			left.append("%s(%s) at %s" % [z.name, ZS.keys()[z.state], _v(z.global_position)])
	if not left.is_empty():
		_note("infected still standing after the route: " + ", ".join(left))
	_note("chapter 1 route finished at %.0fs, hp %.0f, died %d times, bag %s" % [sim_t, p.hp, _deaths, JSON.stringify(p.inventory.to_dict().get("slots", []))])
	await _power_and_lift()

## The end of the first area: throw the vault breaker in the boiler room,
## back through the vault to the elevator, the key card, into the car and
## down. All through the real prompts (the 0.10 breaker had none).
func _power_and_lift() -> void:
	var breaker: Node = current_scene.find_child("BreakerPanel", true, false)
	var lift: Node = current_scene.find_child("VaultElevator", true, false)
	if breaker == null or lift == null:
		_bug("power", "breaker panel or vault elevator missing from the level")
		return
	var n: Vector3 = breaker.global_transform.basis.z
	var panel: Vector3 = breaker.global_position + breaker.global_transform.basis * Vector3(0.25, 1.3, 0.0)
	var stand := Vector3(panel.x, 0.0, panel.z) + n * 1.0
	if not await go_to(stand, 40.0, true, "breaker "):
		await _warp(stand, "to the breaker")
	await face(panel)
	if not await use_thing("Turn on the power", "the breaker panel"):
		return
	await _wait(3.0)
	if not GS.has_flag("power:vault"):
		_bug("power", "threw the breaker and the vault power didn't come on")
		return
	_shot("power_on")
	await cross(Vector3(5.6, 0, 20.6), Vector3(2.6, 0, 20.6), "the boiler room door (back)")
	var ln: Vector3 = lift.global_transform.basis.z
	var front: Vector3 = lift.global_position + ln * 1.2
	if not await go_to(front, 40.0, true, "elevator "):
		await _warp(front, "to the elevator")
	await face(lift.doors_point())
	if not await use_thing("key card", "the vault elevator"):
		return
	await _wait(3.0)
	if not lift.is_open:
		_bug("power", "used the key card and the elevator doors stayed shut")
		return
	await cross(front, lift.ride_spot(0), "the elevator doors")
	if not lift.in_car(p.global_position):
		_bug("power", "couldn't walk into the elevator car (stopped at %s)" % _v(p.global_position))
		return
	await face(lift.doors_point())
	if not await use_thing("Go down", "inside the elevator"):
		return
	await _wait(0.5)
	if not CUTS.active or CUTS.current != "elevator":
		_bug("power", "'Go down' didn't start the ride")
		return
	await _wait_cutscene_end(3.0)
	if not GS.has_flag("story_elevator"):
		_bug("power", "the ride ended without the story_elevator flag")
	_note("rode the vault elevator: chapter 1 done at %.0fs" % sim_t)

# ---------------------------------------------------------------- chapter 2

## Chapter 2's level check (the Undercroft): the same probe as the first
## area, then 25 s standing in the lift while the infected settle.
func _run_probe2() -> void:
	GS.reset_run()
	GS.level_path = UNDERCROFT
	GS.shared_checkpoint = "ch2_lift"
	GS.set_flag("story_c2_arrival")
	await _start_solo()
	CHEATS.set_cheat("god_mode", true)
	await _wait(1.0)
	if CUTS.active:
		CUTS._on_skip_pressed()
	probe_level()
	await _wait(25.0)
	CHEATS.set_cheat("god_mode", false)

## Chapter 2 played through like a person: the arrival, every room cleared
## and picked over, the master clock, the Tallyman's hunt, the diesel, the
## tannoy, the Warden, cranking the generator through its waves, the flood
## door and the deep stacks. After the first area's route it carries on in
## the same run (her bag from chapter 1); on its own (`only route2`) she
## starts at the lift with what a player usually has by then.
func _run_route2() -> void:
	# Straight on from chapter 1's ride (the elevator scene sets the level),
	# or chapter 2 on its own.
	var chained: bool = GS.level_path == UNDERCROFT and GS.has_flag("story_elevator")
	if not chained:
		GS.reset_run()
		GS.level_path = UNDERCROFT
		GS.shared_checkpoint = "ch2_lift"
		await _start_solo()
		# About what's left at the end of chapter 1 (tools/balance_report.py).
		p.inventory.add_weapon("m12")
		p.inventory.add_ammo("9mm", 30)
		p.inventory.add_ammo("shells", 8)
		p.inventory.add_item("herb_green", 2)
	else:
		# Off the elevator: the new level loads, then its first scene.
		await _until_t(func(): return _level() != null and _level().name == "Undercroft" and get_first_node_in_group("players") != null, 20.0)
		await _wait(0.5)
		p = get_first_node_in_group("players")
		_prev_hp = p.hp
		areas = AREAS2
	if _level() == null or _level().name != "Undercroft":
		_bug("chapter2", "chapter 2's level didn't load (%s)" % GS.level_path)
		return
	var t0 := sim_t
	# ---- the arrival
	if not await _until_t(func(): return CUTS.active, 12.0):
		_bug("chapter2", "the arrival scene didn't start in the lift")
	else:
		await _wait_cutscene_end(4.0)
	if not GS.has_flag("story_c2_arrival"):
		_bug("chapter2", "arrival finished but story_c2_arrival not set")
	var lift = get_first_node_in_group("vault_elevator")
	if lift == null or not lift.is_open:
		_bug("chapter2", "the lift doors didn't open after the arrival")
	_shot("c2_lift")
	p.equip("p9")
	# Out of the car (the navmesh was baked with its doors shut).
	await cross(Vector3(-1.3, 0, 3.0), Vector3(1.6, 0, 3.0), "the lift doors")
	await pick_up("c2_lift_ammo")
	# ---- the service tunnel
	await clear_area("corridor", 120.0)
	await pick_up("c2_corr_herb")
	# ---- the engine hall: its scene, then the generator's three gaps
	await go_to(Vector3(40.6, 0, 3.0), 40.0, true, "engine hall ")
	if await _until_t(func(): return CUTS.active, 6.0):
		await _wait_cutscene_end(3.0)
	elif not GS.has_flag("story_c2_hall"):
		_bug("chapter2", "walking into the engine hall didn't start its scene")
	await clear_area("hall", 90.0)
	for id in ["c2_hall_ammo", "c2_hall_powder", "c2_hall_fuel"]:
		await pick_up(id)
	var gen: Node = _level().find_child("GeneratorSet", true, false)
	# ---- the keeper's lodge (the safe room)
	await open_door("lodge_door", Vector3(11.0, 0, 3.4), Vector3(11.0, 1, 4.6))
	await cross(Vector3(11.0, 0, 3.4), Vector3(11.0, 0, 6.0), "the lodge door")
	_shot("c2_lodge")
	for id in ["c2_ledger", "c2_lodge_ribbon", "c2_lodge_herb", "c2_lodge_shells"]:
		await pick_up(id)
	# ---- the survey room: the winding key
	await cross(Vector3(11.0, 0, 6.0), Vector3(11.0, 0, 3.0), "the lodge door (out)")
	await open_door("survey_door", Vector3(12.0, 0, 2.7), Vector3(12.0, 1, 1.4))
	await cross(Vector3(12.0, 0, 2.7), Vector3(12.0, 0, 0.0), "the survey room door")
	_shot("c2_survey")
	await clear_area("survey", 90.0)
	for id in ["c2_clock_key", "c2_survey_note", "c2_survey_ammo"]:
		await pick_up(id)
	if not p.inventory.key_items.has("clock_key"):
		_bug("chapter2", "no winding key after the survey room")
	# ---- the clock gallery and the master clock
	await open_door("gallery_west_door", Vector3(20.1, 0, -4.4), Vector3(21.0, 1, -4.4))
	await cross(Vector3(20.1, 0, -4.4), Vector3(22.2, 0, -4.4), "the gallery door")
	_shot("c2_gallery")
	await clear_area("gallery", 90.0)
	for id in ["c2_gallery_shells", "c2_gallery_red"]:
		await pick_up(id)
	var clock: Node = _level().find_child("MasterClock", true, false)
	var front: Vector3 = clock.global_position + clock.global_basis.z * 1.5
	if not await go_to(front, 30.0, true, "master clock "):
		await _warp(front, "to the master clock")
	await face(clock.global_position + Vector3.UP * 1.1)
	if await use_thing("Wind the master clock", "the master clock"):
		await _wait(9.0)
		if not GS.has_flag("c2_clock_open"):
			_bug("chapter2", "wound the master clock and its drawer didn't open")
	_shot("c2_clock")
	await pick_up("c2_fuse")
	if not p.inventory.key_items.has("fuse"):
		_bug("chapter2", "no fuse after the master clock")
	# ---- the hunt
	if await _until_t(func(): return CUTS.active, 12.0):
		await _wait_cutscene_end(3.0)
	if not GS.has_flag("story_c2_hunt"):
		_bug("chapter2", "taking the fuse didn't bring the Tallyman")
	# ---- the coal yard: the diesel (he follows; she keeps moving)
	await go_to(Vector3(57.0, 0, 2.0), 60.0, true, "the coal yard ")
	_shot("c2_yard")
	await clear_area("yard", 150.0)
	for id in ["c2_diesel", "c2_yard_ammo", "c2_yard_shells", "c2_yard_herb"]:
		await pick_up(id)
	if not p.inventory.key_items.has("diesel_can"):
		_bug("chapter2", "no diesel after the coal yard")
	# ---- diesel and fuse in
	await _gen_use(gen, Vector3(-0.1, 0, 0), Vector3(0, 0, 1), 1.0, "Pour in the diesel")
	await _gen_use(gen, Vector3(0.7, 0, 0), Vector3(0, 0, 1), 1.9, "Fit the fuse")
	if not (gen.fitted("fuel") and gen.fitted("fuse")):
		_bug("chapter2", "diesel and fuse not both in the generator")
	# ---- Hardass on the tannoy: it waits until she's clear of the Tallyman
	if not await _evade_until(func(): return CUTS.active or GS.has_flag("story_c2_intercom"), 90.0):
		_bug("chapter2", "the tannoy scene never started after the diesel and fuse (Tallyman %s)" % _stalker_where())
	if CUTS.active:
		await _wait_cutscene_end(3.0)
	# ---- the muster room and the Warden
	for tries in 3:
		if GS.has_flag("c2_warden_dead"):
			break
		if not GS.has_flag("story_c2_warden"):
			await open_door("muster_door", Vector3(26.1, 0, 3.4), Vector3(26.1, 1, 4.7))
			await cross(Vector3(26.1, 0, 3.4), Vector3(26.1, 0, 6.4), "the muster room door")
			if await _until_t(func(): return CUTS.active, 8.0):
				await _wait_cutscene_end(4.0)
			elif not GS.has_flag("story_c2_warden"):
				_bug("chapter2", "walking into the muster room didn't start the Warden scene")
				break
		var b: Node = _level().get_node_or_null("Warden")
		if b == null:
			_bug("chapter2", "no Warden in the muster room after his scene")
			break
		_shot("c2_warden")
		await fight_warden(b)
		await _recover()
	if not GS.has_flag("c2_warden_dead"):
		_bug("chapter2", "couldn't beat the Warden")
		CHEATS.set_cheat("one_hit_kills", true)
		var b: Node = _level().get_node_or_null("Warden")
		if b:
			b.take_hit(9999.0, "p9", "torso", -b.global_basis.z)
		await _wait(2.0)
		CHEATS.set_cheat("one_hit_kills", false)
	await _wait(2.0)
	for id in ["c2_crank", "c2_muster_shells", "c2_muster_ammo", "c2_muster_herb"]:
		await pick_up(id)
	if not p.inventory.key_items.has("crank_handle") and not gen.fitted("crank"):
		_bug("chapter2", "no starting handle after the Warden")
	# Back out through the muster door (doors are walls to the navmesh).
	await cross(Vector3(26.1, 0, 6.4), Vector3(26.1, 0, 3.0), "the muster room door (out)")
	# ---- crank it, seeing off the waves
	await _gen_use(gen, Vector3(-2.0, 0, 0), Vector3(-1, 0, 0), 1.1, "Fit the starting handle")
	await _crank(gen, 300.0)
	if not gen.running():
		_bug("chapter2", "the generator never caught (progress %.2f)" % gen.progress)
		return
	_shot("c2_power")
	await _wait(6.0)
	if not GS.has_flag("c2_flood_open"):
		_bug("chapter2", "the generator runs and the flood door stayed down")
	# ---- the deep stacks
	await clear_area("hall", 60.0)
	await go_to(Vector3(46.0, 0, 14.5), 40.0, true, "the deep stacks ")
	if await _until_t(func(): return CUTS.active, 8.0):
		await _wait_cutscene_end(4.0)
	await pick_up("c2_stacks_ammo")
	if not GS.has_flag("c2_complete"):
		_bug("chapter2", "reached the deep stacks and chapter 2 didn't finish")
	_note("chapter 2 done in %.0fs, hp %.0f, bag %s" % [sim_t - t0, p.hp, JSON.stringify(p.inventory.to_dict().get("slots", []))])

func _stalker_where() -> String:
	var st = get_first_node_in_group("stalker")
	if st == null or not st.active:
		return "gone"
	return "%.1f m away" % st.global_position.distance_to(p.global_position)

## Away from the Tallyman until `cond` holds: to whichever of a few far-off
## spots is furthest from him, again and again (he walks slower than she runs).
func _evade_until(cond: Callable, max_t: float) -> bool:
	var spots := [Vector3(8.5, 0, 3.0), Vector3(36.0, 0, 3.0), Vector3(66.0, 0, 3.0), Vector3(46.0, 0, -4.5), Vector3(28.0, 0, -6.0)]
	var end := sim_t + max_t
	while sim_t < end:
		if cond.call():
			return true
		var st = get_first_node_in_group("stalker")
		var from: Vector3 = st.global_position if st and st.active else p.global_position
		var best: Vector3 = spots[0]
		for s in spots:
			if s.distance_to(from) > best.distance_to(from):
				best = s
		var leg_end := sim_t + 10.0
		var path := _path(best)
		var i := 0
		while sim_t < leg_end and i < path.size() and not cond.call():
			var to: Vector3 = path[i] - p.global_position
			to.y = 0.0
			if to.length() < 0.45:
				i += 1
				continue
			_steer(to, true)
			await physics_frame
		_stop()
		await _wait(0.5)
		await _recover()
	return cond.call()

## One of the generator's parts, through its real prompt.
func _gen_use(gen: Node, local: Vector3, n: Vector3, dist: float, expect: String) -> bool:
	var at: Vector3 = gen.global_transform * local
	var stand: Vector3 = Vector3(at.x, 0, at.z) + n * dist
	# Drops from the waves lying where she stands would take the prompt:
	# a player picks them up first.
	for pk in get_nodes_in_group("pickups"):
		if is_instance_valid(pk) and not pk._taken and Vector2(pk.global_position.x - stand.x, pk.global_position.z - stand.z).length() < 1.6:
			await pick_up_node(pk)
	if not await go_to(stand, 40.0, true, expect + " "):
		await _warp(stand, "to the generator (" + expect + ")")
	await face(Vector3(at.x, 1.0, at.z))
	_stop()
	await _wait(0.2)
	# Something dropped at her feet since: take it, like a player would.
	for i in 3:
		if not p._prompt_text.begins_with("Pick up"):
			break
		p.interact()
		await _wait(0.6)
		await face(Vector3(at.x, 1.0, at.z))
	return await use_thing(expect, "the generator")

## Heave the handle; let go to see off anything that comes close, then go
## back to it (in co-op the partner covers; solo she has to do both).
func _crank(gen: Node, max_t: float) -> void:
	var end := sim_t + max_t
	var lets_go := 0
	while sim_t < end and not gen.running():
		await _recover()
		var z := _threat(7.0)
		if z:
			if p.working == "crank":
				lets_go += 1
			p.stop_work()
			await fight(z)
			continue
		if p.working != "crank":
			await _gen_use(gen, Vector3(-2.0, 0, 0), Vector3(-1, 0, 0), 1.1, "Crank the engine")
			if p.working != "crank":
				_bug("chapter2", "'Crank the engine' didn't put her on the handle")
				return
		await _wait(0.25)
	_note("cranking: %.0f s, let go %d times to fight, waves %d, progress %.2f" % [max_t - (end - sim_t), lets_go, gen._waves_done, gen.progress])

## Just the Warden fight, the bot's way (for working on his fight):
## `-- only warden2`.
func _run_warden2() -> void:
	GS.reset_run()
	for f in ["story_c2_arrival", "c2_arrival", "story_c2_hall", "story_c2_hunt", "c2_hunt", "c2_hunt_over", "story_c2_intercom", "story_c2_warden", "c2_clock_open", "taken:c2_fuse"]:
		GS.set_flag(f)
	GS.level_path = UNDERCROFT
	GS.shared_checkpoint = "ch2_lift"
	await _start_solo()
	p.inventory.add_weapon("m12")
	p.inventory.add_ammo("9mm", 45)
	p.inventory.add_ammo("shells", 12)
	p.inventory.add_item("herb_green", 2)
	var b: Node = _level().get_node_or_null("Warden")
	if b == null:
		_bug("chapter2", "no Warden in the muster room on a load")
		return
	await _warp(Vector3(26.0, 0, 6.4), "into the muster room")
	await fight_warden(b)
	if not GS.has_flag("c2_warden_dead"):
		_bug("chapter2", "couldn't beat the Warden")

## The Warden: legs while the shield is up (or round to the growth on his
## back), anything once it's gone, the growth whenever he kneels, and keep
## out of his reach.
func fight_warden(b: Node) -> bool:
	if _busy_fighting or not is_instance_valid(b):
		return false
	_busy_fighting = true
	_fight_kind = "warden"
	var end := sim_t + 240.0
	var hp0: float = b.hp
	var last_hp: float = b.hp
	var progress_t := sim_t
	var gun := _best_gun()
	if gun != "":
		p.equip(gun)
	while sim_t < end and is_instance_valid(b) and b.state != ZS.DEAD and not p.downed:
		if p.hp < 45.0:
			_heal()
		var to: Vector3 = b.global_position - p.global_position
		to.y = 0.0
		var dist: float = to.length()
		var kneeling: bool = b._act == "kneel"
		var zone := "torso"
		if kneeling:
			zone = "wound"
		elif b._shield_hp > 0.0:
			zone = "leg"
		var aim_pt: Vector3 = b.global_position + Vector3.UP * 1.2
		for a in b._hitboxes:
			if is_instance_valid(a) and a.get_meta("hit_zone", "") == zone:
				aim_pt = a.global_position
		var err: float = _aim_at(aim_pt)
		p.aiming = true
		# Keep 4 to 7 m off him, circling so his charge goes into a wall.
		var side := to.cross(Vector3.UP).normalized() * (1.0 if int(sim_t / 3.0) % 2 == 0 else -1.0)
		if dist < 4.0 and not kneeling:
			_steer(-to.normalized() + side * 0.6, false, false)
		elif dist > 8.0:
			_steer(to.normalized() + side * 0.5, false, false)
		else:
			p.move_input = Vector2.ZERO
		var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, aim_pt, 1 | 8, [p.get_rid()])
		q.collide_with_areas = true
		var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
		var clear: bool = hit.is_empty() or (hit.collider is Area3D and hit.collider.get_meta("enemy", null) == b)
		p.fire_held = err < (2.5 if dist < 5.0 else 1.6) and p._reloading <= 0.0 and clear
		if OS.has_environment("WARDEN_DEBUG") and Engine.get_physics_frames() % 60 == 0:
			print("WDBG t=%.1f dist %.1f err %.1f clear %s hit %s gun %s mag %d fire %s act '%s' zone %s" % [sim_t, dist, err, clear, (str(hit.collider.name) + ":" + str(hit.collider.get_meta("hit_zone", ""))) if not hit.is_empty() else "-", p.inventory.equipped, p.inventory.mag.get(p.inventory.equipped, 0), p.fire_held, b._act, zone])
		var w: Dictionary = WeaponDB.WEAPONS.get(p.inventory.equipped, {})
		if w.has("ammo") and p.inventory.mag.get(p.inventory.equipped, 0) == 0 and p.inventory.ammo_count(w["ammo"]) == 0:
			var g := _best_gun()
			if g == "" or g == "knife" or g == p.inventory.equipped:
				_note("out of ammo against the Warden at hp %.0f of %.0f" % [b.hp, b.max_hp])
				break
			p.equip(g)
		if b.hp < last_hp:
			last_hp = b.hp
			progress_t = sim_t
		if sim_t - progress_t > 25.0:
			_note("no damage on the Warden for 25 s (hp %.0f, act '%s', shield %.0f)" % [b.hp, b._act, b._shield_hp])
			break
		await physics_frame
	_stop()
	_busy_fighting = false
	_fight_kind = ""
	var won: bool = is_instance_valid(b) and b.state == ZS.DEAD
	_note("Warden fight: hp %.0f -> %.0f in %.0f s, she has hp %.0f%s" % [hp0, b.hp if is_instance_valid(b) else 0.0, 240.0 - (end - sim_t), p.hp, ", won" if won else ""])
	if won:
		_kills["warden"] = 1
	return won

# ---------------------------------------------------------------- weapons

## Every weapon: it fires (or swings / throws), makes a sound, uses ammo and
## hurts an infected standing in front of her.
func _run_weapons() -> void:
	if p == null or not is_instance_valid(p) or _level() == null or GS.level_path == UNDERCROFT:
		GS.reset_run()
		GS.level_path = "res://scenes/levels/archive_hub.tscn"
		GS.set_flag("story_intro")
		await _start_solo()
	CHEATS.set_cheat("all_weapons", true)
	CHEATS.set_cheat("god_mode", true)
	for id in WeaponDB.WEAPONS:
		var w: Dictionary = WeaponDB.WEAPONS[id]
		if w.get("enemy_only", false):
			continue
		await _try_weapon(id, w)
	CHEATS.set_cheat("all_weapons", false)
	CHEATS.set_cheat("god_mode", false)

func _try_weapon(id: String, w: Dictionary) -> void:
	# A fresh dummy 5 m in front, in an open spot of the street.
	var spot := Vector3(0, 0.1, -24)
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	p.pitch = -0.05
	for z in get_nodes_in_group("zombies"):
		if z.global_position.distance_to(spot) < 14.0:
			z.queue_free()
	await physics_frame
	var zname := "Dummy_" + id
	var gap := 1.3 if w["kind"] == "melee" else 5.0   # in reach of a blade, or 5 m off
	_bot_spawning = true   # the bot's own target, not a scare
	_level().spawn_zombie_synced(zname, spot + Vector3(0, 0, -gap), "shambler")
	_bot_spawning = false
	await physics_frame
	var z: Node = _level().get_node_or_null(zname)
	z.state = ZS.IDLE
	z.rotation.y = 0.0
	z.set_physics_process(false)   # stands still for the test
	p.equip(id)
	await _wait(0.3)
	if p.inventory.equipped != id:
		_bug("weapons", "couldn't equip %s" % id)
		return
	if p.held.weapon_id != id:
		_bug("weapons", "%s equipped but %s in her hand" % [id, p.held.weapon_id])
	var hp0: float = z.hp
	var sounds_before := _audio_ids()
	var mag0: int = p.inventory.mag.get(id, 0)
	var end := sim_t + 4.0
	var shots_seen := false
	while sim_t < end:
		var err := _aim_at(_aim_point(z))
		p.aiming = true
		if w["kind"] == "melee":
			var to: Vector3 = z.global_position - p.global_position
			to.y = 0
			if to.length() > 1.4:
				_steer(to, false, false)
			else:
				p.move_input = Vector2.ZERO
		p.fire_held = err < 3.0
		await physics_frame
		# A flash grenade blinds (staggers) instead of hurting.
		if z.hp < hp0 or z.state == ZS.DEAD or (id == "flash" and z.state == ZS.STAGGER):
			shots_seen = true
			await _wait(0.4)
			break
	_stop()
	var new_sounds := _audio_ids().filter(func(s): return not sounds_before.has(s))
	var heard := false
	for s in new_sounds:
		if not (s.begins_with("flesh") or s.begins_with("zombie") or s.begins_with("equip") or s.begins_with("blood") or s.begins_with("impact") or s.begins_with("ricochet")):
			heard = true
	_shot("weapon_" + id)
	if not shots_seen:
		_bug("weapons", "%s did nothing to an infected %.1f m in front (mag %d, kind %s)" % [id, gap, mag0, w["kind"]], "nodmg:" + id)
	if not heard and not w.get("silent", false):
		_bug("weapons", "%s made no firing sound (heard only %s)" % [id, str(new_sounds)], "nosound:" + id)
	if is_instance_valid(z):
		z.queue_free()
	await _wait(0.6)

var _audio_seen_ids := {}
func _audio_ids() -> Array:
	var out := []
	_collect_audio(current_scene, out)
	return out

func _collect_audio(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is AudioStreamPlayer3D and c.stream:
			out.append(c.stream.resource_path.get_file().get_basename() + "#" + str(c.get_instance_id()))
		elif c.get_child_count() > 0:
			_collect_audio(c, out)

# ---------------------------------------------------------------- bag

func _run_bag() -> void:
	if p == null or not is_instance_valid(p) or _level() == null or GS.level_path == UNDERCROFT:
		GS.reset_run()
		GS.level_path = "res://scenes/levels/archive_hub.tscn"
		GS.set_flag("story_intro")
		await _start_solo()
	var hud := _hud()
	p.inventory.add_item("herb_green", 1)
	p.inventory.add_item("herb_red", 1)
	hud.toggle_inventory()
	await _wait(0.5)
	var menu: Node = null
	for c in hud.get_children():
		if c.has_method("open") and c.has_method("_refresh_grid"):
			menu = c
	if menu == null:
		menu = _find_by_method(root, "_refresh_grid")
	if menu == null or not menu.visible:
		_bug("bag", "BAG didn't open")
		return
	if not paused:
		_bug("bag", "game keeps running behind the open bag")
	_shot("bag_open")
	# Combine red + green.
	var red := -1
	var green := -1
	for i in p.inventory.slots.size():
		var s = p.inventory.slots[i]
		if s is Dictionary and s.get("id") == "herb_red":
			red = i
		if s is Dictionary and s.get("id") == "herb_green":
			green = i
	if red >= 0 and green >= 0:
		menu._on_slot(red)
		await _frames(2)
		menu._toggle_combine()
		await _frames(2)
		menu._finish_combine(green)
		await _frames(4)
		if p.inventory.count("herb_mix") == 0:
			_bug("bag", "combining red + green ferns didn't make a mixture")
	# Equip from the bag.
	if p.inventory.has_weapon("knife"):
		menu._equip("knife")
		await _frames(2)
		if p.inventory.equipped != "knife":
			_bug("bag", "equipping the knife from the bag didn't take")
	# Examine and close.
	menu._open_examine("p9")
	await _frames(6)
	_shot("bag_examine")
	menu._close_examine()
	await _frames(2)
	hud.toggle_inventory()
	await _frames(4)
	if paused:
		_bug("bag", "game still paused after closing the bag")
		paused = false

func _find_by_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var f := _find_by_method(c, m)
		if f:
			return f
	return null

# ---------------------------------------------------------------- saves

func _run_save() -> void:
	if p == null or not is_instance_valid(p) or _level() == null or GS.level_path == UNDERCROFT:
		GS.reset_run()
		GS.level_path = "res://scenes/levels/archive_hub.tscn"
		GS.set_flag("story_intro")
		await _start_solo()
	var cp: String = GS.shared_checkpoint
	SAVE.request_save("slot1")
	await _wait(0.3)
	var d: Dictionary = SAVE.read_slot("slot1")
	if d.is_empty():
		_bug("saves", "Save wrote nothing")
		return
	var bag_saved: Variant = d.get("inventories", {}).get(character, {})
	# (through JSON both ways: the file has 1.0 where the bag has 1)
	if _norm(bag_saved.get("slots", [])) != _norm(p.inventory.to_dict().get("slots", [])):
		_bug("saves", "saved bag differs from the bag in hand: %s vs %s" % [_norm(bag_saved.get("slots", [])), _norm(p.inventory.to_dict().get("slots", []))])
	# Quit to title and Continue from that save.
	var flags_before: Dictionary = GS.world_flags.duplicate(true)
	var bag_before: String = _norm(p.inventory.to_dict().get("slots", []))
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(10)
	p = null
	SAVE.apply_snapshot(SAVE.read_slot("slot1"))
	await _start_solo()
	await _wait(1.0)
	if GS.shared_checkpoint != cp:
		_bug("saves", "loaded at checkpoint '%s', saved at '%s'" % [GS.shared_checkpoint, cp])
	if _norm(p.inventory.to_dict().get("slots", [])) != bag_before:
		_bug("saves", "bag after loading differs from the saved bag: %s vs %s" % [_norm(p.inventory.to_dict().get("slots", [])), bag_before])
	for k in flags_before:
		if not GS.world_flags.has(k):
			_bug("saves", "world flag %s lost after loading" % k, "flaglost")
	if CUTS.active:
		_bug("saves", "a cutscene (%s) replays after loading a save" % CUTS.current)
		await _wait_cutscene_end(0.5)

func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))

# ---------------------------------------------------------------- dying

## Solo death: she goes down, the game over screen comes, Continue puts her
## back at the checkpoint with the run as it was there, not an old save.
func _run_death() -> void:
	if p == null or not is_instance_valid(p) or _level() == null or GS.level_path == UNDERCROFT:
		GS.reset_run()
		GS.level_path = "res://scenes/levels/archive_hub.tscn"
		GS.set_flag("story_intro")
		await _start_solo()
	# A stale autosave from some other run sits on the phone.
	var stale: Dictionary = SAVE.build_snapshot()
	stale["checkpoint"] = "start"
	stale["flags"] = {"story_intro": true, "stale_marker": true}
	stale["inventories"] = {}
	SAVE._write(SAVE.AUTOSAVE_SLOT, stale)
	var cp: String = GS.shared_checkpoint
	var bag: String = JSON.stringify(p.inventory.to_dict().get("slots", []))
	var z: Node = null
	for x in _zombies():
		z = x
	p.apply_damage(p.hp + 50.0, z)
	await _wait(0.5)
	if not p.downed:
		_bug("death", "she didn't go down at 0 hp")
	var screen: Node = null
	var end := sim_t + 15.0
	while sim_t < end and screen == null:
		screen = _find_by_method(_level(), "show_votes")
		await physics_frame
	if screen == null:
		_bug("death", "no game over screen after dying")
		return
	end = sim_t + 12.0
	while sim_t < end and not screen._buttons.visible:
		await physics_frame
	_shot("game_over")
	if not screen._buttons.visible:
		_bug("death", "Continue / Quit buttons never appeared (12 s)")
	screen._on_continue()
	await _frames(10)
	end = sim_t + 15.0
	while sim_t < end and (get_first_node_in_group("players") == null or get_first_node_in_group("players") == p):
		await physics_frame
	p = get_first_node_in_group("players")
	if p == null:
		_bug("death", "Continue didn't bring the level back")
		return
	_prev_hp = p.hp
	await _wait(1.0)
	if Engine.time_scale != 1.0:
		_bug("death", "game stuck in slow motion after Continue (%.2f)" % Engine.time_scale)
	if p.downed or p.hp <= 0.0:
		_bug("death", "she's still down after Continue")
	if GS.has_flag("stale_marker"):
		_bug("death", "Continue after dying loaded an old autosave from another run (back to '%s', bag emptied) instead of this run's checkpoint '%s'" % [GS.shared_checkpoint, cp], "stale_autosave")
	elif GS.shared_checkpoint != cp:
		_bug("death", "Continue put her at '%s', the checkpoint was '%s'" % [GS.shared_checkpoint, cp])
	_shot("after_continue")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saves/autosave.json"))
