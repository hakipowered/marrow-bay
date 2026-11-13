extends LevelBase
## Chapter 1: RaGoon City. Ashgrove Street (outdoor), the Archive courtyard,
## and the ground floor of the RaGoon City Civic Archive, a grand old records
## building turned emergency shelter, now overrun. Original setting.

const WARM := Color(1.0, 0.78, 0.52)
const COLD := Color(0.62, 0.75, 1.0)
const SICK := Color(0.75, 0.95, 0.7)

func build() -> void:
	_environment()
	_street()
	_diner()
	_courtyard()
	_great_hall()
	_west_corridor()
	_reading_room()
	_office_safe_room()
	_records_vault()
	_boiler_room()
	_horror_beats()
	# Story: the intro, the gates, Hardass, the Tallyman behind the glass.
	var story := Chapter1Story.new()
	story.name = "Story"
	add_child(story)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.02, 0.025, 0.04)
	ps.sky_horizon_color = Color(0.12, 0.08, 0.07)   # city fires on the horizon
	ps.ground_bottom_color = Color(0.01, 0.01, 0.01)
	ps.ground_horizon_color = Color(0.1, 0.07, 0.06)
	sky.sky_material = ps
	env.sky = sky
	# A cold, low fill so shadows stay readable on a phone screen; the
	# practical lights (lamps, fires, chandeliers) do the real work.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.33, 0.42)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.09, 0.11)
	env.fog_density = 0.018
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = COLD
	moon.light_energy = 0.45
	moon.rotation_degrees = Vector3(-55, 30, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	add_child(moon)

# ---------------- Ashgrove Street (open area) ----------------
func _street() -> void:
	# The 24H diner's doorway, behind its shutter (local x 25.2 .. 28.8): no
	# upper-floor window column comes down through it.
	var windows := _facade_windows(40.0, "ashgrove")
	windows["n"] = windows["n"].filter(func(wn): return wn[0] + wn[1] < 25.0 or wn[0] > 29.0)
	var r := RoomBuilder.build(self, {
		"id": "AshgroveStreet", "pos": Vector3(-20, 0, -30), "size": Vector3(40, 9, 16),
		"floor": "street_road", "wall": "facade_brick", "outdoor": true,
		"floor_look": {"tile_size": 4.0, "wetness": 0.8, "puddles": 1.0, "rain": 1.0},
		"wall_look": {"tile_size": 3.0, "grime_amount": 0.7, "grime_height": 1.4, "wall_wet": 1.0},
		"look": {"variation": 0.3},
		"openings": {"s": [[18.0, 4.0, 9.0]], "n": [[25.2, 3.6, 2.6]]},
		"skip_walls": ["e", "w"],
		"windows": windows,
		"decals": {"blood": 4, "stain": 8, "scorch": 2},
		"papers": 30,
		"probe": true,
	})
	_street_dressing(r)
	# Sidewalk strips on both sides.
	for z in [1.5, 14.5]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(40, 0.18, 3)
		mi.mesh = b
		mi.material_override = Mats.surface("sidewalk", {"tile_size": 1.5, "wetness": 0.7, "grime_amount": 0.5, "puddles": 0.6, "rain": 1.0})
		mi.position = Vector3(20, 0.09, z)
		r.add_child(mi)
		# Collision with a gentle ramp on both long edges, so players and
		# the infected walk up the kerb instead of stopping against it.
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var hx: float = b.size.x / 2.0
		var hy: float = b.size.y / 2.0
		var hz: float = b.size.z / 2.0
		var ramp := 0.55
		var pts := PackedVector3Array()
		for sx in [-hx, hx]:
			pts.append_array([Vector3(sx, hy, -hz), Vector3(sx, hy, hz),
				Vector3(sx, -hy, -hz - ramp), Vector3(sx, -hy, hz + ramp)])
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		sb.add_child(cs)
		sb.position = mi.position
		r.add_child(sb)
	# Shopfronts with shutters along the north facade. The diner's (x 27) is
	# a real roller shutter over a doorway: the infected inside force it up
	# (the "diner_shutter" scare).
	for x in [5.0, 13.0, 27.0, 35.0]:
		if x == 27.0:
			var rs := RollShutter.new()
			rs.name = "DinerShutter"
			rs.position = Vector3(x, 0.0, 0.2)
			r.add_child(rs)
			if GameState.has_flag("scare:diner_shutter"):
				rs.open_now()
		else:
			var sh := MeshInstance3D.new()
			var b2 := BoxMesh.new()
			b2.size = Vector3(4.0, 2.8, 0.1)
			sh.mesh = b2
			sh.material_override = Mats.surface("shutter", {"tile_size": 1.6, "grime_amount": 0.6})
			sh.position = Vector3(x, 1.4, 0.2)
			r.add_child(sh)
		RoomBuilder.light(r, Vector3(x, 3.4, 0.8), Color(1.0, 0.45, 0.25) if x == 13.0 else WARM, 0.9, 6.0, false, x == 27.0)
	RoomBuilder.prop(r, "covered_car", Vector3(9, 0, 8), 12)
	RoomBuilder.prop(r, "covered_car", Vector3(30, 0, 6.5), 170)
	RoomBuilder.prop(r, "concrete_road_barrier", Vector3(16, 0, 5), 80)
	RoomBuilder.prop(r, "concrete_road_barrier", Vector3(24, 0, 5.5), 100)
	RoomBuilder.prop(r, "fire_hydrant", Vector3(17.2, 0.18, 13.6))
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_rust", Vector3(3, 0.18, 14))
	RoomBuilder.prop(r, "trashbag", Vector3(3.8, 0.18, 14.4), 40, 1.0, false)
	RoomBuilder.prop(r, "trashbag", Vector3(36, 0.18, 1.8), 10, 1.0, false)
	RoomBuilder.prop(r, "utility_box_01", Vector3(38.5, 0.18, 13.8), -90)
	RoomBuilder.prop(r, "modular_fire_escape", Vector3(32, 2.5, 0.4), 0, 1.0, false)
	RoomBuilder.prop(r, "water_manhole_cover", Vector3(20, 0.01, 8), 0, 1.0, false)
	RoomBuilder.prop(r, "street_rat", Vector3(4.6, 0.18, 13.9), 200, 1.0, false)
	# The middle lamp stands beside the courtyard gate (local x 18..22), not
	# in front of it. Each post gets a slim collider of its own: the box fitted
	# to the whole model (post and arm) was an invisible metre-deep wall.
	# A round through the lamp head bursts it and the light goes out.
	for x in [6.0, 23.4, 34.0]:
		var lamp := RoomBuilder.prop(r, "street_lamp_01", Vector3(x, 0.18, 14.6), 180, 1.0, false)
		_post_collider(r, Vector3(x, 0.18, 14.6), 0.14, 4.6)
		var l := RoomBuilder.light(r, Vector3(x, 4.6, 13.6), Color(1.0, 0.7, 0.4), 2.4, 11.0, x == 23.4, x == 34.0)
		Breakable.make_lamp(lamp, [l], "street_lamp_%d" % int(x))
	# Burning wreck glow at the far end.
	RoomBuilder.light(r, Vector3(30, 1.0, 7), Color(1.0, 0.45, 0.15), 3.0, 9.0, true, true)
	_rain(r, Vector3(20, 9, 8), Vector3(19.5, 0, 7.5))
	# Fuel drums where they pay off: one by the two runners at the east
	# barricade, one beside the diner window the infected smash through.
	Breakable.make(r, "fuel_drum", Vector3(36.4, 0.0, 4.1), 30.0, "street_drum_east")
	Breakable.make(r, "fuel_drum", Vector3(24.9, 0.18, 2.3), 75.0, "street_drum_diner")
	var crate := Breakable.make(r, "wood", Vector3(2.0, 0.18, 12.9), 15.0, "street_crate", "wooden_crate_01")
	crate.drop_table = "crate"
	place_checkpoint("start", Vector3(0, 0, -24), Vector3(6, 3, 6))
	place_zombie("Z_street_1", Vector3(-8, 0, -22), 30, "shambler", false, "cop")
	place_zombie("Z_street_2", Vector3(12.5, 0, -25.6), -60, "shambler", false, "mechanic")
	place_zombie("Z_street_crawl", Vector3(-11, 0, -18.8), 100, "crawler")
	place_zombie("Z_street_run1", Vector3(18, 0, -26), -90, "runner", true)
	place_zombie("Z_street_run2", Vector3(15.5, 0, -22.5), -100, "runner", true)
	place_zombie("Z_street_hound", Vector3(-14, 0, -25.5), 40, "hound", true)
	place_zombie("Z_street_3", Vector3(14, 0, -18), 200, "shambler", true, "jogger")
	place_pickup("ammo:9mm", Vector3(-15, 0.2, -16.2), "street_ammo_1")
	place_pickup("herb_green", Vector3(17, 0.2, -28.5), "street_herb_1")

## The 24H diner behind its shutter on Ashgrove Street: a dark, trashed
## dining room with one dying tube light. Its south side is the street's
## facade (the doorway is cut there). The infected in the "diner_shutter"
## scare are spawned in here, out of sight, and come out through the door.
const DINER_SPOTS := [Vector3(6.4, 0.2, -31.8), Vector3(8.0, 0.2, -33.0), Vector3(6.4, 0.2, -34.1)]

func _diner() -> void:
	var r := RoomBuilder.build(self, {
		"id": "Diner", "pos": Vector3(3.4, 0.18, -35.0), "size": Vector3(7.2, 3.0, 5.0),
		"floor": "clinic_floor", "wall": "plaster_damaged", "wainscot": "facade_tiles", "wainscot_height": 1.0,
		"trim": Color(0.45, 0.07, 0.06),
		"floor_look": {"tile_size": 1.2, "grime_amount": 0.8, "stain_amount": 0.7},
		"wall_look": {"tile_size": 2.0, "grime_amount": 0.7, "stain_amount": 0.6, "tint": Color(0.62, 0.58, 0.5)},
		"skip_walls": ["s"],
		"decals": {"blood": 3, "stain": 4, "wall_blood": 2},
		"papers": 14,
	})
	# Counter down the east side (red front, formica top) with the old TV on
	# it, a booth seat and table in the far corner, the specials board.
	RoomBuilder._box(r, Vector3(6.2, 0.53, 2.3), Vector3(0.6, 1.05, 2.8), Mats.surface("plank_painted", {"tile_size": 1.0, "grime_amount": 0.5, "tint": Color(0.55, 0.12, 0.1)}), true)
	RoomBuilder._box(r, Vector3(6.15, 1.08, 2.3), Vector3(0.74, 0.05, 2.9), Mats.trim(Color(0.75, 0.72, 0.66), 0.35), false)
	RoomBuilder.prop(r, "Television_01", Vector3(6.25, 1.105, 1.3), -100, 1.0, false)
	RoomBuilder.prop(r, "Sofa_01", Vector3(1.45, 0, 0.55), 0)
	RoomBuilder.prop(r, "dining_table", Vector3(1.5, 0, 2.6), 90)
	RoomBuilder.prop(r, "standing_chalkboard_01", Vector3(5.0, 0, 4.4), 200)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(0.5, 0, 4.4), 25)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(4.3, 0, 0.45), -10)
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_rust", Vector3(6.75, 0, 4.4), 0)
	RoomBuilder.prop(r, "trashbag", Vector3(2.6, 0, 4.4), 120, 1.0, false)
	RoomBuilder.prop(r, "trashbag", Vector3(5.2, 0, 0.5), 30, 1.0, false)
	RoomBuilder.prop(r, "wall_clock", Vector3(3.6, 2.3, 0.14), 0, 1.0, false)
	RoomBuilder.prop(r, "mounted_fluorescent_lights", Vector3(3.6, 2.97, 2.4), 90, 1.0, false)
	RoomBuilder.light(r, Vector3(3.6, 2.6, 2.4), Color(0.7, 0.92, 0.8), 0.35, 4.0, false, true)
	# Dark inside: the street's lights (no shadows, so they'd shine through
	# the facade) don't reach in; only its own dying tube does.
	for vi in r.find_children("*", "VisualInstance3D", true, false):
		if vi is GeometryInstance3D:
			vi.layers = 2
	for l in get_node("AshgroveStreet").find_children("*", "Light3D", true, false):
		if not l.shadow_enabled:
			l.light_cull_mask &= ~2

