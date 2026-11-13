class_name Breakable
extends Node3D
## Things in the world that bullets, blades, blasts and fire break, the way
## the genre has taught players to expect:
##
##   fuel_drum  red drum of fuel. Any bullet punches a hole, a tongue of
##              burning fuel spits out and it goes up a beat later. A blast
##              nearby sets it off too (drums chain), and fire (the
##              flamethrower, a burning pool) cooks it off after a couple of
##              seconds. Kills or knocks down every infected around it, hurts
##              survivors too, leaves a torn scorched wreck and a burning pool.
##   propane    gas cylinder: the same, a sharper, smaller bang.
##   jerrycan   fuel can: a small fireball and a burning splash.
##   wood       wooden barrel or crate: splinters apart (crates can drop an
##              item, see drop_table).
##   glass      a window pane: shatters; jagged shards stay in the frame and
##              bullets fly on through.
##   lamp       a light fixture: the bulb bursts in sparks and the light dies.
##
## Co-op: the phone that shoots tells the host, the host decides, and every
## phone plays the same event at once (Combat.breakable_event). Broken things
## stay broken across saves and retries (GameState flag "broken:<id>").

const KINDS := {
	"fuel_drum": {"explosive": true, "damage": 250.0, "radius": 5.0, "fuse": 0.22, "cook": 2.4,
		"sound": "barrel_blast", "pool": 1.7, "pool_t": 9.0},
	"propane": {"explosive": true, "damage": 200.0, "radius": 4.2, "fuse": 0.15, "cook": 1.6, "sound": "propane_burst"},
	"jerrycan": {"explosive": true, "damage": 120.0, "radius": 3.0, "fuse": 0.18, "cook": 1.3,
		"sound": "barrel_blast", "pool": 1.2, "pool_t": 6.0},
	"wood": {"hp": 45.0, "sound": "wood_break"},
	"glass": {"hp": 1.0, "sound": "glass_break"},
	"lamp": {"hp": 1.0, "sound": "bulb_pop"},
}
const DRUM_MODEL := "res://assets/props/fuel_drum/fuel_drum.glb"
const WRECK_MODEL := "res://assets/props/fuel_drum_wreck/fuel_drum_wreck.glb"
const DRUM_H := 0.88        # a 200-litre drum: 88 cm tall, 58 cm across
const DRUM_R := 0.29

static var _all := {}       # id -> Breakable

@export var kind := "fuel_drum"
var breakable_id := ""
var drop_table := ""        # wood: WeaponDB.DROPS table rolled when it's smashed
var hp := 1.0
var broken := false
var model: Node3D           # what you see before it breaks
var body: CollisionObject3D # what bullets (and, for solid things, people) hit
var lights: Array = []      # lamp: the lights it feeds
var glass: MeshInstance3D   # glass: the pane
var pane := Vector2.ONE     # glass: its size in metres
var center := Vector3(0, 0.45, 0)   # local point blasts and blades measure to
var _bulbs: Array = []      # lamp: [mesh instance, surface index] of bulb and glass parts
var _fuse := -1.0           # host: seconds until it goes up
var _jet: Node3D            # burning fuel spitting from a hole
var _cook := 0.0            # seconds left of shaking while it cooks off
var _model_at := Vector3.ZERO

static func of(col: Object) -> Breakable:
	if col and col.has_meta("breakable"):
		var b: Variant = col.get_meta("breakable")
		if is_instance_valid(b):
			return b
	return null

static func find(id: String) -> Breakable:
	var b: Variant = _all.get(id)
	return b if is_instance_valid(b) else null

func explosive() -> bool:
	return KINDS[kind].get("explosive", false)

func _ready() -> void:
	add_to_group("breakables")
	if breakable_id == "":
		var g := global_position * 10.0
		breakable_id = "%s@%d,%d,%d" % [kind, roundi(g.x), roundi(g.y), roundi(g.z)]
	_all[breakable_id] = self
	hp = KINDS[kind].get("hp", 1.0)
	set_physics_process(false)
	if GameState.has_flag("broken:" + breakable_id):
		broken = true
		_show_broken(false)

func _exit_tree() -> void:
	if _all.get(breakable_id) == self:
		_all.erase(breakable_id)

# ------------------------------------------------------------ building

