extends SceneTree
## The extra infected that co-op and Hard bring (scripts/levels/extra_infected.gd)
## and the difficulty numbers behind them.
##  1. Each level at the highest pressure: every extra is there, stands on
##     floor with room around it, on the infected's navigation, clear of the
##     checkpoints the survivors come in at, of items and of the other
##     infected. At Normal solo none of them is there; at pressure 2 only
##     tier 2.
##  2. Groups grow with pressure (scares, the generator's waves), never
##     shrink, and the waves never gain a brute.
##  3. Drop rolls: the table as written at chance 1.0 (drawn exactly as
##     before), scaled by the chance otherwise.
##  4. Difficulty numbers: Easy softer than Normal softer than Hard, and a
##     save remembers it (old saves read as Normal).
## godot --headless --path . --fixed-fps 60 --script tests/extra_infected.gd
## Prints "EXTRA ok/FAIL ..." and "EXTRA DONE n fails".

const LEVELS := ["res://scenes/levels/archive_hub.tscn", "res://scenes/levels/undercroft.tscn"]
## How near the survivors' way in an extra may stand (m).
const CHECKPOINT_CLEAR := 7.0
var GS: Node
var fails: Array = []

func _initialize() -> void:
	GS = root.get_node("GameState")
	create_timer(240.0).timeout.connect(func():
		print("EXTRA FAIL timed out")
		quit(1))
	_main.call_deferred()

func _check(cond: bool, what: String) -> void:
	print("EXTRA %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails.append(what)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _main() -> void:
	_numbers()
	for path in LEVELS:
		await _level(path, 3)
		await _level(path, 2)
		await _level(path, 1)
	print("EXTRA DONE %d fails" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)

func _load(path: String, pressure: int) -> Node:
	GS.reset_run()
	for f in ["story_intro", "story_c2_arrival"]:
		GS.set_flag(f)
	root.get_node("Net").start_solo("obcera")
	GS.set_difficulty("hard")
	GS.test_pressure = pressure
	change_scene_to_file(path)
	await _frames(6)
	var end := Time.get_ticks_msec() + 20000
	while get_first_node_in_group("players") == null and Time.get_ticks_msec() < end:
		await physics_frame
	await _frames(4)
	return current_scene

func _level(path: String, pressure: int) -> void:
	var lvl := await _load(path, pressure)
	var short := path.get_file().get_basename()
	var list: Array = lvl.ExtraInfected.for_level(path)
	_check(not list.is_empty(), "%s has extra infected listed" % short)
	var names := {}
	for e in list:
		_check(not names.has(e["name"]), "%s: %s listed once" % [short, e["name"]])
		names[e["name"]] = true
		var z: Node3D = lvl.get_node_or_null(NodePath(e["name"]))
		var want: bool = int(e["tier"]) <= pressure
		if not want:
			_check(z == null, "%s at pressure %d: tier %d %s stays out" % [short, pressure, e["tier"], e["name"]])
			continue
		_check(z != null and z.is_in_group("zombies"), "%s at pressure %d: %s (tier %d) is in the level" % [short, pressure, e["name"], e["tier"]])
		if z == null or pressure != 3:
			continue
		_spot(lvl, short, e)

## Where an extra stands (checked from its listed spot, before it has moved).
func _spot(lvl: Node3D, short: String, e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var n: String = e["name"]
	var space: PhysicsDirectSpaceState3D = lvl.get_world_3d().direct_space_state
	var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.8, at + Vector3.DOWN * 0.8, 1))
	_check(not down.is_empty() and absf(down.position.y - at.y) < 0.3, "%s: %s has floor under it at %s" % [short, n, at])
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4 if e.get("variant", "") != "crawler" else 0.3
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), at + Vector3.UP * 0.95)
	var hit: Array = space.intersect_shape(q, 4)
	var what := ", ".join(hit.map(func(h): return str(h.collider.get_parent().name if h.collider and h.collider.get_parent() else "?")))
	_check(hit.is_empty(), "%s: %s has room to stand at %s%s" % [short, n, at, "" if hit.is_empty() else " (inside " + what + ")"])
	var map: RID = lvl.get_world_3d().navigation_map
	var on_nav: Vector3 = NavigationServer3D.map_get_closest_point(map, at)
	_check(Vector2(on_nav.x, on_nav.z).distance_to(Vector2(at.x, at.z)) < 0.6, "%s: %s stands on the infected's navigation (nearest %s)" % [short, n, on_nav])
	for c in get_nodes_in_group("checkpoints"):
		for i in 2:
			var sp: Vector3 = c.spawn_transform(i).origin
			var d := Vector2(sp.x, sp.z).distance_to(Vector2(at.x, at.z))
			if d < CHECKPOINT_CLEAR:
				_check(false, "%s: %s stands %.1f m from where the survivors come in at %s" % [short, n, d, c.checkpoint_id])
		if c.is_safe_room:
			var box: Shape3D = c.get_child(0).shape if c.get_child_count() > 0 and c.get_child(0) is CollisionShape3D else null
			if box is BoxShape3D:
				var local: Vector3 = c.global_transform.affine_inverse() * at
				var hb: Vector3 = box.size / 2.0
				_check(not (absf(local.x) < hb.x and absf(local.z) < hb.z), "%s: %s isn't in the safe room %s" % [short, n, c.checkpoint_id])
	for p in get_nodes_in_group("pickups"):
		var d: float = Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(at.x, at.z))
		if d < 1.0:
			_check(false, "%s: %s stands on item %s (%.1f m)" % [short, n, p.name, d])
	for z in get_nodes_in_group("zombies"):
		if z.name == n:
			continue
		var d: float = Vector2(z.global_position.x, z.global_position.z).distance_to(Vector2(at.x, at.z))
		if d < 1.2:
			_check(false, "%s: %s stands %.1f m from %s" % [short, n, d, z.name])

