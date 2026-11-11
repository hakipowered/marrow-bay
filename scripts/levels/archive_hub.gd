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
	_courtyard()
	_great_hall()
	_west_corridor()
	_reading_room()
	_office_safe_room()
	_records_vault()
	_boiler_room()
	_horror_beats()

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
	var r := RoomBuilder.build(self, {
		"id": "AshgroveStreet", "pos": Vector3(-20, 0, -30), "size": Vector3(40, 9, 16),
		"floor": "street_road", "wall": "facade_brick", "outdoor": true,
		"floor_look": {"tile_size": 4.0, "wetness": 0.8},
		"wall_look": {"tile_size": 3.0, "grime_amount": 0.7, "grime_height": 1.4},
		"look": {"variation": 0.3},
		"openings": {"s": [[18.0, 4.0, 9.0]]},
	})
	# Sidewalk strips on both sides.
	for z in [1.5, 14.5]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(40, 0.18, 3)
		mi.mesh = b
		mi.material_override = Mats.surface("sidewalk", {"tile_size": 1.5, "wetness": 0.6, "grime_amount": 0.5})
		mi.position = Vector3(20, 0.09, z)
		r.add_child(mi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = mi.position
		r.add_child(sb)
	# Shopfronts with shutters along the north facade.
	for x in [5.0, 13.0, 27.0, 35.0]:
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
	for x in [6.0, 20.0, 34.0]:
		RoomBuilder.prop(r, "street_lamp_01", Vector3(x, 0.18, 14.6), 180)
		var l := RoomBuilder.light(r, Vector3(x, 4.6, 13.6), Color(1.0, 0.7, 0.4), 2.4, 11.0, x == 20.0, x == 34.0)
	# Burning wreck glow at the far end.
	RoomBuilder.light(r, Vector3(30, 1.0, 7), Color(1.0, 0.45, 0.15), 3.0, 9.0, true, true)
	_rain(r, Vector3(20, 9, 8), Vector3(19.5, 0, 7.5))
	place_checkpoint("start", Vector3(0, 0, -24), Vector3(6, 3, 6))
	place_zombie("Z_street_1", Vector3(-8, 0, -22), 30, "shambler", false, "cop")
	place_zombie("Z_street_2", Vector3(10, 0, -25), -60, "shambler", false, "mechanic")
	place_zombie("Z_street_crawl", Vector3(-11, 0, -21.5), 100, "crawler")
	place_zombie("Z_street_run1", Vector3(18, 0, -26), -90, "runner", true)
	place_zombie("Z_street_run2", Vector3(19, 0, -24), -100, "runner", true)
	place_zombie("Z_street_hound", Vector3(-17, 0, -27), 40, "hound", true)
	place_zombie("Z_street_3", Vector3(14, 0, -18), 200, "shambler", true, "jogger")
	place_pickup("ammo:9mm", Vector3(-15, 0.2, -16.2), "street_ammo_1")
	place_pickup("herb_green", Vector3(17, 0.2, -28.5), "street_herb_1")

# ---------------- Courtyard (open area) ----------------
func _courtyard() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ArchiveCourtyard", "pos": Vector3(-10, 0, -14), "size": Vector3(20, 6, 12),
		"floor": "courtyard_floor", "wall": "alley_wall", "outdoor": true,
		"floor_look": {"tile_size": 2.5, "wetness": 0.7},
		"wall_look": {"tile_size": 2.5, "grime_amount": 0.8, "grime_height": 1.8},
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
	RoomBuilder.prop(r, "Barrel_01", Vector3(2, 0, 2), 20)
	RoomBuilder.prop(r, "wooden_crate_01", Vector3(17.5, 0, 1.5), 10)
	RoomBuilder.prop(r, "industrial_wall_lamp", Vector3(8.0, 3.0, 11.8), 180, 1.0, false)
	RoomBuilder.light(r, Vector3(10, 2.8, 11.2), WARM, 1.6, 8.0, true)
	RoomBuilder.light(r, Vector3(10, 1.2, 5.5), Color(0.5, 0.6, 0.9), 0.6, 5.0)
	_rain(r, Vector3(10, 6, 6), Vector3(9.5, 0, 5.5))
	# Iron gate from the street (manual, swings).
	place_door(Vector3(0, 0, -14), 0, Door.Kind.MANUAL, "iron_gate", 4.0, 3.0, "courtyard_gate")
	place_zombie("Z_court_1", Vector3(-6, 0, -6), 90, "possum")
	place_zombie("Z_court_2", Vector3(5, 0, -9), 200, "shambler", true, "nurse")
	place_pickup("ammo:shells", Vector3(7.5, 0.1, -12.4), "court_shells")
	place_pickup("weapon:m12", Vector3(7.5, 0.1, -12.8), "court_m12")

# ---------------- Great Hall (hub) ----------------
func _great_hall() -> void:
	var r := RoomBuilder.build(self, {
		"id": "GreatHall", "pos": Vector3(-12, 0, -2), "size": Vector3(24, 9, 18),
		"floor": "archive_hall_floor", "wall": "archive_hall_wall", "wainscot": "archive_wainscot",
		"ceiling": "hall_ceiling", "ceiling_look": {"tile_size": 2.0},
		"wainscot_height": 1.4, "trim": Color(0.16, 0.09, 0.05),
		"floor_look": {"tile_size": 4.2, "roughness_mul": 0.45, "grime_amount": 0.25},
		"wall_look": {"tile_size": 3.0, "tint": Color(0.78, 0.74, 0.66), "stain_amount": 0.6},
		"look": {"grime_amount": 0.45},
		"windows": {"n": [
			[3.6, 1.8, 1.5, 3.7, {"boards": 3, "moon": 2.2}],
			[18.6, 1.8, 1.5, 3.7, {"boards": 3, "moon": 2.2}],
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
	RoomBuilder.prop(r, "wooden_military_crate", Vector3(3.6, 0, 1.9), -10)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(22.4, 0, 2.2), 5)
	RoomBuilder.prop(r, "plastic_crate_01", Vector3(22.4, 0.32, 2.2), 30, 1.0, false)
	RoomBuilder.prop(r, "industrial_wall_sconce", Vector3(0.2, 2.8, 9.0), 90, 1.0, false)
	RoomBuilder.prop(r, "industrial_wall_sconce", Vector3(23.8, 2.8, 9.0), -90, 1.0, false)
	RoomBuilder.light(r, Vector3(12, 6.4, 9), WARM, 2.2, 16.0, true)
	RoomBuilder.light(r, Vector3(0.7, 2.7, 9.0), WARM, 1.0, 6.0, false, true)
	RoomBuilder.light(r, Vector3(23.3, 2.7, 9.0), WARM, 1.0, 6.0)
	RoomBuilder.light(r, Vector3(3, 3.0, 15), WARM, 0.8, 6.0, false, true)
	RoomBuilder.light(r, Vector3(21, 3.0, 4), COLD, 0.7, 7.0)
	place_door(Vector3(0, 0, -2), 0, Door.Kind.MANUAL, "wood_panel", 2.4, 3.2, "hall_main")
	place_checkpoint("hall", Vector3(0, 0, 4), Vector3(8, 3, 6))
	place_zombie("Z_hall_1", Vector3(6, 0, 12), 200, "shambler", true, "suit")
	place_zombie("Z_hall_possum1", Vector3(-9, 0, 13), 30, "possum")
	place_zombie("Z_hall_possum2", Vector3(-7.8, 0, 13.6), 160, "possum")
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
		"openings": {"n": [[8.0, 1.2, 2.3]]},
		"skip_walls": ["e"],
	})
	RoomBuilder.prop(r, "korean_fire_extinguisher_01", Vector3(11.6, 0, 0.4), 0)
	RoomBuilder.prop(r, "mounted_fluorescent_lights", Vector3(4, 3.35, 1.5), 90, 1.0, false)
	RoomBuilder.light(r, Vector3(4, 3.1, 1.5), SICK, 1.2, 6.0, false, true)
	RoomBuilder.light(r, Vector3(10, 3.1, 1.5), SICK, 0.6, 5.0)
	place_door(Vector3(-15.4, 0, 5), 0, Door.Kind.LOCKED, "wood_panel", 1.2, 2.3, "reading_door", "brass_quill_key")
	place_zombie("Z_corr_1", Vector3(-22, 0, 6.5), 90, "bloater")
	place_zombie("Z_corr_vent", Vector3(-19, 0, 6.4), 90, "ventling")

# ---------------- Reading room ----------------
func _reading_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "ReadingRoom", "pos": Vector3(-26, 0, -7), "size": Vector3(14, 4.5, 12),
		"floor": "reading_room_floor", "wall": "reading_room_wall", "wainscot": "archive_wainscot",
		"trim": Color(0.2, 0.11, 0.06),
		"floor_look": {"tile_size": 2.0, "roughness_mul": 0.7},
		"wall_look": {"tile_size": 2.2, "tint": Color(0.75, 0.85, 0.75), "stain_amount": 0.6},
		"openings": {"s": [[10.6, 1.2, 2.3]]},
		"skip_walls": ["e"],
		"windows": {"w": [[2.4, 1.6, 1.3, 3.7, {"moon": 2.6, "boards": 2}], [7.6, 1.6, 1.3, 3.7, {"moon": 2.6}]]},
		"beams": {"axis": "z", "spacing": 3.0, "slot": "archive_wainscot", "depth": 0.3},
		"decals": {"blood": 2, "stain": 4, "wall_blood": 1},
		"papers": 26,
	})
	for i in 5:
		_bookshelf(r, Vector3(1.0 + i * 2.6, 0, 0.5), 0)
	for i in 3:
		_bookshelf(r, Vector3(13.4, 0, 3.2 + i * 1.6), -90)
	RoomBuilder.prop(r, "lantern_chandelier_01", Vector3(4.5, 4.5, 6.0), 0, 1.0, false)
	RoomBuilder.prop(r, "lantern_chandelier_01", Vector3(9.5, 4.5, 6.0), 0, 1.0, false)
	RoomBuilder.prop(r, "hanging_picture_frame_03", Vector3(5.0, 2.3, 11.84), 180, 1.3, false)
	RoomBuilder.prop(r, "ornate_mirror_01", Vector3(8.0, 2.2, 11.85), 180, 1.0, false)
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
		"openings": {"e": [[4.0, 1.2, 2.3]]},
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
	RoomBuilder.prop(r, "wooden_crate_01", Vector3(12.6, 0, 8.5), 80)
	RoomBuilder.prop(r, "hanging_industrial_lamp", Vector3(7, 3.1, 5), 0, 1.0, false)
	RoomBuilder.prop(r, "propane_tank", Vector3(13, 0, 1), 0)
	RoomBuilder.light(r, Vector3(7, 2.6, 5), Color(1.0, 0.8, 0.55), 1.6, 8.0, true, true)
	place_zombie("Z_vault_1", Vector3(-4, 0, 22), 180, "riot")
	place_zombie("Z_vault_grab", Vector3(-8, 0, 24), 200, "grappler")
	place_zombie("Z_vault_2", Vector3(1, 0, 24), 200, "brute")
	place_zombie("Z_boiler_burn", Vector3(10, 0, 22), 180, "burner")
	place_pickup("weapon:gl", Vector3(2.3, 0.37, 24.4), "vault_gl")
	place_pickup("ammo:grenades", Vector3(2.9, 0.37, 24.6), "vault_gl_ammo")