## A fuel drum, propane cylinder or jerrycan standing at `pos` (parent space).
## `id` keeps it broken in saves; give every placed one its own.
static func make(parent: Node3D, kind_: String, pos: Vector3, rot_deg := 0.0, id := "", prop := "") -> Breakable:
	var b := Breakable.new()
	b.kind = kind_
	b.breakable_id = id
	b.name = ("Breakable_" + id) if id != "" else "Breakable_%s_%d" % [kind_, parent.get_child_count()]
	b.position = pos
	b.rotation_degrees.y = rot_deg
	match kind_:
		"fuel_drum":
			b._build_drum()
		"propane":
			b._build_prop("propane_tank", true)
		"jerrycan":
			b._build_prop("metal_jerrycan", false)
		"wood":
			b._build_prop(prop, false)
	parent.add_child(b)   # after building: a drum saved as blown loads as its wreck
	return b

func _build_drum() -> void:
	if ResourceLoader.exists(DRUM_MODEL):
		model = (load(DRUM_MODEL) as PackedScene).instantiate()
		var box := RoomBuilder._aabb(model, Transform3D.IDENTITY)
		var k := DRUM_H / maxf(box.size.y, 0.01)
		model.scale = Vector3.ONE * k
		model.position = Vector3(0, -box.position.y * k, 0)
	else:
		model = Node3D.new()
	add_child(model)
	_model_at = model.position
	var cyl := CylinderShape3D.new()
	cyl.radius = DRUM_R
	cyl.height = DRUM_H
	_solid(cyl, Vector3(0, DRUM_H / 2.0, 0))
	center = Vector3(0, DRUM_H * 0.5, 0)

## A Poly Haven prop (propane_tank, metal_jerrycan, Barrel_01, a crate).
func _build_prop(prop: String, round: bool) -> void:
	model = RoomBuilder.prop(self, prop, Vector3.ZERO, 0.0, 1.0, false)
	_model_at = model.position
	var box := RoomBuilder._aabb(model, Transform3D.IDENTITY)
	if box.size.length() < 0.05:
		box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.8, 0.6))
	var shape: Shape3D
	if round:
		var c := CylinderShape3D.new()
		c.radius = maxf(box.size.x, box.size.z) * 0.5
		c.height = box.size.y
		shape = c
	else:
		var bs := BoxShape3D.new()
		bs.size = box.size
		shape = bs
	_solid(shape, box.get_center())
	center = box.get_center()