## Rows of upper-floor windows for a street facade: some lit, some dark,
## some boarded. The ground floor is left for shopfronts and doors.
func _facade_windows(length: float, key: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var out := {"n": [], "s": []}
	for side in ["n", "s"]:
		var x := 2.0
		while x < length - 2.0:
			if side == "s" and x > 16.5 and x < 23.5:
				x += 4.0   # courtyard gate
				continue
			for row in [[3.8, 5.6], [6.6, 8.3]]:
				var roll := rng.randf()
				var o := {"moon": 0.0, "opaque": true}
				if roll < 0.18:
					o["lit"] = true
				elif roll < 0.3:
					o["boards"] = 3
				out[side].append([x, 1.3, row[0], row[1], o])
			x += rng.randf_range(3.4, 4.4)
	return out

## Skyline, signs, clutter and the barricaded street ends for Ashgrove Street.
func _street_dressing(r: Node3D) -> void:
	# Uneven skyline: extra storeys and cornices on top of the 9 m facades.
	var blocks := [
		["n", 0.0, 12.0, 3.0, "facade_painted"], ["n", 12.0, 25.0, 0.0, ""], ["n", 25.0, 40.0, 5.5, "facade_tiles"],
		["s", 0.0, 9.0, 4.5, "facade_stone"], ["s", 9.0, 17.0, 1.5, "facade_painted"], ["s", 23.0, 40.0, 2.5, "facade_tiles"],
	]
	for b in blocks:
		var z: float = 0.0 if b[0] == "n" else 16.0
		var inward: float = 1.0 if b[0] == "n" else -1.0
		var len: float = b[2] - b[1]
		var cx: float = (b[1] + b[2]) / 2.0
		if b[3] > 0.0:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(len, b[3], 0.25)
			mi.mesh = bm
			mi.material_override = Mats.surface(b[4], {"tile_size": 3.0, "grime_amount": 0.6})
			mi.position = Vector3(cx, 9.0 + b[3] / 2.0, z)
			r.add_child(mi)
		# Cornice at the top of each block.
		var top: float = 9.0 + b[3]
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(len + 0.3, 0.35, 0.6)
		c.mesh = cm
		c.material_override = Mats.trim(Color(0.32, 0.3, 0.28), 0.8)
		c.position = Vector3(cx, top + 0.1, z + inward * 0.2)
		r.add_child(c)
		# Storey band between ground floor and the flats above.
		var band := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(len, 0.25, 0.3)
		band.mesh = bb
		band.material_override = Mats.trim(Color(0.36, 0.33, 0.3), 0.8)
		band.position = Vector3(cx, 3.3, z + inward * 0.18)
		r.add_child(band)
	# Shop signs: real sign boards (weathered metal, neon tubes, a backlit
	# lightbox, a hotel blade sign) whose glow lights the wet street.
	var signs := [
		# [texture, centre, height, light colour, flickers]
		["pharmacy", Vector3(5, 3.15, 0.42), 0.72, Color(0.25, 1.0, 0.45), true],
		["pawn", Vector3(13, 3.15, 0.42), 0.85, Color(1.0, 0.25, 0.2), false],
		["diner", Vector3(27, 3.15, 0.42), 0.8, Color(1.0, 0.45, 0.8), true],
		["transit", Vector3(35, 3.15, 0.42), 0.85, Color(0.35, 0.65, 1.0), false],
	]
	for sg in signs:
		var mat := _sign_material(sg[0])
		var h: float = sg[2]
		var tex: Texture2D = mat.albedo_texture
		var w: float = h * float(tex.get_width()) / tex.get_height()
		_sign_board(r, sg[1], Vector2(w, h), mat, 0.0)
		var l := RoomBuilder.light(r, sg[1] + Vector3(0, -0.5, 1.1), sg[3], 0.9, 5.5, false, sg[4])
		l.light_specular = 1.4
		if sg[4]:
			l.set("linked", [mat])
	# Hotel blade sign sticking out over the south pavement, readable from
	# down the street in both directions.
	var hmat := _sign_material("hotel")
	var htex: Texture2D = hmat.albedo_texture
	var hh := 2.7
	var hw := hh * float(htex.get_width()) / htex.get_height()
	_sign_board(r, Vector3(30, 5.3, 15.25), Vector2(hw, hh), hmat, 90.0, true)
	for y in [4.3, 6.3]:
		RoomBuilder._box(r, Vector3(30, y, 15.65), Vector3(0.06, 0.06, 0.75), Mats.trim(Color(0.15, 0.14, 0.13), 0.6, 0.7), false)
	var hl := RoomBuilder.light(r, Vector3(30, 4.6, 14.4), Color(1.0, 0.7, 0.3), 1.0, 6.0, false, true)
	hl.light_specular = 1.4
	hl.set("linked", [hmat])
	# Facade details.
	for at in [[8.5, 4.8, 0.3, 0.0], [22.0, 7.5, 0.3, 0.0], [32.0, 4.6, 15.7, 180.0], [4.0, 7.4, 15.7, 180.0]]:
		RoomBuilder.prop(r, "exterior_aircon_unit", Vector3(at[0], at[1], at[2]), at[3], 1.0, false)
	Breakable.make_lamp(RoomBuilder.prop(r, "security_light", Vector3(18.0, 3.6, 0.3), 0, 1.0, false), [], "street_security_light")
	RoomBuilder.prop(r, "korean_public_payphone_01", Vector3(23.5, 1.0, 0.3), 0, 1.0, false)
	RoomBuilder.prop(r, "planter_box_01", Vector3(10.5, 0.18, 15.3), 180)
	RoomBuilder.prop(r, "modular_street_seating", Vector3(26.0, 0.18, 15.2), 180)
	RoomBuilder.prop(r, "old_tyre", Vector3(12.0, 0.3, 9.5), 70, 1.0, false)
	RoomBuilder.prop(r, "cement_bag", Vector3(36.5, 0.18, 2.4), 30)
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_handle", Vector3(37.0, 0.18, 14.0), 0, 1.0, false)
	RoomBuilder.prop(r, "metal_trash_can/metal_trash_can_rust", Vector3(15.0, 0.18, 14.6), 90)
	RoomBuilder.prop(r, "concrete_road_barrier_02", Vector3(3.0, 0, 6.5), 75)
	# Barricaded ends: the street carries on past a police line into the dark.
	for e in [[-1.0, 0.0], [1.0, 40.0]]:
		var ex: float = e[1]
		for i in 5:
			RoomBuilder.prop(r, "concrete_road_barrier_02" if i % 2 == 0 else "concrete_road_barrier", Vector3(ex - e[0] * 0.8, 0, 2.5 + i * 2.6), 90 + i * 7)
		RoomBuilder.prop(r, "modular_chainlink_fence", Vector3(ex - e[0] * 1.6, 0, 8.0), 90 * e[0])
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 4.0, 16.0)
		cs.shape = bs
		wall.add_child(cs)
		wall.position = Vector3(ex - e[0] * 0.8, 2.0, 8.0)
		r.add_child(wall)
		# More street beyond: road, facades and a dead-end wall far back.
		var beyond := RoomBuilder.build(r, {
			"id": "AshgroveBeyond%s" % ("W" if e[0] < 0 else "E"), "pos": Vector3(-14.0 if e[0] < 0 else 40.0, 0, 0), "size": Vector3(14, 11, 16),
			"floor": "street_road", "wall": "facade_painted" if e[0] < 0 else "facade_brick", "outdoor": true,
			"floor_look": {"tile_size": 4.0, "wetness": 0.8, "puddles": 1.0, "rain": 1.0}, "wall_look": {"tile_size": 3.0, "grime_amount": 0.8, "wall_wet": 1.0},
			"skip_walls": ["e"] if e[0] < 0 else ["w"],
			"windows": {"n": [[3.0, 1.3, 3.8, 5.6, {"moon": 0.0, "opaque": true, "lit": e[0] > 0}], [8.0, 1.3, 6.6, 8.3, {"moon": 0.0, "opaque": true}]],
				"s": [[5.0, 1.3, 3.8, 5.6, {"moon": 0.0, "opaque": true}], [10.0, 1.3, 6.6, 8.3, {"moon": 0.0, "opaque": true, "lit": true}]]},
			"decals": {"stain": 3, "scorch": 1},
		})
		RoomBuilder.prop(beyond, "covered_car", Vector3(7.0, 0, 6.0), 70 if e[0] < 0 else 110)
		RoomBuilder.prop(beyond, "street_lamp_01", Vector3(4.0, 0, 14.6), 180)
		RoomBuilder.light(beyond, Vector3(4.0, 4.6, 13.6), Color(1.0, 0.65, 0.35), 1.6, 9.0, false, true)
		if e[0] > 0:
			# A car still burning at the east end.
			RoomBuilder.light(beyond, Vector3(7.0, 1.4, 6.0), Color(1.0, 0.42, 0.12), 3.2, 10.0, true, true)
		_rain(beyond, Vector3(7, 10, 8), Vector3(6.5, 0, 7.5), false)