# ---------------- Boiler room ----------------
func _boiler_room() -> void:
	var r := RoomBuilder.build(self, {
		"id": "BoilerRoom", "pos": Vector3(4, 0, 16), "size": Vector3(10, 4, 10),
		"floor": "boiler_floor", "wall": "boiler_wall", "trim": Color(0.2, 0.2, 0.2),
		"floor_look": {"tile_size": 1.5},
		"wall_look": {"tile_size": 2.0},
		"look": {"grime_amount": 0.9, "grime_height": 1.4, "wetness": 0.3},
		"skip_walls": ["w"],
	})
	RoomBuilder.prop(r, "portable_generator", Vector3(5, 0, 5), 30)
	RoomBuilder.prop(r, "power_box_01", Vector3(9.8, 1.4, 3), -90, 1.0, false)
	RoomBuilder.prop(r, "metal_jerrycan", Vector3(6, 0, 6.2), 80)
	RoomBuilder.prop(r, "Barrel_01", Vector3(8.6, 0, 8.6))
	RoomBuilder.prop(r, "Barrel_01", Vector3(7.8, 0, 9.0), 40)
	RoomBuilder.light(r, Vector3(5, 3.4, 5), Color(1.0, 0.35, 0.2), 1.4, 9.0, true, true)
	place_door(Vector3(4, 0, 20.6), 90, Door.Kind.MANUAL, "steel", 1.2, 2.3, "boiler_door")
	place_pickup("ammo:fuel", Vector3(10, 0.1, 22.2), "boiler_fuel")
	place_pickup("gunpowder", Vector3(12.5, 0.1, 18), "boiler_powder")

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