func _solid(shape: Shape3D, at: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	sb.add_child(cs)
	sb.set_meta("breakable", self)
	add_child(sb)
	body = sb

## Makes a window pane breakable. `glass` is the pane (a QuadMesh), `sb` the
## body that keeps people in; it stays, so the window still can't be climbed.
static func make_glass(parent: Node3D, glass_: MeshInstance3D, sb: StaticBody3D, size: Vector2, id: String) -> Breakable:
	var b := Breakable.new()
	b.kind = "glass"
	b.breakable_id = id
	b.name = "Breakable_" + id.validate_node_name()
	b.glass = glass_
	b.pane = size
	b.body = sb
	sb.set_meta("breakable", b)
	b.position = glass_.position   # the pane is a child of the same room
	b.center = Vector3.ZERO
	parent.add_child(b)
	return b

## Makes a light fixture shootable: a small target round its bulb or glass,
## wired to the lights it feeds. `fixture` is the prop (from RoomBuilder.prop).
static func make_lamp(fixture: Node3D, lights_: Array, id: String) -> Breakable:
	var b := Breakable.new()
	b.kind = "lamp"
	b.breakable_id = id
	b.name = "Breakable_" + id.validate_node_name()
	b.lights = lights_
	var box := AABB()
	var first := true
	for mi in fixture.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf: Transform3D = _local_xf(fixture, mi)
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var nm := (mat.resource_name if mat else "").to_lower()
			if not ("glass" in nm or "bulb" in nm):
				continue
			b._bulbs.append([mi, s])
			var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = xf * v
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	if first:
		box = RoomBuilder._aabb(fixture, Transform3D.IDENTITY)
	b.position = box.get_center()
	b.center = Vector3.ZERO
	# A target a bit bigger than the bulb: on a phone a lamp should be hittable.
	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = clampf(box.size.length() * 0.5, 0.14, 0.35)
	cs.shape = sp
	area.add_child(cs)
	area.set_meta("breakable", b)
	b.add_child(area)
	b.body = area
	fixture.add_child(b)
	return b

static func _local_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

# ------------------------------------------------------------ hits

## A bullet from this phone hit it. Plays what the shooter sees at once and
## asks the host to apply it. Returns true when the shot carries on through
## (glass, a bulb).
func shot(at: Vector3, normal: Vector3, dir: Vector3, dmg: float) -> bool:
	if kind in ["glass", "lamp"]:
		if not broken:
			Combat.hurt_breakable(self, dmg, "bullet", at, dir)
		return true
	if broken:
		Effects.impact(at, normal, body)
		return false
	if explosive():
		# Sparks off the steel; the host answers with the burst of flame.
		Effects.impact(at, normal, body)
	else:
		Effects.impact(at, normal, body)
		Effects.splinters(at, 0.3)
	Combat.hurt_breakable(self, dmg, "bullet", at, dir)
	return false

## Host only: something hurt it. how: "bullet", "blade", "blast" or "fire".
func host_damage(dmg: float, how: String, at: Vector3, dir: Vector3) -> void:
	if broken or not multiplayer.is_server():
		return
	if explosive():
		if how == "blade":
			return   # a knife only scrapes a steel drum
		var k: Dictionary = KINDS[kind]
		var fuse: float = k["fuse"]
		match how:
			"blast":
				fuse = randf_range(0.15, 0.4)   # drums go off one after another, not all in one frame
			"fire":
				fuse = k["cook"]
		if _fuse >= 0.0 and _fuse <= fuse:
			return   # already going, and sooner
		var first := _fuse < 0.0
		_fuse = fuse
		set_physics_process(true)
		if first or how == "bullet":
			Combat.breakable_event(breakable_id, "arm", at, dir, fuse)
		return
	if how == "fire":
		return
	hp -= dmg
	if hp <= 0.0:
		Combat.breakable_event(breakable_id, "break", at, dir, 0.0)
		if drop_table != "":
			var drop := WeaponDB.roll_drop(drop_table, RandomNumberGenerator.new())
			var level := get_tree().get_first_node_in_group("level")
			if drop != "none" and level and level.has_method("spawn_pickup"):
				level.spawn_pickup.rpc(drop, global_transform * Vector3(0, 0.08, 0), -1)

func _physics_process(delta: float) -> void:
	if broken or _fuse < 0.0:
		set_physics_process(false)
		return
	_fuse -= delta
	if _fuse <= 0.0 and multiplayer.is_server():
		_fuse = -1.0
		Combat.breakable_event(breakable_id, "explode", global_transform * center, Vector3.UP, 0.0)

func _process(delta: float) -> void:
	if _cook <= 0.0 or model == null:
		set_process(false)
		return
	# Cooking off: the drum rattles harder as it gets closer to going up.
	_cook -= delta
	var s := 0.012 * clampf(1.6 - _cook * 0.5, 0.3, 1.6)
	model.position = _model_at + Vector3(randf_range(-s, s), randf_range(0, s), randf_range(-s, s))

## Every phone: the host says what happened.
func on_event(ev: String, at: Vector3, dir: Vector3, x: float) -> void:
	match ev:
		"arm":
			_arming(at, dir, x)
		"explode":
			_explode()
		"break":
			_break(at, dir)

# ------------------------------------------------------------ what happens

func _arming(at: Vector3, dir: Vector3, fuse: float) -> void:
	if broken:
		return
	var mid := global_transform * center
	var out := at - mid
	out.y = 0.0
	if out.length() < 0.05:
		out = -dir
		out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	if at.distance_to(mid) > 1.5:
		at = mid + out * DRUM_R   # set off by fire or a blast: the leak is on the near side
	Sfx.play_at("barrel_hit", at, "metal_bang", 0.0, 8.0)
	if _jet == null:
		_jet = Effects.fire_jet()
		add_child(_jet)
		_jet.global_position = at
		var up := out.lerp(Vector3.UP, 0.25).normalized()
		var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD).normalized()
		_jet.global_basis = Basis(side, up, side.cross(up))
	if fuse > 0.8:
		Sfx.attach("barrel_hiss", self, 2.0, 7.0)
		_cook = fuse
		set_process(true)

func _explode() -> void:
	if broken:
		return
	broken = true
	_fuse = -1.0
	GameState.set_flag("broken:" + breakable_id)
	var k: Dictionary = KINDS[kind]
	var at := global_transform * center
	if _jet:
		Effects.put_out(_jet)
		_jet = null
	_cook = 0.0
	if kind == "propane":
		Effects.gas_burst(at, k["radius"])
	else:
		Effects.fuel_blast(at, k["radius"])
	_throw_debris(at)
	_show_broken(true)
	Combat.explode(at, k["damage"], k["radius"], kind, 0, k["sound"])
	if multiplayer.is_server() and k.has("pool"):
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("spawn_hazard"):
			level.spawn_hazard.rpc("fire", global_position + Vector3.UP * 0.05, k["pool"], k["pool_t"])