# ---------------- Courtyard (open area) ----------------
func _courtyard() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ArchiveCourtyard", "pos": Vector3(-10, 0, -14), "size": Vector3(20, 6, 12),
		"floor": "courtyard_floor", "wall": "alley_wall", "outdoor": true,
		"floor_look": {"tile_size": 2.5, "wetness": 0.7, "puddles": 0.8, "rain": 1.0},
		"wall_look": {"tile_size": 2.5, "grime_amount": 0.8, "grime_height": 1.8, "wall_wet": 0.8},
		"openings": {"s": [[8.8, 2.4, 3.2]]},
		# North side is the street's wall; south wall sits flush against the hall.
		"skip_walls": ["n"],
		"wall_inset": {"s": 0.25},
		"windows": {"s": [[1.6, 1.8, 1.5, 3.7, {"moon": 0.0, "glass": false}], [16.6, 1.8, 1.5, 3.7, {"moon": 0.0, "glass": false}]]},
		"decals": {"blood": 2, "stain": 4},
	})
	RoomBuilder.prop(r, "gothic_statue", Vector3(10, 0, 5), 180)
	RoomBuilder.prop(r, "potted_plant_02", Vector3(1.2, 0, 10.6))
	RoomBuilder.prop(r, "potted_plant_02", Vector3(18.8, 0, 10.6))
	# A fuel drum by the gate, another near the nurse; an old rain barrel and
	# a crate that splinter (the crate may hold something).
	Breakable.make(r, "fuel_drum", Vector3(2, 0, 2), 20.0, "court_drum_gate")
	Breakable.make(r, "fuel_drum", Vector3(14.6, 0, 1.3), -40.0, "court_drum_east")
	Breakable.make(r, "wood", Vector3(2.4, 0, 9.9), 60.0, "court_barrel", "Barrel_01")
	var crate := Breakable.make(r, "wood", Vector3(17.5, 0, 1.5), 10.0, "court_crate", "wooden_crate_01")
	crate.drop_table = "crate"
	RoomBuilder.prop(r, "industrial_wall_lamp", Vector3(8.0, 3.0, 11.8), 180, 1.0, false)
	RoomBuilder.light(r, Vector3(10, 2.8, 11.2), WARM, 1.6, 8.0, true)
	RoomBuilder.light(r, Vector3(10, 1.2, 5.5), Color(0.5, 0.6, 0.9), 0.6, 5.0)
	_rain(r, Vector3(10, 6, 6), Vector3(9.5, 0, 5.5))
	# Iron gate from the street (manual, swings).
	place_door(Vector3(0, 0, -14), 0, Door.Kind.MANUAL, "iron_gate", 4.0, 3.0, "courtyard_gate")
	place_zombie("Z_court_1", Vector3(-6, 0, -6), 90, "possum")
	place_zombie("Z_court_2", Vector3(5, 0, -9), 200, "shambler", true, "nurse")
	place_pickup("ammo:shells", Vector3(7.5, 0.37, -12.4), "court_shells")   # on the crate (it was inside it: no prompt)
	place_pickup("weapon:m12", Vector3(7.5, 0.1, -12.8), "court_m12")

