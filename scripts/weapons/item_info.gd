class_name ItemInfo
## What the inventory shows for each thing a survivor can carry: names,
## descriptions, icons, stack sizes and combine recipes.
##
## Ids: weapon ids from WeaponDB.WEAPONS ("p9"), ammo as "ammo:<kind>"
## ("ammo:9mm"), items from WeaponDB.ITEMS ("herb_green"). Grenades are
## weapons that stack ("frag", "flash"). Key items are "key:<id>" and files
## "file:<id>"; they never take a bag slot.

const DESC := {
	"knife": "A paramedic's fixed-blade rescue knife, honed well past regulation. Quiet, and it never runs dry. Tap FIRE to slash; keep tapping for a three-cut combo.",
	"hatchet": "Pried out of a fire-point cabinet. Slow to swing, but one good chop splits a skull or stops a charging infected cold.",
	"p9": "The city wardens' standard 9 mm sidearm. Fifteen rounds, light recoil, honest and reliable.",
	"vk18": "A machine pistol that fires three-round bursts. It eats 9 mm fast, but every burst lands close together.",
	"bastion": "A six-shot hand cannon. One round punches through two bodies and rocks even the big ones back on their heels.",
	"hornet": "Compact and fully automatic. Sprays 9 mm at close range; keep bursts short to stay on target.",
	"m12": "A police pump-action shotgun. Nine pellets a shell and enough stopping power to clear a corridor. Loads one shell at a time.",
	"breacher": "A drum-fed automatic shotgun built for breaching doors. Brutal up close, and hungry for shells.",
	"longshot": "A scoped bolt-action rifle. Each round goes through three targets, and a head hit ends anything that was once human.",
	"carbine": "A select-fire rifle from a security armoury. Accurate, quick and fully automatic.",
	"bolt": "Silent. Bolts pin the infected where they stand, and nothing nearby hears a thing.",
	"gl": "A single-shot 40 mm launcher. The blast hurts anyone standing too close, partners included.",
	"flamer": "A pressurised fuel rig that sets the infected burning. Short reach; mind where your partner is standing.",
	"rocket": "For when nothing else has worked. One rocket per load, and you will want a lot of distance.",
	"flash": "Blinds and staggers everything in the blast. Look away when it goes, and tell your partner to.",
	"frag": "A stick grenade with a long fuse and a wide blast. It hurts anyone in range, partners included.",
	"ammo:9mm": "Fits the Warden P9, the Vesk 18 and the Hornet SMG.",
	"ammo:50cal": "Heavy magnum rounds for the Bastion revolver. Rare; make each one count.",
	"ammo:shells": "12-gauge buckshot for the Ranger M12 and the Breacher.",
	"ammo:rifle": "Rifle rounds for the Longshot and the Sentry Carbine.",
	"ammo:bolts": "Steel-tipped bolts for the Quarrel crossbow.",
	"ammo:grenades": "40 mm rounds for the Thumper launcher.",
	"ammo:fuel": "A pressurised canister for the Cinder flamethrower.",
	"ammo:rockets": "A single rocket for the Last Word.",
	"herb_green": "A medicinal fern that grows in the city's damp corners. Restores a little health. Combine two for a stronger dose, or mix it with a red fern.",
	"herb_red": "Useless on its own. Ground together with a green fern it becomes a powerful remedy.",
	"herb_gg": "Two green ferns crushed together. Restores a good share of health.",
	"herb_mix": "Green and red ferns ground into a paste. Restores full health.",
	"medkit": "A sealed emergency kit with a clotting injector. Restores full health.",
	"bandage": "Stops light bleeding. Restores a little health.",
	"gunpowder": "Loose powder from spent cartridges. Combine two to press fifteen 9 mm rounds.",
	"ink_ribbon": "A reel of tape for the old recorders in the safe rooms.",
}

const KEY_NAMES := {
	"brass_quill_key": ["Brass Quill Key", "A heavy brass key with a quill engraved on its bow. One of the archive's old locks will take it."],
	"vault_card": ["Vault Elevator Key Card", "Warden Hardass's staff card for the lift in the records vault, worn white at the edges. The lift runs on the vault's own circuit: no power, no ride. The breaker for it is in the boiler room."],
	"clock_key": ["Brass Winding Key", "A small brass crank key, polished by thirty years of one man's fingers. It fits the winding hole of a big clock."],
	"fuse": ["Field Fuse", "A porcelain cartridge fuse the size of a fist, stamped GPO 60A FIELD. The engine hall generator won't excite without it."],
	"diesel_can": ["Jerrycan of Diesel", "Twenty litres of red diesel from the coal yard shed. Heavy, and it sloshes. The generator's day tank is dry."],
	"crank_handle": ["Starting Handle", "The generator's iron starting handle, from Warden Hardass's belt. It's still warm."],
}