func _break(at: Vector3, dir: Vector3) -> void:
	if broken:
		return
	broken = true
	GameState.set_flag("broken:" + breakable_id)
	var k: Dictionary = KINDS[kind]
	match kind:
		"glass":
			var n := (glass.global_basis.z if glass else Vector3.FORWARD)
			if dir != Vector3.ZERO and n.dot(dir) < 0.0:
				n = -n
			Effects.glass_shatter(at, n, pane.x)
			Sfx.play_at(k["sound"], at, "", 2.0, 10.0)
			_crack_at(at)
		"lamp":
			Effects.lamp_burst(global_position)
			Sfx.play_at(k["sound"], global_position, "glass_break", 0.0, 8.0)
			_show_broken(true)
		"wood":
			Effects.splinters(global_transform * center, 1.0)
			Sfx.play_at(k["sound"], global_transform * center, "", 0.0, 9.0)
			_throw_planks(at, dir)
			_show_broken(true)

## How it looks once broken. live: it's breaking now (not loaded broken).
func _show_broken(live: bool) -> void:
	match kind:
		"fuel_drum":
			if model:
				model.queue_free()
			model = null
			var wreck: Node3D
			if ResourceLoader.exists(WRECK_MODEL):
				wreck = (load(WRECK_MODEL) as PackedScene).instantiate()
				var box := RoomBuilder._aabb(wreck, Transform3D.IDENTITY)
				# The torn petals splay wider than the drum: size it by height.
				# Blown down to a squat, splayed stump, charred black: it must
				# never pass for a drum that's still whole (under the diner's
				# neon the rusty wreck read as an intact red barrel).
				var s := (DRUM_H * 0.86) / maxf(box.size.y, 0.01)
				wreck.scale = Vector3(s * 1.08, s, s * 1.08)
				wreck.position = Vector3(0, -box.position.y * s, 0)
				wreck.rotation = Vector3(deg_to_rad(6.0), _seed_angle(), deg_to_rad(-4.0))
				_char(wreck)
			else:
				wreck = Node3D.new()
			add_child(wreck)
			if live:
				# Still burning inside for a while, then just smoke.
				var f := Effects.make_fire(Vector3(0.18, 0.05, 0.18), 0.7)
				f.position = Vector3(0, DRUM_H * 0.75, 0)
				add_child(f)
				var out := f.create_tween()
				out.tween_interval(24.0)
				out.tween_callback(Effects.put_out.bind(f))
		"propane", "jerrycan", "wood":
			if model:
				model.queue_free()
			model = null
			if body:
				body.queue_free()
			body = null
		"glass":
			if not live:
				_crack_at(Vector3.INF)
		"lamp":
			for l in lights:
				if not is_instance_valid(l):
					continue
				l.set_process(false)
				if live:
					# A last stutter before it dies.
					var e: float = l.light_energy
					var t: Tween = l.create_tween()
					t.tween_property(l, "light_energy", e * 0.15, 0.05)
					t.tween_property(l, "light_energy", e * 0.6, 0.06)
					t.tween_property(l, "light_energy", 0.0, 0.12)
					t.tween_callback(func(): l.visible = false)
				else:
					l.visible = false
			var dead := StandardMaterial3D.new()
			dead.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
			dead.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dead.roughness = 0.35
			for bs in _bulbs:
				if is_instance_valid(bs[0]):
					(bs[0] as MeshInstance3D).set_surface_override_material(bs[1], dead)
			if body:
				body.queue_free()
			body = null