# ---------------- Great Hall (hub) ----------------
func _great_hall() -> void:
	var r := RoomBuilder.build(self, {
		"id": "GreatHall", "pos": Vector3(-12, 0, -2), "size": Vector3(24, 9, 18),
		"floor": "stone_trim", "wall": "archive_hall_wall", "wainscot": "archive_wainscot",
		"ceiling": "hall_ceiling", "ceiling_look": {"tile_size": 2.0},
		"wainscot_height": 1.4, "trim": Color(0.16, 0.09, 0.05),
		"floor_look": {"tile_size": 3.0, "roughness_mul": 0.4, "grime_amount": 0.3},
		"wall_look": {"tile_size": 3.0, "tint": Color(0.78, 0.74, 0.66), "stain_amount": 0.6},
		"look": {"grime_amount": 0.45},
		"windows": {"n": [
			# The courtyard's wall stands against this one and frames these two.
			[3.6, 1.8, 1.5, 3.7, {"boards": 3, "moon": 2.2, "frame": false}],
			[18.6, 1.8, 1.5, 3.7, {"boards": 3, "moon": 2.2, "frame": false}],
			[2.0, 2.6, 5.6, 8.2, {"moon": 3.5, "reach": 10.0}],
			[7.2, 2.6, 5.6, 8.2, {"moon": 3.5, "reach": 10.0}],
			[14.2, 2.6, 5.6, 8.2, {"moon": 3.5, "reach": 10.0}],
			[19.4, 2.6, 5.6, 8.2, {"moon": 3.5, "reach": 10.0}],
		]},
		"pilasters": {"sides": ["e", "w", "s"], "spacing": 4.0, "slot": "archive_marble"},
		"beams": {"axis": "both", "spacing": 4.0, "slot": "archive_wainscot", "depth": 0.45},
		"decals": {"blood": 4, "stain": 5, "wall_blood": 2},
		"papers": 30,
		"probe": true,
		"openings": {
			"n": [[10.8, 2.4, 3.2]],
			"w": [[7.0, 1.4, 2.3]],
			"e": [[4.0, 1.2, 2.3]],
			"s": [[5.0, 2.0, 2.6]],
		},
	})
	# Gallery balcony along the north wall, held by columns.
	var bal := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(24, 0.3, 3)
	bal.mesh = bm
	bal.material_override = Mats.surface("archive_wainscot", {"tile_size": 1.5})
	bal.position = Vector3(12, 4.5, 1.5)
	r.add_child(bal)
	for x in [3.0, 9.0, 15.0, 21.0]:
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.34
		cm.height = 4.5
		col.mesh = cm
		col.material_override = Mats.surface("archive_marble", {"tile_size": 1.0, "grime_amount": 0.3})
		col.position = Vector3(x, 2.25, 3.0)
		r.add_child(col)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.34
		cy.height = 4.5
		cs.shape = cy
		sb.add_child(cs)
		sb.position = col.position
		r.add_child(sb)
	# Central reception desk and a cracked memorial bust.
	RoomBuilder.prop(r, "metal_office_desk", Vector3(12, 0, 10), 180)
	RoomBuilder.prop(r, "metal_office_desk", Vector3(10.4, 0, 10), 180)
	RoomBuilder.prop(r, "marble_bust_01", Vector3(12, 0, 15.5), 180, 1.6)
	RoomBuilder.prop(r, "vintage_grandfather_clock_01", Vector3(23.4, 0, 12), -90)
	RoomBuilder.prop(r, "Chandelier_02", Vector3(12, 7.4, 9), 0, 1.4, false)
	RoomBuilder.prop(r, "Sofa_01", Vector3(3, 0, 13), 90)
	RoomBuilder.prop(r, "Rockingchair_01", Vector3(4.5, 0, 9), 40)
	RoomBuilder.prop(r, "WetFloorSign_01", Vector3(14, 0, 6), 20)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(20, 0, 16.5), 10)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(20.6, 0, 16.2), 50)
	RoomBuilder.prop(r, "wheelchair_01", Vector3(1.5, 0, 16), 120)
	RoomBuilder.prop(r, "fancy_picture_frame_01", Vector3(0.2, 2.6, 4), 90, 2.0, false)
	RoomBuilder.prop(r, "security_camera_01", Vector3(23.6, 3.6, 0.5), -135, 1.0, false)
	RoomBuilder.band(r, Vector3(24, 9, 18), 4.95)
	# The hall was an emergency shelter before it fell: cots, luggage, crates.
	for c in [[17.0, 13.2], [17.0, 10.2], [20.6, 13.2], [20.6, 10.2]]:
		RoomBuilder.prop(r, "old_bed_frame", Vector3(c[0], 0, c[1]), 90.0 + (c[0] - 17.0) * 3.0)
	RoomBuilder.prop(r, "vintage_suitcase/vintage_suitcase_01", Vector3(18.8, 0, 14.8), 30)
	RoomBuilder.prop(r, "vintage_suitcase/vintage_suitcase_02", Vector3(15.6, 0, 11.6), -70)
	RoomBuilder.prop(r, "old_gas_mask", Vector3(0.2, 2.05, 6.3), 90, 1.0, false)
	RoomBuilder.prop(r, "vintage_crutches_01", Vector3(19.0, 0, 15.6), 10, 1.0, false)
	RoomBuilder.prop(r, "Megaphone_01", Vector3(11.0, 0.78, 9.8), 60, 1.0, false)
	RoomBuilder.prop(r, "painted_wooden_bench", Vector3(1.0, 0, 7.6), 90)
	RoomBuilder.prop(r, "standing_chalkboard_01", Vector3(8.0, 0, 14.6), 160)
	RoomBuilder.prop(r, "hanging_picture_frame_02", Vector3(0.16, 2.6, 12.6), 90, 1.4, false)
	RoomBuilder.prop(r, "old_military_crate", Vector3(2.6, 0, 2.6), 15)
	var mil := Breakable.make(r, "wood", Vector3(3.6, 0, 1.9), -10.0, "hall_crate", "wooden_military_crate")
	mil.drop_table = "crate"
	# The shelter's heater gas by the cots, a can of generator fuel by the sofa.
	Breakable.make(r, "propane", Vector3(16.2, 0, 15.7), 0.0, "hall_propane")
	Breakable.make(r, "jerrycan", Vector3(3.4, 0, 17.4), 70.0, "hall_jerrycan")   # against the wall beside the vault door, not in front of it
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(22.4, 0, 2.2), 5)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(22.4, 0.32, 2.2), 30, 1.0, false)
	var sconce_w := RoomBuilder.prop(r, "industrial_wall_sconce", Vector3(0.2, 2.8, 9.0), 90, 1.0, false)
	var sconce_e := RoomBuilder.prop(r, "industrial_wall_sconce", Vector3(23.8, 2.8, 9.0), -90, 1.0, false)
	RoomBuilder.light(r, Vector3(12, 6.4, 9), WARM, 2.2, 16.0, true)
	Breakable.make_lamp(sconce_w, [RoomBuilder.light(r, Vector3(0.7, 2.7, 9.0), WARM, 1.0, 6.0, false, true)], "hall_sconce_w")
	Breakable.make_lamp(sconce_e, [RoomBuilder.light(r, Vector3(23.3, 2.7, 9.0), WARM, 1.0, 6.0)], "hall_sconce_e")
	RoomBuilder.light(r, Vector3(3, 3.0, 15), WARM, 0.8, 6.0, false, true)
	RoomBuilder.light(r, Vector3(21, 3.0, 4), COLD, 0.7, 7.0)
	place_door(Vector3(0, 0, -2), 0, Door.Kind.MANUAL, "wood_panel", 2.4, 3.2, "hall_main")
	place_checkpoint("hall", Vector3(0, 0, 4), Vector3(8, 3, 6))
	place_zombie("Z_hall_1", Vector3(6, 0, 12), 200, "shambler", true, "suit")
	place_zombie("Z_hall_possum1", Vector3(-9, 0, 13), 30, "possum")
	place_zombie("Z_hall_possum2", Vector3(-7.8, 0, 13.6), 160, "possum")
	# Lying among the dead on the way to the vault: stepping between them
	# (the hall_wake scare) gets both up at once.
	for zn in ["Z_hall_possum1", "Z_hall_possum2"]:
		var hz := get_node_or_null(zn)
		if hz:
			hz.add_to_group("hall_dead")
	place_zombie("Z_hall_scream", Vector3(9, 0, 4), 180, "screamer")
	place_zombie("Z_hall_2", Vector3(-8, 0, 8), 120, "shambler", false, "office")
	place_pickup("ammo:9mm", Vector3(-1, 1.05, 8), "hall_desk_ammo")
	place_pickup("file:shelter_log", Vector3(0.6, 1.05, 8.1), "hall_file_1")
	# Co-op steel door down to the records vault: two wheel valves.
	place_door(Vector3(-6, 0, 16), 0, Door.Kind.COOP, "steel", 2.0, 2.6, "vault_door")

