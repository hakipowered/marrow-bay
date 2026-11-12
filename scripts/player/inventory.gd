class_name Inventory
extends RefCounted
## A survivor's bag, RE-style: SIZE slots holding weapons and stacks of
## supplies (see ItemInfo for ids and stack sizes). Key items and files are
## carried separately and never take a slot. Each player's own phone owns its
## bag; Player mirrors it to the partner and the host for saves.

signal changed

const SIZE := 16

## One entry per slot: null, or {"id": String, "n": int}.
var slots: Array = []
## Rounds loaded in each gun.
var mag: Dictionary = {}
var key_items: Array[String] = []
var files: Array[String] = []
var equipped := "p9"

func _init() -> void:
	slots.resize(SIZE)
	add("knife")
	add("p9")
	mag["p9"] = 15
	add("ammo:9mm", 30)
	add("herb_green")

# ---------- Queries ----------

func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["id"] == id:
			n += int(s["n"])
	return n

static func ammo_id(kind: String) -> String:
	# Grenades are thrown straight from their stack.
	return kind if ItemInfo.kind(kind) == "throwable" else "ammo:" + kind

func ammo_count(kind: String) -> int:
	return count(ammo_id(kind))

func free_slots() -> int:
	return slots.count(null)

## How many more of id would fit.
func room_for(id: String) -> int:
	var st := ItemInfo.stack(id)
	var n := free_slots() * st
	for s in slots:
		if s != null and s["id"] == id:
			n += maxi(st - int(s["n"]), 0)
	return n

func has_weapon(id: String) -> bool:
	if Cheats.on("all_weapons") and WeaponDB.WEAPONS.has(id) and not WeaponDB.WEAPONS[id].get("enemy_only", false):
		return true
	return count(id) > 0

## Weapons in bag order (grenades included while any are left).
func weapon_list() -> Array[String]:
	var out: Array[String] = []
	for s in slots:
		if s != null and ItemInfo.kind(s["id"]) in ["weapon", "throwable"] and not out.has(s["id"]):
			out.append(s["id"])
	if Cheats.on("all_weapons"):
		for id in WeaponDB.WEAPONS:
			if not out.has(id) and has_weapon(id):
				out.append(id)
	return out

# ---------- Changes ----------

## Adds up to n of id, topping up partial stacks first. Returns how many fit.
func add(id: String, n := 1) -> int:
	var st := ItemInfo.stack(id)
	var left := n
	for s in slots:
		if left <= 0:
			break
		if s != null and s["id"] == id and int(s["n"]) < st:
			var put := mini(st - int(s["n"]), left)
			s["n"] = int(s["n"]) + put
			left -= put
	for i in SIZE:
		if left <= 0:
			break
		if slots[i] == null:
			var put := mini(st, left)
			slots[i] = {"id": id, "n": put}
			left -= put
	if left != n:
		changed.emit()
	return n - left

## Takes up to n of id, from the smallest stacks first. Returns how many.
func remove(id: String, n := 1) -> int:
	var left := n
	while left > 0:
		var best := -1
		for i in SIZE:
			if slots[i] != null and slots[i]["id"] == id and (best < 0 or int(slots[i]["n"]) < int(slots[best]["n"])):
				best = i
		if best < 0:
			break
		left -= take_from_slot(best, left, false)
	if left != n:
		changed.emit()
	return n - left

func take_from_slot(i: int, n := 1, notify := true) -> int:
	var s = slots[i]
	if s == null:
		return 0
	var got := mini(n, int(s["n"]))
	s["n"] = int(s["n"]) - got
	if int(s["n"]) <= 0:
		slots[i] = null
		if ItemInfo.kind(s["id"]) == "weapon":
			mag.erase(s["id"])
	if notify and got > 0:
		changed.emit()
	return got