## Swaps the pane for broken glass with a jagged hole where it was hit (or
## blown out across most of it, for a blast or a pane loaded broken).
func _crack_at(at: Vector3) -> void:
	if glass == null or not is_instance_valid(glass):
		return
	var old := glass.material_override as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/broken_glass.gdshader")
	if old:
		m.set_shader_parameter("tint", old.albedo_color)
		m.set_shader_parameter("glow", old.emission)
		m.set_shader_parameter("glow_energy", old.emission_energy_multiplier)
	m.set_shader_parameter("pane", pane)
	var uv := Vector2(0.5, 0.5)
	var hole := maxf(pane.x, pane.y) * 0.62
	if at != Vector3.INF:
		var l := glass.global_transform.affine_inverse() * at
		uv = Vector2(clampf(l.x / pane.x + 0.5, 0.15, 0.85), clampf(0.5 - l.y / pane.y, 0.15, 0.85))
		hole = minf(pane.x, pane.y) * randf_range(0.42, 0.55)
	m.set_shader_parameter("hole_at", uv)
	m.set_shader_parameter("hole", hole)
	m.set_shader_parameter("seed", float(hash(breakable_id) % 1000) / 10.0)
	glass.material_override = m

# ------------------------------------------------------------ debris

## Steel thrown out by a drum: the lid spinning up and away, torn strips.
func _throw_debris(at: Vector3) -> void:
	var mat := _first_material(model)
	if kind == "fuel_drum":
		var lid := CylinderMesh.new()
		lid.top_radius = DRUM_R
		lid.bottom_radius = DRUM_R
		lid.height = 0.025
		lid.radial_segments = 20
		_chunk(lid, mat, at + Vector3.UP * 0.4, Vector3(randf_range(-2, 2), randf_range(9, 12), randf_range(-2, 2)), 25.0)
	var n := 4 if kind == "fuel_drum" else 3
	for i in n:
		var strip := BoxMesh.new()
		strip.size = Vector3(randf_range(0.15, 0.3), 0.012, randf_range(0.08, 0.16))
		var a := TAU * i / n + randf_range(-0.4, 0.4)
		var v := Vector3(cos(a), 0, sin(a)) * randf_range(5, 9) + Vector3.UP * randf_range(4, 8)
		_chunk(strip, mat, at + Vector3(cos(a), 0.2, sin(a)) * 0.3, v, 30.0)

## Staves or planks flying off a smashed barrel or crate.
func _throw_planks(at: Vector3, dir: Vector3) -> void:
	var mat := _first_material(model)
	var box := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.8, 0.6))
	if model:
		box = RoomBuilder._aabb(model, Transform3D.IDENTITY)
	var mid := global_transform * box.get_center()
	var push := dir * Vector3(1, 0, 1)
	for i in 7:
		var plank := BoxMesh.new()
		var tall := i < 4
		plank.size = Vector3(randf_range(0.08, 0.12), box.size.y * randf_range(0.5, 0.95) if tall else 0.02, 0.025 if tall else box.size.z * 0.6)
		if not tall:
			plank.size.x = box.size.x * randf_range(0.4, 0.8)
		var a := TAU * i / 7.0 + randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var v := out * randf_range(1.5, 3.5) + push * 2.0 + Vector3.UP * randf_range(2.0, 4.5)
		_chunk(plank, mat, mid + out * box.size.x * 0.3, v, 12.0)

func _chunk(mesh: Mesh, mat: Material, at: Vector3, vel: Vector3, spin: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var ab := mesh.get_aabb()
	bs.size = Vector3(maxf(ab.size.x, 0.03), maxf(ab.size.y, 0.03), maxf(ab.size.z, 0.03))
	cs.shape = bs
	rb.add_child(cs)
	scene.add_child(rb)
	rb.global_position = at
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-spin, spin), randf_range(-spin, spin), randf_range(-spin, spin))
	# Lie still after a while, then go (keeps the phone's physics light).
	var life := rb.create_tween()
	life.tween_interval(6.0)
	life.tween_callback(rb.set.bind("freeze", true))
	life.tween_interval(34.0)
	life.tween_callback(rb.queue_free)

static func _first_material(n: Node) -> Material:
	if n == null:
		return null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m and m.get_surface_count() > 0:
			var mat := (mi as MeshInstance3D).get_active_material(0)
			if mat:
				return mat
	return null

## The same turn for a wreck every time it loads (from its id), so a retry
## shows it lying the way it did.
func _seed_angle() -> float:
	return float(hash(breakable_id) % 6283) / 1000.0

## Scorch a wreck: darker, duller, the paint burnt off.
static func _char(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			if m == null:
				m = mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var c: StandardMaterial3D = m.duplicate()
				c.albedo_color = Color(c.albedo_color.r * 0.34, c.albedo_color.g * 0.3, c.albedo_color.b * 0.28, c.albedo_color.a)
				c.roughness = 0.95
				c.metallic = minf(c.metallic, 0.2)
				mi.set_surface_override_material(i, c)