# ---------------- West corridor ----------------
func _west_corridor() -> void:
	var r := RoomBuilder.build(self, {
		"id": "WestCorridor", "pos": Vector3(-24, 0, 5), "size": Vector3(12, 3.4, 3),
		"floor": "corridor_floor", "wall": "corridor_wall", "trim": Color(0.25, 0.22, 0.18),
		"floor_look": {"tile_size": 1.6},
		"wall_look": {"tile_size": 2.0, "tint": Color(0.78, 0.82, 0.76), "stain_amount": 0.7},
		"look": {"grime_amount": 0.7},
		# The reading room's wall stands back to back with the north wall and
		# frames the doorway and the pane through both (RoomBuilder header).
		"openings": {"n": [[8.0, 1.2, 2.3, {"frame": false}]]},
		"skip_walls": ["e"],
		# Frosted pane into the reading room (Chapter1Story fills it).
		"windows": {"n": [[4.0, 1.2, 0.9, 2.4, {"glass": false, "moon": 0.0, "frame": false}]]},
		# The air vent the ventling waits in (Z_corr_vent, right under it).
		"ceiling_holes": [[5.15, 0.95, 0.9, 0.9, {"vent": true}]],
	})
	RoomBuilder.prop(r, "korean_fire_extinguisher_01", Vector3(11.6, 0, 0.4), 0)
	var tube := RoomBuilder.prop(r, "mounted_fluorescent_lights", Vector3(4, 3.35, 1.5), 90, 1.0, false)
	Breakable.make_lamp(tube, [RoomBuilder.light(r, Vector3(4, 3.1, 1.5), SICK, 1.2, 6.0, false, true)], "corridor_tube")
	RoomBuilder.light(r, Vector3(10, 3.1, 1.5), SICK, 0.6, 5.0)
	place_door(Vector3(-15.4, 0, 5), 0, Door.Kind.LOCKED, "wood_panel", 1.2, 2.3, "reading_door", "brass_quill_key")
	place_zombie("Z_corr_1", Vector3(-22, 0, 6.5), 90, "bloater")
	place_zombie("Z_corr_vent", Vector3(-18.4, 0, 6.4), 90, "ventling")
	if GameState.has_flag("dead:Z_corr_vent"):
		# It came through earlier in this run: the grille is already out.
		for g in r.find_children("VentGrille", "", true, false):
			g.queue_free()