## Rain over an outdoor area. `top` is the local centre of the emitter (just
## under the sky), `extents` the half-size of the area it covers.
func _rain(parent: Node3D, top: Vector3, extents: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = int(clampf(extents.x * extents.z * 7.0, 400.0, 2500.0))
	p.lifetime = 1.0
	p.visibility_aabb = AABB(Vector3(-extents.x - 2, -top.y - 1, -extents.z - 2), Vector3(extents.x * 2 + 4, top.y + 2, extents.z * 2 + 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(extents.x, 0.2, extents.z)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -6, 0)
	p.process_material = pm
	var m := QuadMesh.new()
	m.size = Vector2(0.012, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.75, 0.85, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.material = mat
	p.draw_pass_1 = m
	p.position = top
	parent.add_child(p)


# ---------------- Scripted horror ----------------
func _horror_beats() -> void:
	place_scare("hall_entry_sting", "stinger", Vector3(0, 0, 1), Vector3(4, 3, 2))
	place_scare("hall_whisper", "whisper", Vector3(-8, 0, 12), Vector3(4, 3, 4), {"target": Vector3(-11, 1.5, 14), "text": "...forty-one... forty-two..."})
	place_scare("corridor_lights", "lights_out", Vector3(-20, 0, 5.2), Vector3(2, 3, 2.6), {"room": "WestCorridor", "duration": 7.0})
	place_scare("office_bang", "door_bang", Vector3(15, 0, 5), Vector3(3, 3, 3), {"target": Vector3(19.8, 1.2, 7.6)})
	place_scare("reading_drop", "body_drop", Vector3(-20, 0, -2), Vector3(3, 3, 3), {"target": Vector3(-19, 0, -3)})
	place_scare("street_window", "window_break", Vector3(4, 0, -26), Vector3(4, 3, 4), {"target": Vector3(7, 0, -29.4), "spawn_count": 3})
	place_scare("hall_wake", "wake_dead", Vector3(-8, 0, 15), Vector3(3, 3, 2), {"group": "hall_dead"})
	place_scare("vault_lights", "lights_out", Vector3(-6, 0, 17), Vector3(3, 3, 2), {"room": "RecordsVault", "duration": 5.0})
	# The Tallyman: first seen behind the reading-room glass, then hunting from chapter 2.
	place_stalker(Vector3(-24, 0, -5), GameState.has_flag("tallyman_awake"))
