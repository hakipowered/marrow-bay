extends RefCounted
## Infected who join a level only at higher "pressure" (GameState.pressure:
## the difficulty, plus one when two survivors play). Tier 2 comes in on
## Normal co-op and Hard solo, tier 3 only on Hard co-op. Each stands where a
## lone one would: on open floor in a room that already has a fight, never
## at a checkpoint or on top of an item. tests/extra_infected.gd checks every
## one at the highest pressure (floor, room to stand, navigation, away from
## where the survivors come in), and the level probe runs with them too.
## Easy solo and Normal solo play exactly the levels as built.

const LEVELS := {
	"res://scenes/levels/archive_hub.tscn": [
		# Ashgrove Street: one more on each side of the burning ambulance,
		# and a crawler under the cars on the way to the gates.
		{"tier": 2, "name": "X_street_4", "at": Vector3(-14.5, 0, -20.5), "rot": 60, "variant": "shambler", "look": "nurse"},
		{"tier": 2, "name": "X_street_5", "at": Vector3(14.0, 0, -26.0), "rot": 200, "variant": "shambler", "asleep": true, "look": "suit"},
		{"tier": 3, "name": "X_street_crawl2", "at": Vector3(-7.5, 0, -18.5), "rot": 150, "variant": "crawler"},
		# The courtyard behind the gates.
		{"tier": 2, "name": "X_court_3", "at": Vector3(-6.5, 0, -11.0), "rot": 120, "variant": "shambler", "look": "cook"},
		{"tier": 3, "name": "X_court_4", "at": Vector3(6.5, 0, -5.0), "rot": 230, "variant": "crawler", "look": "office"},
		# The Great Hall, away from the checkpoint by the main doors.
		{"tier": 2, "name": "X_hall_3", "at": Vector3(10.5, 0, 13.0), "rot": 250, "variant": "shambler", "asleep": true, "look": "student"},
		{"tier": 2, "name": "X_hall_4", "at": Vector3(-5.0, 0, 11.0), "rot": 160, "variant": "shambler", "look": "office"},
		{"tier": 3, "name": "X_hall_crawl", "at": Vector3(-2.5, 0, 14.5), "rot": 200, "variant": "crawler", "look": "cop"},
		# The West Corridor and the Reading Room (the side trip).
		{"tier": 3, "name": "X_corr_crawl", "at": Vector3(-14.5, 0, 6.0), "rot": 90, "variant": "crawler"},
		{"tier": 2, "name": "X_read_3", "at": Vector3(-24.5, 0, 0.5), "rot": 90, "variant": "shambler", "asleep": true, "look": "suit"},
		# The Records Vault fight and the boiler room.
		{"tier": 2, "name": "X_vault_3", "at": Vector3(-1.0, 0, 20.0), "rot": 200, "variant": "shambler", "look": "cop"},
		{"tier": 3, "name": "X_vault_4", "at": Vector3(-7.0, 0, 20.0), "rot": 160, "variant": "runner", "asleep": true},
		{"tier": 2, "name": "X_boiler_2", "at": Vector3(8.5, 0, 24.0), "rot": 300, "variant": "shambler", "look": "mechanic"},
	],
	"res://scenes/levels/undercroft.tscn": [
		# (The service corridor has its own body through the ceiling.)
		# The survey room and the clock gallery.
		{"tier": 2, "name": "X_c2_survey3", "at": Vector3(15.5, 0, -7.5), "rot": 30, "variant": "shambler", "asleep": true, "look": "nurse"},
		{"tier": 3, "name": "X_c2_survey_crawl", "at": Vector3(17.0, 0, -1.5), "rot": 200, "variant": "crawler", "look": "office"},
		{"tier": 2, "name": "X_c2_gallery2", "at": Vector3(26.0, 0, -7.0), "rot": 120, "variant": "shambler", "look": "cop"},
		# The engine hall (away from its checkpoint by the corridor) and the coal yard.
		{"tier": 2, "name": "X_c2_hall3", "at": Vector3(53.0, 0, -3.0), "rot": 200, "variant": "shambler", "look": "mechanic"},
		{"tier": 3, "name": "X_c2_hall_possum", "at": Vector3(50.5, 0, 9.5), "rot": 80, "variant": "possum"},
		{"tier": 2, "name": "X_c2_yard4", "at": Vector3(76.0, 0, -3.0), "rot": 250, "variant": "runner", "asleep": true},
		{"tier": 3, "name": "X_c2_yard5", "at": Vector3(58.5, 0, 7.0), "rot": 290, "variant": "shambler", "asleep": true, "look": "jogger"},
	],
}

static func for_level(path: String) -> Array:
	return LEVELS.get(path, [])