# ---------------- Reading room ----------------
func _reading_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ReadingRoom", "pos": Vector3(-26, 0, -7), "size": Vector3(14, 4.5, 12),
		"floor": "reading_room_floor", "wall": "reading_room_wall", "wainscot": "archive_wainscot",
		"trim": Color(0.2, 0.11, 0.06),
		"floor_look": {"tile_size": 2.0, "roughness_mul": 0.7},
		"wall_look": {"tile_size": 2.2, "tint": Color(0.75, 0.85, 0.75), "stain_amount": 0.6},
		"openings": {"s": [[10.0, 1.2, 2.3]]},   # lines up with the corridor's doorway (x -16.0 .. -14.8)
		# South wall: back to back with the corridor's (one wall in the same
		# place as another flickers through it). East: the Great Hall's wall
		# closes z -2 .. 5; this room closes the rest itself.
		"wall_inset": {"s": RoomBuilder.WALL_T},
		"wall_range": {"e": [0.0, 5.0]},
		"windows": {"w": [[2.4, 1.6, 1.3, 3.7, {"moon": 2.6, "boards": 2}], [7.6, 1.6, 1.3, 3.7, {"moon": 2.6}]],
			"s": [[6.0, 1.2, 0.9, 2.4, {"glass": false, "moon": 0.0}]]},
		"beams": {"axis": "z", "spacing": 3.0, "slot": "archive_wainscot", "depth": 0.3},
		"decals": {"blood": 2, "stain": 4, "wall_blood": 1},
		"papers": 26,
		# Caved in between two beams: the "reading_drop" infected comes
		# through here (world x -19.6 .. -18.4, z -4.4 .. -3.2).
		"ceiling_holes": [[6.4, 2.6, 1.2, 1.2]],
	})
	for i in 5:
		_bookshelf(r, Vector3(1.0 + i * 2.6, 0, 0.5), 0)
	for i in 3:
		_bookshelf(r, Vector3(13.4, 0, 3.2 + i * 1.6), -90)
	RoomBuilder.prop(r, "lantern_chandelier_01", Vector3(4.5, 4.5, 6.0), 0, 1.0, false)
	RoomBuilder.prop(r, "lantern_chandelier_01", Vector3(9.5, 4.5, 6.0), 0, 1.0, false)
	RoomBuilder.prop(r, "hanging_picture_frame_03", Vector3(5.0, 2.3, 11.59), 180, 1.3, false)
	RoomBuilder.prop(r, "ornate_mirror_01", Vector3(8.0, 2.2, 11.6), 180, 1.0, false)
	RoomBuilder.prop(r, "wooden_ladder", Vector3(6.2, 0, 1.2), 10)
	RoomBuilder.prop(r, "book_encyclopedia_set_01", Vector3(2.2, 0.0, 9.4), 70, 1.0, false)
	RoomBuilder.prop(r, "book_encyclopedia_set_01", Vector3(2.5, 0.0, 9.0), 120, 1.0, false)
	RoomBuilder.prop(r, "WetFloorSign_01", Vector3(11.0, 0, 9.0), -30)
	RoomBuilder.prop(r, "book_encyclopedia_set_01", Vector3(4, 0.75, 6), 20)
	RoomBuilder.prop(r, "dining_table", Vector3(5, 0, 6), 0)
	RoomBuilder.prop(r, "dining_table", Vector3(9, 0, 6), 0)
	RoomBuilder.prop(r, "desk_lamp_arm_01", Vector3(5.4, 0.78, 6.2), 200)
	RoomBuilder.prop(r, "ArmChair_01", Vector3(12, 0, 10), -140)
	RoomBuilder.prop(r, "vintage_oil_lamp", Vector3(9, 0.78, 6), 0, 1.0, false)
	RoomBuilder.light(r, Vector3(5.3, 1.45, 6.0), Color(1.0, 0.85, 0.6), 1.4, 5.0)
	RoomBuilder.light(r, Vector3(9, 1.1, 6), Color(1.0, 0.6, 0.3), 0.9, 4.0, false, true)
	RoomBuilder.light(r, Vector3(4.5, 3.8, 6.0), WARM, 1.1, 7.0, true)
	RoomBuilder.light(r, Vector3(9.5, 3.8, 6.0), WARM, 0.7, 6.0, false, true)
	place_pickup("weapon:longshot", Vector3(-17, 0.82, -1), "reading_rifle")
	place_pickup("ammo:rifle", Vector3(-16.6, 0.82, -0.6), "reading_rifle_ammo")
	place_zombie("Z_read_1", Vector3(-20, 0, 2), 0, "shambler", true, "student")
	place_zombie("Z_read_2", Vector3(-15, 0, -4), 180, "spitter")

