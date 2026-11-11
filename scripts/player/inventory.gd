class_name Inventory
extends RefCounted

var weapons: Array[String] = ["knife", "p9"]
var mag: Dictionary = {"p9": 15}
var ammo: Dictionary = {"9mm": 30}
var items: Dictionary = {"herb_green": 1}
var key_items: Array[String] = []
var equipped := "p9"

func has_weapon(id: String) -> bool:
	return Cheats.on("all_weapons") or weapons.has(id)

func add_weapon(id: String) -> void:
	if not weapons.has(id):
		weapons.append(id)
		mag[id] = WeaponDB.WEAPONS[id].get("mag", 0)

func add_ammo(kind: String, n: int) -> void:
	ammo[kind] = min(ammo.get(kind, 0) + n, WeaponDB.AMMO[kind]["stack"] * 4)

func add_item(id: String, n := 1) -> void:
	items[id] = items.get(id, 0) + n

func take_item(id: String) -> bool:
	if items.get(id, 0) <= 0:
		return false
	items[id] -= 1
	if items[id] == 0:
		items.erase(id)
	return true

func to_dict() -> Dictionary:
	return {"weapons": weapons, "mag": mag, "ammo": ammo, "items": items, "keys": key_items, "equipped": equipped}

func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	weapons.assign(d.get("weapons", weapons))
	mag = d.get("mag", mag)
	ammo = d.get("ammo", ammo)
	items = d.get("items", items)
	key_items.assign(d.get("keys", []))
	equipped = d.get("equipped", equipped)