func swap(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()

## Picking up a gun you already carry gives you its ammo instead.
func add_weapon(id: String) -> bool:
	if ItemInfo.kind(id) == "throwable":
		return add(id) > 0
	if count(id) > 0:
		var kind: String = WeaponDB.WEAPONS[id].get("ammo", "")
		return kind != "" and add_ammo(kind, WeaponDB.AMMO[kind]["pickup"]) > 0
	if add(id) == 0:
		return false
	mag[id] = WeaponDB.WEAPONS[id].get("mag", 0)
	return true

func add_ammo(kind: String, n: int) -> int:
	return add(ammo_id(kind), n)

func take_ammo(kind: String, n: int) -> int:
	return remove(ammo_id(kind), n)

func add_item(id: String, n := 1) -> int:
	return add(id, n)

func take_item(id: String) -> bool:
	return remove(id, 1) == 1

func add_key(id: String) -> void:
	if not key_items.has(id):
		key_items.append(id)
		changed.emit()

func add_file(id: String) -> void:
	if not files.has(id):
		files.append(id)
		changed.emit()

## What a pickup string ("ammo:9mm", "weapon:m12", "key:x", "file:x", item id)
## would add, and whether the bag has room for any of it.
func can_take(item: String) -> bool:
	var parts := item.split(":")
	match parts[0]:
		"key", "file":
			return true
		"ammo":
			return room_for(ammo_id(parts[1])) > 0
		"weapon":
			var id := parts[1]
			if ItemInfo.kind(id) == "throwable":
				return room_for(id) > 0
			if count(id) > 0:
				var kind: String = WeaponDB.WEAPONS[id].get("ammo", "")
				return kind != "" and room_for(ammo_id(kind)) > 0
			return free_slots() > 0
	return room_for(item) > 0

## Combines slot a into slot b: a recipe, or loading ammo into a gun.
## Returns a line for the player ("" when the two don't go together).
func combine(a: int, b: int) -> String:
	if a == b and (slots[a] == null or int(slots[a]["n"]) < 2):
		return ""
	if slots[a] == null or slots[b] == null:
		return ""
	var ida: String = slots[a]["id"]
	var idb: String = slots[b]["id"]
	# Ammo onto its gun: a manual reload from that stack.
	for pair in [[ida, idb, b, a], [idb, ida, a, b]]:
		if ItemInfo._ammo_fits(pair[0], pair[1]):
			var w: Dictionary = WeaponDB.WEAPONS[pair[0]]
			var need: int = int(w.get("mag", 0)) - int(mag.get(pair[0], 0))
			if need <= 0:
				return "%s is already fully loaded." % w["name"]
			var got := take_from_slot(pair[3], need, false)
			mag[pair[0]] = int(mag.get(pair[0], 0)) + got
			changed.emit()
			return "Loaded %d into the %s." % [got, w["name"]]
	var r := ItemInfo.recipe(ida, idb)
	if r.is_empty():
		return ""
	take_from_slot(a, 1, false)
	take_from_slot(b, 1, false)
	var made: String = r[0]
	var n: int = r[1]
	var put := add(made, n)
	changed.emit()
	if put < n:
		return "Made %s, but %d didn't fit." % [ItemInfo.display_name(made), n - put]
	return "Made %s." % ItemInfo.display_name(made)

# ---------- Saving and syncing ----------

func to_dict() -> Dictionary:
	var out_slots := []
	for s in slots:
		out_slots.append(null if s == null else [s["id"], int(s["n"])])
	return {"v": 2, "slots": out_slots, "mag": mag.duplicate(), "keys": key_items.duplicate(), "files": files.duplicate(), "equipped": equipped}

## Accepts this format and the old one (weapons / ammo / items lists). JSON
## brings numbers back as floats, so counts are coerced to ints.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	slots.clear()
	slots.resize(SIZE)
	mag.clear()
	key_items.clear()
	files.clear()
	if d.has("slots"):
		var src: Array = d["slots"]
		for i in mini(src.size(), SIZE):
			var s = src[i]
			if s is Array and s.size() >= 2 and int(s[1]) > 0:
				slots[i] = {"id": str(s[0]), "n": int(s[1])}
	else:
		for w in d.get("weapons", []):
			add(str(w))
		var ammo: Dictionary = d.get("ammo", {})
		for k in ammo:
			if int(ammo[k]) > 0:
				add_ammo(str(k), int(ammo[k]))
		var items: Dictionary = d.get("items", {})
		for k in items:
			var id := str(k)
			if id.begins_with("file:"):
				files.append(id.substr(5))
			elif int(items[k]) > 0:
				add(id, int(items[k]))
	var m: Dictionary = d.get("mag", {})
	for k in m:
		mag[str(k)] = int(m[k])
	for k in d.get("keys", []):
		key_items.append(str(k))
	for f in d.get("files", []):
		files.append(str(f))
	equipped = str(d.get("equipped", equipped))
	changed.emit()