# ---------------- Office (safe room) ----------------
func _office_safe_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ArchivistOffice", "pos": Vector3(12, 0, 0), "size": Vector3(8, 3.2, 8),
		"floor": "office_floor", "wall": "office_wall", "wainscot": "archive_wainscot", "wainscot_height": 0.9,
		"trim": Color(0.3, 0.2, 0.12),
		"floor_look": {"tile_size": 1.5},
		"wall_look": {"tile_size": 2.0, "tint": Color(0.95, 0.88, 0.78), "stain_amount": 0.2},
		"look": {"grime_amount": 0.25},
		"openings": {"w": [[2.0, 1.2, 2.3]]},
		"skip_walls": ["w"],
	})
	RoomBuilder.prop(r, "metal_office_desk", Vector3(5, 0, 1.2), 0)
	RoomBuilder.prop(r, "GothicCabinet_01", Vector3(7.5, 0, 5), -90)
	RoomBuilder.prop(r, "drawer_cabinet", Vector3(1, 0, 7.4), 180)
	RoomBuilder.prop(r, "Television_01", Vector3(4.4, 0.79, 1.0), 0)
	RoomBuilder.prop(r, "vintage_telephone_wall_clock", Vector3(4, 2.2, 0.15), 0, 1.0, false)
	RoomBuilder.shelf_unit(r, Vector3(7.5, 0, 1.4), -90, 1.6, 1.9, 0.45, "office")
	RoomBuilder.prop(r, "medical_box", Vector3(7.5, 0.98, 1.0), -90, 1.0, false)
	RoomBuilder.prop(r, "ArmChair_01", Vector3(2.0, 0, 4.6), 120)
	RoomBuilder.prop(r, "hanging_picture_frame_01", Vector3(0.16, 1.8, 3.0), 90, 1.0, false)
	RoomBuilder.prop(r, "mantel_clock_01", Vector3(5.9, 0.79, 1.4), -20, 1.0, false)
	RoomBuilder.light(r, Vector3(4, 2.9, 4), Color(1.0, 0.86, 0.66), 1.8, 7.0, true)
	place_door(Vector3(12, 0, 2.6), 90, Door.Kind.MANUAL, "wood_panel", 1.2, 2.3, "office_door")
	place_checkpoint("safe_office", Vector3(16, 0, 4), Vector3(6, 3, 6), true)
	place_pickup("herb_red", Vector3(19.5, 1.47, 1.8), "office_red_herb")
	place_pickup("ink_ribbon", Vector3(17.3, 0.82, 1.4), "office_tape")
	place_pickup("key:brass_quill_key", Vector3(17.8, 0.82, 1.0), "brass_quill_key")

# ---------------- Records vault (behind the co-op door) ----------------
func _records_vault() -> void:
	var r := RoomBuilder.build(self, {
		"id": "RecordsVault", "pos": Vector3(-10, 0, 16), "size": Vector3(14, 3.2, 10),
		"floor": "basement_floor", "wall": "basement_wall", "trim": Color(0.3, 0.3, 0.3),
		"floor_look": {"tile_size": 2.5, "wetness": 0.4},
		"wall_look": {"tile_size": 2.0, "stain_amount": 0.8},
		"look": {"grime_amount": 0.8, "grime_height": 1.0},
		# East: the boiler room door. West: the vault elevator (VaultElevator
		# builds its own steel frame and the car behind the wall).
		"openings": {"e": [[4.0, 1.2, 2.3]], "w": [[6.4, VaultElevator.DOOR_W, VaultElevator.DOOR_H, {"frame": false}]]},
		"skip_walls": ["n"],
		"decals": {"blood": 3, "stain": 5, "wall_blood": 2},
		"papers": 18,
	})
	# Rows of records shelving.
	for row in [2.6, 5.2]:
		for i in 4:
			RoomBuilder.shelf_unit(r, Vector3(2.2 + i * 2.2, 0, row), 0, 2.0, 2.4, 0.5, "vault")
	for i in 5:
		RoomBuilder.shelf_unit(r, Vector3(1.8 + i * 2.2, 0, 9.5), 180, 2.0, 2.4, 0.5, "vault_back")
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(11.6, 0, 7.6), 37)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(11.9, 0, 7.1), 80)
	RoomBuilder.prop(r, "cardboard_box_01", Vector3(11.7, 0.34, 7.4), 10, 1.0, false)
	var vcrate := Breakable.make(r, "wood", Vector3(12.6, 0, 8.5), 80.0, "vault_crate", "wooden_crate_01")
	vcrate.drop_table = "crate"
	# Down here a drum is the answer to the brute and the riot shield.
	Breakable.make(r, "fuel_drum", Vector3(10.6, 0, 6.5), 10.0, "vault_drum")
	RoomBuilder.prop(r, "hanging_industrial_lamp", Vector3(7, 3.1, 5), 0, 1.0, false)
	Breakable.make(r, "propane", Vector3(13, 0, 1), 0.0, "vault_propane")
	RoomBuilder.light(r, Vector3(7, 2.6, 5), Color(1.0, 0.8, 0.55), 1.6, 8.0, true, true)
	place_zombie("Z_vault_1", Vector3(-4, 0, 22), 180, "riot")
	place_zombie("Z_vault_grab", Vector3(-8, 0, 24), 200, "grappler")
	place_zombie("Z_vault_2", Vector3(1, 0, 24), 200, "brute")
	place_zombie("Z_boiler_burn", Vector3(11, 0, 19), 180, "burner")
	place_pickup("weapon:gl", Vector3(2.3, 0.37, 24.4), "vault_gl")
	place_pickup("ammo:grenades", Vector3(2.9, 0.37, 24.6), "vault_gl_ammo")
	# The vault's own circuit (dead until the boiler-room breaker is thrown)
	# and the elevator Hardass sends them to, in the west wall.
	var circuit := VaultCircuit.new()
	circuit.name = "VaultCircuit"
	add_child(circuit)
	var lift := VaultElevator.new()
	lift.name = "VaultElevator"
	lift.position = Vector3(-10.0, 0.0, 23.2)
	lift.rotation_degrees.y = 90.0
	add_child(lift)

