class_name WeaponDB
## Weapon catalog. Names and models are original; stats tuned for mobile pacing.
## kind: hitscan | pellets | projectile | melee | flame
## Hitbox multipliers live on the enemy (head x3, legs cripple, etc.).

const WEAPONS := {
	"knife": {"name": "Field Knife", "kind": "melee", "damage": 30, "rate": 0.45, "range": 1.8, "durability": 60, "slot": "melee"},
	"hatchet": {"name": "Fire Hatchet", "kind": "melee", "damage": 70, "rate": 0.9, "range": 2.1, "durability": 40, "slot": "melee", "stagger": 0.6},
	"p9": {"name": "Warden P9", "kind": "hitscan", "damage": 26, "rate": 0.28, "mag": 15, "reload": 1.5, "ammo": "9mm", "spread": 0.8, "slot": "sidearm"},
	"vk18": {"name": "Vesk 18 (burst)", "kind": "hitscan", "damage": 22, "rate": 0.09, "burst": 3, "burst_gap": 0.35, "mag": 18, "reload": 1.6, "ammo": "9mm", "spread": 1.4, "slot": "sidearm"},
	"bastion": {"name": "Bastion .50 Revolver", "kind": "hitscan", "damage": 160, "rate": 0.95, "mag": 6, "reload": 2.6, "ammo": "50cal", "spread": 0.3, "pierce": 2, "slot": "sidearm", "stagger": 1.0},
	"hornet": {"name": "Hornet SMG", "kind": "hitscan", "damage": 14, "rate": 0.07, "mag": 40, "reload": 2.0, "ammo": "9mm", "spread": 2.6, "slot": "primary", "auto": true},
	"m12": {"name": "Ranger M12 Pump", "kind": "pellets", "pellets": 9, "damage": 13, "rate": 0.95, "mag": 5, "reload": 0.55, "reload_per_shell": true, "ammo": "shells", "spread": 7.0, "slot": "primary", "stagger": 1.0},
	"breacher": {"name": "Breacher Auto-12", "kind": "pellets", "pellets": 8, "damage": 11, "rate": 0.32, "mag": 8, "reload": 2.8, "ammo": "shells", "spread": 9.0, "slot": "primary", "auto": true},
	"longshot": {"name": "Longshot .308", "kind": "hitscan", "damage": 220, "rate": 1.3, "mag": 5, "reload": 2.8, "ammo": "rifle", "spread": 0.05, "pierce": 3, "slot": "primary", "scope": true},
	"carbine": {"name": "Sentry Carbine", "kind": "hitscan", "damage": 32, "rate": 0.11, "mag": 30, "reload": 2.2, "ammo": "rifle", "spread": 1.2, "slot": "primary", "auto": true},
	"bolt": {"name": "Quarrel Crossbow", "kind": "projectile", "projectile": "bolt", "damage": 120, "rate": 1.1, "mag": 1, "reload": 1.4, "ammo": "bolts", "slot": "primary", "silent": true},
	"gl": {"name": "Thumper Grenade Launcher", "kind": "projectile", "projectile": "grenade", "damage": 180, "radius": 4.5, "rate": 1.2, "mag": 1, "reload": 1.8, "ammo": "grenades", "slot": "heavy"},
	"flamer": {"name": "Cinder Flamethrower", "kind": "flame", "damage": 9, "rate": 0.05, "mag": 200, "reload": 3.2, "ammo": "fuel", "range": 7.0, "slot": "heavy", "auto": true, "burn": 6.0},
	"rocket": {"name": "Last Word Rocket Launcher", "kind": "projectile", "projectile": "rocket", "damage": 600, "radius": 6.0, "rate": 1.6, "mag": 1, "reload": 2.5, "ammo": "rockets", "slot": "heavy"},
	"flash": {"name": "Flash Grenade", "kind": "throwable", "effect": "flash", "rate": 1.0, "ammo": "flash", "slot": "throwable"},
	"frag": {"name": "Frag Grenade", "kind": "throwable", "effect": "frag", "damage": 220, "radius": 5.0, "rate": 1.0, "ammo": "frag", "slot": "throwable"},
}

const AMMO := {
	"9mm": {"name": "9mm Rounds", "stack": 60, "pickup": 15},
	"50cal": {"name": ".50 Magnum Rounds", "stack": 12, "pickup": 6},
	"shells": {"name": "Shotgun Shells", "stack": 30, "pickup": 6},
	"rifle": {"name": "Rifle Rounds", "stack": 60, "pickup": 10},
	"bolts": {"name": "Crossbow Bolts", "stack": 12, "pickup": 4},
	"grenades": {"name": "Launcher Grenades", "stack": 6, "pickup": 2},
	"fuel": {"name": "Fuel Canister", "stack": 400, "pickup": 100},
	"rockets": {"name": "Rocket", "stack": 2, "pickup": 1},
	"flash": {"name": "Flash Grenade", "stack": 3, "pickup": 1},
	"frag": {"name": "Frag Grenade", "stack": 3, "pickup": 1},
}

const ITEMS := {
	"herb_green": {"name": "Green Fern", "heal": 35, "glow": Color(0.35, 1.0, 0.45)},
	"herb_red": {"name": "Red Fern", "combine_with": "herb_green", "result": "herb_mix", "glow": Color(1.0, 0.3, 0.25)},
	"herb_mix": {"name": "Fern Mixture", "heal": 100, "glow": Color(1.0, 0.75, 0.3)},
	"medkit": {"name": "Trauma Kit", "heal": 100, "glow": Color(0.9, 0.95, 1.0)},
	"bandage": {"name": "Gauze Wrap", "heal": 20, "glow": Color(0.95, 0.95, 0.9)},
	"gunpowder": {"name": "Gunpowder", "craft": true, "glow": Color(1.0, 0.85, 0.5)},
	"ink_ribbon": {"name": "Tape Reel", "glow": Color(0.6, 0.8, 1.0)},
}

## Weighted drop tables used by enemies and breakable crates.
const DROPS := {
	"zombie": [["ammo:9mm", 30], ["ammo:shells", 10], ["herb_green", 12], ["gunpowder", 8], ["none", 40]],
	"crate": [["ammo:9mm", 30], ["ammo:shells", 20], ["ammo:rifle", 10], ["herb_green", 15], ["gunpowder", 15], ["ammo:grenades", 5], ["none", 5]],
	"brute": [["ammo:50cal", 30], ["ammo:grenades", 30], ["medkit", 25], ["herb_mix", 15]],
}

static func roll_drop(table: String, rng: RandomNumberGenerator) -> String:
	var entries: Array = DROPS.get(table, [])
	var total := 0
	for e in entries:
		total += e[1]
	var r := rng.randi_range(1, max(total, 1))
	for e in entries:
		r -= e[1]
		if r <= 0:
			return e[0]
	return "none"
