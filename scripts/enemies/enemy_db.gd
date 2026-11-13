class_name EnemyDB
## Enemy roster. All designs original to RaGoon City.
## speed in m/s, dmg per hit, flags drive special behavior in zombie.gd.
## Health is balanced in Warden P9 body shots (26 damage; a head shot is x3):
## a shambler takes 4 body shots or 2 to the head, and each area carries more
## ammo than it takes to clear it with body shots (tools/balance_report.py).

const TYPES := {
	"shambler": {"hp": 100, "speed": 0.9, "dmg": 20, "reach": 1.2, "drop": "zombie",
		"looks": ["office", "nurse", "cook", "jogger", "cop", "mechanic", "student", "suit"]},
	"runner": {"hp": 60, "speed": 2.6, "dmg": 14, "reach": 1.3, "drop": "zombie", "lunge": true,
		"looks": ["jogger", "student", "courier"]},
	"riot": {"hp": 150, "speed": 0.85, "dmg": 24, "reach": 1.3, "drop": "brute", "shield": true, "shield_hp": 100, "looks": ["riot"]},
	"bloater": {"hp": 130, "speed": 0.6, "dmg": 28, "reach": 1.2, "drop": "zombie", "death_gas": true, "bulk": 1.45, "looks": ["bloated"]},
	"brute": {"hp": 360, "speed": 1.35, "dmg": 38, "reach": 1.6, "drop": "brute", "charge": true, "bulk": 1.5, "height": 1.2, "looks": ["brute"]},
	"crawler": {"hp": 60, "speed": 0.55, "dmg": 16, "reach": 0.9, "drop": "zombie", "crawl": true, "ankle_grab": true, "looks": ["office", "cop"]},
	"possum": {"hp": 100, "speed": 0.95, "dmg": 22, "reach": 1.2, "drop": "zombie", "plays_dead": true, "looks": ["suit", "nurse"]},
	"screamer": {"hp": 75, "speed": 0.7, "dmg": 12, "reach": 1.1, "drop": "zombie", "screams": true, "looks": ["screamer"]},
	"burner": {"hp": 110, "speed": 1.1, "dmg": 18, "reach": 1.2, "drop": "zombie", "fire_immune": true, "ignites": true, "looks": ["burnt"]},
	"grappler": {"hp": 150, "speed": 1.2, "dmg": 8, "reach": 1.4, "drop": "brute", "pins": true, "height": 1.1, "looks": ["grappler"]},
	"ventling": {"hp": 110, "speed": 2.2, "dmg": 26, "reach": 1.5, "drop": "zombie", "ceiling_drop": true, "height": 1.15, "mutant": true, "looks": ["ventling"]},
	"spitter": {"hp": 85, "speed": 0.8, "dmg": 10, "reach": 1.1, "drop": "zombie", "ranged": "acid", "range": 11.0, "mutant": true, "looks": ["spitter"]},
	"hound": {"hp": 50, "speed": 3.5, "dmg": 15, "reach": 1.2, "drop": "none", "quadruped": true, "lunge": true, "looks": ["hound"]},
	"larva": {"hp": 20, "speed": 1.6, "dmg": 6, "reach": 0.7, "drop": "none", "crawl": true, "tiny": true, "looks": ["larva"]},
	"brood_mother": {"hp": 900, "boss": true, "speed": 0.0, "dmg": 30, "reach": 2.2, "drop": "brute", "spawner": "larva", "spawn_every": 7.0, "bulk": 2.2, "mutant": true, "looks": ["brood"]},
}

const ZONE_MULT := {"head": 3.0, "torso": 1.0, "arm": 0.6, "leg": 0.8}

static func get_type(id: String) -> Dictionary:
	return TYPES.get(id, TYPES["shambler"])

## Own rigged, animated model per body plan. Human infected share the scanned
## townspeople; the others each need their own.
const OWN_MODEL := {"quadruped": "hound", "tiny": "larva", "brood_mother": "brood_mother"}

## Whether this type has a real, animated model in the game. Types without one
## are never spawned: no stand-in made of boxes ever reaches a build.
static func has_model(id: String) -> bool:
	var d := get_type(id)
	var own := ""
	if d.get("quadruped"):
		own = OWN_MODEL["quadruped"]
	elif d.get("tiny"):
		own = OWN_MODEL["tiny"]
	elif id == "brood_mother":
		own = OWN_MODEL["brood_mother"]
	if own == "":
		return true
	return ResourceLoader.exists("res://assets/characters/enemies/%s/%s.glb" % [own, own]) \
		and ResourceLoader.exists("res://assets/characters/enemies/%s/%s_anims.res" % [own, own])