# ---------------- Boiler room ----------------
func _boiler_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "BoilerRoom", "pos": Vector3(4, 0, 16), "size": Vector3(10, 4, 10),
		"floor": "boiler_floor", "wall": "boiler_wall", "trim": Color(0.2, 0.2, 0.2),
		"floor_look": {"tile_size": 1.5},
		"wall_look": {"tile_size": 2.0},
		"look": {"grime_amount": 0.9, "grime_height": 1.4, "wetness": 0.3},
		"skip_walls": ["w"],
		"wall_inset": {"n": RoomBuilder.WALL_T},   # back to back with the Great Hall's south wall
	})
	RoomBuilder.prop(r, "portable_generator", Vector3(5, 0, 5), 30)
	# The vault breaker on the east wall: blinking fault lamp, big handle.
	var breaker := BreakerPanel.new()
	breaker.name = "BreakerPanel"
	breaker.position = Vector3(13.875, 0.0, 19.0)
	breaker.rotation_degrees.y = -90.0
	add_child(breaker)
	Breakable.make(r, "jerrycan", Vector3(6, 0, 6.2), 80.0, "boiler_jerrycan")
	# Two drums side by side: one goes, the other follows.
	Breakable.make(r, "fuel_drum", Vector3(8.7, 0, 8.6), 0.0, "boiler_drum_1")
	Breakable.make(r, "fuel_drum", Vector3(7.95, 0, 9.05), 40.0, "boiler_drum_2")
	RoomBuilder.light(r, Vector3(5, 3.4, 5), Color(1.0, 0.35, 0.2), 1.4, 9.0, true, true)
	place_door(Vector3(4, 0, 20.6), 90, Door.Kind.MANUAL, "steel", 1.2, 2.3, "boiler_door")
	place_pickup("ammo:fuel", Vector3(10.6, 0.1, 22.2), "boiler_fuel")   # beside the jerrycan (it was inside it: no prompt)
	place_pickup("gunpowder", Vector3(12.5, 0.1, 17.0), "boiler_powder")   # off to the side: right by the breaker its prompt took over

## A slim upright collider for a post-like prop (lamp posts) placed without
## its fitted box, so nothing bumps into the empty space under its arm.
func _post_collider(parent: Node3D, base: Vector3, radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	sb.add_child(cs)
	sb.position = base + Vector3(0, height / 2.0, 0)
	parent.add_child(sb)

## A worn bookshelf filled with uneven rows of books (some missing, some leaning).
func _bookshelf(r: Node3D, at: Vector3, rot: float) -> void:
	var shelf := RoomBuilder.prop(r, "wooden_bookshelf_worn", at, rot)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(at))
	for y in [0.12, 0.52, 0.92, 1.32, 1.72]:
		for x in [-0.6, -0.05]:
			if rng.randf() < 0.2:
				continue
			var b := RoomBuilder.prop(shelf, "book_encyclopedia_set_01", Vector3(x + rng.randf_range(-0.03, 0.03), y, 0.0), 0.0, 1.0, false)
			if rng.randf() < 0.25:
				b.rotation_degrees.z = rng.randf_range(-12, 12)

## Sign face material from assets/textures/signs/<id>.jpg (board) and
## <id>_emit.jpg (the parts that glow).
func _sign_material(id: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/signs/%s.jpg" % id)
	m.roughness = 0.55
	m.metallic = 0.2
	m.emission_enabled = true
	m.emission_texture = load("res://assets/textures/signs/%s_emit.jpg" % id)
	m.emission_energy_multiplier = 2.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## A sign box: dark metal casing with the printed face on the front (and on
## the back too for a blade sign). `rot` turns it about Y.
func _sign_board(parent: Node3D, at: Vector3, face: Vector2, mat: Material, rot: float, two_sided := false) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation_degrees.y = rot
	parent.add_child(n)
	var depth := 0.14
	RoomBuilder._box(n, Vector3.ZERO, Vector3(face.x + 0.06, face.y + 0.06, depth), Mats.trim(Color(0.1, 0.1, 0.1), 0.5, 0.6), false)
	for side in ([1.0, -1.0] if two_sided else [1.0]):
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = face
		q.mesh = qm
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(0, 0, side * (depth / 2 + 0.004))
		if side < 0:
			q.rotation_degrees.y = 180
		n.add_child(q)
	return n

## Rain over an outdoor area. `top` is the local centre of the emitter (just
## under the sky), `extents` the half-size of the area it covers.
func _rain(parent: Node3D, top: Vector3, extents: Vector3, sound := true) -> void:
	Rain.add(parent, top, extents, sound)


# ---------------- Scripted horror ----------------
func _horror_beats() -> void:
	place_scare("hall_entry_sting", "stinger", Vector3(0, 0, 1), Vector3(4, 3, 2))
	place_scare("hall_whisper", "whisper", Vector3(-8, 0, 12), Vector3(4, 3, 4), {"target": Vector3(-11, 1.5, 14), "text": "...forty-one... forty-two..."})
	place_scare("corridor_lights", "lights_out", Vector3(-20, 0, 5.2), Vector3(2, 3, 2.6), {"room": "WestCorridor", "duration": 7.0})
	place_scare("office_bang", "door_bang", Vector3(15, 0, 5), Vector3(3, 3, 3), {"target": Vector3(19.8, 1.2, 7.6)})
	# Walking up to the rifle on the table, the ceiling ahead caves in and an
	# infected drops through the hole, crumples, then gets up.
	place_scare("reading_drop", "body_drop", Vector3(-17.5, 0, 0.4), Vector3(7, 3, 2.4), {"target": Vector3(-19.0, 4.75, -3.8)})
	# Passing the 24H diner, the ones inside pound on its shutter and force it up.
	place_scare("diner_shutter", "shutter_burst", Vector3(7, 0, -25.5), Vector3(7, 3, 4.4), {"room": "DinerShutter", "spots": DINER_SPOTS})
	place_scare("hall_wake", "wake_dead", Vector3(-8, 0, 15), Vector3(3, 3, 2), {"group": "hall_dead"})
	place_scare("vault_lights", "lights_out", Vector3(-6, 0, 17), Vector3(3, 3, 2), {"room": "RecordsVault", "duration": 5.0})
	# The Tallyman: first seen behind the reading-room glass, then hunting from chapter 2.
	place_stalker(Vector3(-24, 0, -5), GameState.has_flag("tallyman_awake"))