const FILES := {
	"lift_note": ["Note on the Lift Doors", "LIFT DEAD AGAIN.\n\nVault breaker tripped when the city went dark. The lift runs off the vault circuit, not the generator, so nothing moves down here until somebody resets it.\n\nBreaker panel is in the BOILER ROOM: through the vault, east door. Big red handle on the right of the box. Push it all the way up.\n\nDon't send anyone down alone.\n\n- O.V."],
	"keeper_ledger": ["Keeper's Night Ledger", "ORRIN VELL. KEEPER, RIVER DISTRICT SERVICE TUNNELS. NIGHT LEDGER.\n\n2 Oct. Rounds 11 to 4. All slave clocks true to the master. Pump room dry.\n\n9 Oct. Knocking again under the deep stacks. Told the Warden. He says it's the river. The river doesn't keep time.\n\n14 Oct. It knocks on the minute. Every minute, the same as the clocks.\n\n15 Oct. I pulled the field fuse at ten past eleven so nothing down here could run without me. Locked it in the master clock's drawer. The winding key is on the surveyor's desk in the survey room, under his lamp. Whoever needs the engine needs the clock first.\n\n16 Oct. The Warden has stopped coming down. I can hear it counting."],
	"survey_note": ["Survey Office Memo, 1891", "RIVER DISTRICT SURVEY: FIELD NOTE, 1891.\n\nThe old burial ground under Ashgrove Street was not cleared when the walled street was built over it. The parish register gives some four hundred and seventy interments. The bones recovered by the drainage gangs come to some three hundred.\n\nThe men will not work the Deep Tunnel heading after dark. They say they hear tallying.\n\nRecommend the heading be bricked up and the matter not entered in the public survey.\n\n- J. Arkwright, Assistant Surveyor"],
	"shelter_log": ["Shelter Log", "Night two. We sealed the hall doors with forty-one people inside.\n\nThe wardens said the buses would come at dawn. Dawn came. No buses.\n\nA woman by the reading room has a bite on her wrist she keeps hidden under her sleeve. Nobody wants to be the one to say it.\n\nIf you're reading this, don't open the vault stairs alone. Whatever we put down there was still knocking this morning."],
}

## How many fit in one bag slot.
const STACK_ITEMS := {
	"herb_green": 3, "herb_red": 3, "herb_gg": 2, "herb_mix": 2,
	"medkit": 1, "bandage": 3, "gunpowder": 6, "ink_ribbon": 5,
}

## a + b -> [result, how many]. Order does not matter.
const RECIPES := [
	["herb_green", "herb_green", "herb_gg", 1],
	["herb_green", "herb_red", "herb_mix", 1],
	["herb_gg", "herb_red", "herb_mix", 1],
	["gunpowder", "gunpowder", "ammo:9mm", 15],
]

static func kind(id: String) -> String:
	if id.begins_with("ammo:"):
		return "ammo"
	if id.begins_with("key:"):
		return "key"
	if id.begins_with("file:"):
		return "file"
	var w: Dictionary = WeaponDB.WEAPONS.get(id, {})
	if not w.is_empty():
		return "throwable" if w.get("kind") == "throwable" else "weapon"
	return "item"

static func display_name(id: String) -> String:
	match kind(id):
		"ammo":
			return WeaponDB.AMMO.get(id.substr(5), {}).get("name", id)
		"weapon", "throwable":
			return WeaponDB.WEAPONS[id]["name"]
		"key":
			var k: String = id.substr(4)
			return KEY_NAMES.get(k, [k.capitalize().replace("_", " ")])[0]
		"file":
			var f: String = id.substr(5)
			return FILES.get(f, [f.capitalize().replace("_", " ")])[0]
	return WeaponDB.ITEMS.get(id, {}).get("name", id.capitalize())

static func description(id: String) -> String:
	match kind(id):
		"key":
			return KEY_NAMES.get(id.substr(4), ["", "Opens a lock somewhere in RaGoon City."])[1]
		"file":
			return FILES.get(id.substr(5), ["", "A document recovered from the city."])[1]
	return DESC.get(id, "")

static func stack(id: String) -> int:
	match kind(id):
		"ammo":
			return WeaponDB.AMMO.get(id.substr(5), {}).get("stack", 30)
		"throwable":
			return WeaponDB.AMMO.get(id, {}).get("stack", 3)
		"weapon":
			return 1
	return STACK_ITEMS.get(id, 1)

static var _icons: Dictionary = {}

static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var name := id.replace(":", "_")
	if id.begins_with("key:") and not ResourceLoader.exists("res://assets/ui/items/%s.jpg" % name):
		name = "key"
	elif id.begins_with("file:"):
		name = "file"
	var path := "res://assets/ui/items/%s.jpg" % name
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[id] = tex
	return tex

static func recipe(a: String, b: String) -> Array:
	for r in RECIPES:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return [r[2], r[3]]
	return []

## Can these two be combined at all (recipe, or ammo into its gun)?
static func combinable(a: String, b: String) -> bool:
	if not recipe(a, b).is_empty():
		return true
	return _ammo_fits(a, b) or _ammo_fits(b, a)

static func _ammo_fits(weapon_id: String, ammo_id: String) -> bool:
	return kind(weapon_id) == "weapon" and kind(ammo_id) == "ammo" and WeaponDB.WEAPONS[weapon_id].get("ammo", "") == ammo_id.substr(5)

## Weapon stats for the details panel, each 0..1.
static func stats(id: String) -> Dictionary:
	var w: Dictionary = WeaponDB.WEAPONS.get(id, {})
	if w.is_empty() or w.get("kind") == "throwable":
		return {}
	var dmg: float = float(w.get("damage", 0)) * float(w.get("pellets", 1))
	var out := {
		"Power": clampf(dmg / 260.0, 0.06, 1.0),
		"Rate": clampf(0.12 / maxf(float(w.get("rate", 1.0)), 0.05), 0.06, 1.0) if w.get("kind") != "flame" else 1.0,
	}
	if w.has("mag"):
		out["Capacity"] = clampf(float(w["mag"]) / 40.0, 0.06, 1.0)
	else:
		out["Reach"] = clampf(float(w.get("range", 2.0)) / 3.0, 0.06, 1.0)
	return out