func _numbers() -> void:
	GS.reset_run()
	var D: Dictionary = GS.DIFFICULTY
	for k in ["enemy_damage", "enemy_health", "boss_health"]:
		_check(D["easy"][k] < D["normal"][k] and D["normal"][k] < D["hard"][k], "%s: Easy < Normal < Hard" % k)
	for k in ["ammo", "drops", "revive"]:
		_check(D["easy"][k] > D["normal"][k] and D["normal"][k] > D["hard"][k], "%s: Easy > Normal > Hard" % k)
	_check(D["normal"]["enemy_damage"] == 1.0 and D["normal"]["enemy_health"] == 1.0 and D["normal"]["ammo"] == 1.0 and D["normal"]["drops"] == 1.0, "Normal is the game as balanced")
	# Pressure: Normal solo is the base game; co-op and Hard add.
	var cases := [["easy", 0, 0], ["easy", 1, 1], ["normal", 0, 1], ["normal", 1, 2], ["hard", 0, 2], ["hard", 1, 3]]
	for c in cases:
		GS.set_difficulty(c[0])
		GS.mode = c[1]
		_check(GS.pressure() == c[2], "pressure %s %s is %d (got %d)" % [c[0], "co-op" if c[1] == 1 else "solo", c[2], GS.pressure()])
		for n in [1, 3, 5]:
			_check(GS.group_size(n) >= n, "a group of %d never shrinks (%s)" % [n, c[0]])
		if c[2] <= 1:
			_check(GS.group_size(3) == 3, "a group of 3 stays 3 at pressure %d" % c[2])
	GS.set_difficulty("hard")
	GS.mode = 1
	_check(GS.group_size(3) == 5 and GS.group_size(5) == 9, "Hard co-op: 3 become 5, 5 become 9 (got %d, %d)" % [GS.group_size(3), GS.group_size(5)])
	var mix: Array = GS.grown_mix(["brute", "shambler", "runner", "shambler", "shambler"])
	_check(mix.size() == GS.group_size(5) and mix.count("brute") == 1, "a wave grows with shamblers and runners, still one brute (%s)" % [mix])
	GS.mode = 0
	GS.set_difficulty("normal")
	GS.test_pressure = -1
	# Drop rolls.
	var WDB: GDScript = load("res://scripts/weapons/weapon_db.gd")
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 99
	r2.seed = 99
	var same := true
	for i in 200:
		# The table as written, drawn the way it always was.
		var entries: Array = WDB.DROPS["zombie"]
		var total := 0
		for e in entries:
			total += e[1]
		var r := r2.randi_range(1, total)
		var want := "none"
		for e in entries:
			r -= e[1]
			if r <= 0:
				want = e[0]
				break
		if WDB.roll_drop("zombie", r1, 1.0) != want:
			same = false
	_check(same, "drop rolls at chance 1.0 come out exactly as before")
	for chance in [0.36, 0.6, 1.4]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var got := 0
		for i in 4000:
			if WDB.roll_drop("zombie", rng, chance) != "none":
				got += 1
		var expect := minf(1.0, 0.6 * chance)
		_check(absf(got / 4000.0 - expect) < 0.03, "zombie drop chance x%.2f: %.2f (expect %.2f)" % [chance, got / 4000.0, expect])
	# A save keeps the difficulty; one from before reads as Normal.
	var SS: Node = root.get_node("SaveSystem")
	GS.set_difficulty("hard")
	var d: Dictionary = SS.build_snapshot()
	_check(d.get("difficulty", "") == "hard", "a save carries its difficulty")
	_check(SS.describe(d)["difficulty"] == "hard", "the save screen reads it back")
	GS.set_difficulty("easy")
	SS.apply_snapshot(d)
	_check(GS.difficulty == "hard", "loading the save brings Hard back")
	d.erase("difficulty")
	SS.apply_snapshot(d)
	_check(GS.difficulty == "normal", "an old save without one plays on Normal")
	_check(GS.ammo_amount(15) == 15, "Normal: a 9mm box holds 15")
	GS.set_difficulty("hard")
	_check(GS.ammo_amount(15) == 11 and GS.ammo_amount(1) == 1, "Hard: a 9mm box holds 11, never less than one round (got %d)" % GS.ammo_amount(15))
	GS.set_difficulty("easy")
	_check(GS.ammo_amount(6) == 9, "Easy: a box of 6 shells holds 9")
	GS.set_difficulty("normal")
