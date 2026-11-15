class_name Pickup
extends Area3D
## Item lying in the world: a model, a faint intermittent glint, and a pickup prompt.
## item string: "ammo:9mm", "weapon:m12", "key:spade_key", "herb_green", ...

@export var item := "ammo:9mm"
@export var amount := 0
@export var pickup_id := ""   # stable id for placed items so saves remember them
## Who it lies there for. Supplies (ammo, herbs, guns, grenades) are each
## survivor's own, as in RE6: each phone shows its own player's copy, and
## taking it leaves the partner's where it is (saved per survivor as
## "taken:<id>:<character>"). Keys and files are "party": one copy, and
## whoever finds it finds it for both. "shared": one copy anyone can take (an
## item a survivor dropped from their bag). "auto" works it out from the item.
@export_enum("auto", "personal", "party", "shared") var share := "auto"

var _glint: MeshInstance3D
var _light: OmniLight3D
var _taken := false

func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.45
	cs.shape = s
	add_child(cs)
	if share == "auto":
		share = "party" if item.split(":")[0] in ["key", "file"] else "personal"
	if pickup_id != "" and (GameState.has_flag("taken:" + pickup_id) or (share == "personal" and GameState.item_taken(pickup_id))):
		queue_free()
		return
	add_to_group("pickups")   # found by distance (see Player._nearest_pickup)
	var model := ItemVisual.build(item)
	add_child(model)
	var col := _color()
	var phase := randf() * 3.0
	_glint = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	_glint.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/item_glow.gdshader")
	mat.set_shader_parameter("glow_color", col)
	mat.set_shader_parameter("phase", phase)
	q.material = mat
	_glint.position.y = 0.12
	add_child(_glint)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.omni_range = 1.4
	_light.light_energy = 0.0
	_light.position.y = 0.25
	add_child(_light)
	var t := create_tween().set_loops()
	t.tween_interval(phase)
	t.tween_property(_light, "light_energy", 0.7, 0.2)
	t.tween_property(_light, "light_energy", 0.0, 0.9)
	t.tween_interval(1.5)

func _process(_d: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _glint:
		_glint.look_at(cam.global_position, Vector3.UP, true)

func _color() -> Color:
	var parts := item.split(":")
	match parts[0]:
		"ammo": return Color(1.0, 0.82, 0.45)
		"weapon": return Color(1.0, 0.95, 0.8)
		"key": return Color(0.55, 0.85, 1.0)
		"file": return Color(0.9, 0.9, 0.75)
	return WeaponDB.ITEMS.get(item, {}).get("glow", Color(1, 1, 1))

## Bag id (see ItemInfo) of this pickup.
func bag_id() -> String:
	var parts := item.split(":")
	match parts[0]:
		"weapon": return parts[1]
		"key", "file", "ammo": return item
	return item

## The pickup string for a bag id: guns and grenades lie as "weapon:<id>".
static func item_string(id: String) -> String:
	return "weapon:" + id if ItemInfo.kind(id) in ["weapon", "throwable"] else id

func display_name() -> String:
	return ItemInfo.display_name(bag_id())

## Why it won't go in: every stack of it is already full and no slot is
## free (a stack of 9 mm holds 100), or the bag is simply full.
func _no_room_line(inv: Inventory) -> String:
	var id := bag_id()
	if item.begins_with("ammo:"):
		id = Inventory.ammo_id(item.substr(5))
	var have := inv.count(id)
	if have > 0 and ItemInfo.stack(id) > 1:
		return "Your %s are full (%d) and every bag slot is taken. Drop or combine something to make room." % [display_name(), have]
	return "No room in your bag for %s. Open the bag to combine or drop something." % display_name()

func interact_text(player: Node) -> String:
	if player and player.get("inventory") and not player.inventory.can_take(item):
		return "Can't carry more " + display_name()
	return "Pick up " + display_name()

func interact(player: Node) -> void:
	if _taken:
		return
	if player.get("inventory") and not player.inventory.can_take(item):
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast(_no_room_line(player.inventory))
		return
	if share == "personal":
		_take_own(player)
	else:
		_rpc_claim.rpc_id(1, player.get_path())

## This phone's survivor takes their own copy: nobody else is asked, and the
## partner's copy on their phone stays put. Whatever doesn't fit stays here.
func _take_own(p: Node) -> void:
	_taken = true
	var left := _give(p, true)
	if left > 0:
		amount = left
		_taken = false
		return
	if pickup_id != "":
		GameState.share_flag("taken:%s:%s" % [pickup_id, p.character])
	Sfx.play_at("pickup_" + item.split(":")[0], global_position, "pickup", -2.0, 5.0)
	queue_free()

@rpc("any_peer", "reliable", "call_local")
func _rpc_claim(player_path: NodePath) -> void:
	if not multiplayer.is_server() or _taken:
		return
	_taken = true
	_rpc_taken.rpc(player_path)

@rpc("authority", "reliable", "call_local")
func _rpc_taken(player_path: NodePath) -> void:
	_taken = true
	if pickup_id != "":
		GameState.set_flag("taken:" + pickup_id)
		# The story can say where to go next (Chapter2Story.item_taken).
		for s in get_tree().get_nodes_in_group("story"):
			if s.has_method("item_taken"):
				s.item_taken(pickup_id)
	var p := get_node_or_null(player_path)
	if share == "party":
		# A key or a file: both survivors have it now, so either can open
		# the door it fits or read it.
		for me in get_tree().get_nodes_in_group("players"):
			if me.is_multiplayer_authority():
				if me == p:
					_give(me)
				else:
					_partner_found(me, p)
	elif p and p.is_multiplayer_authority():
		_give(p)
	Sfx.play_at("pickup_" + item.split(":")[0], global_position, "pickup", -2.0, 5.0)
	queue_free()

## The partner found a key or a file: it goes into this survivor's bag too.
func _partner_found(me: Node, finder: Node) -> void:
	var parts := item.split(":")
	if parts[0] == "key":
		me.inventory.add_key(parts[1])
	elif parts[0] == "file":
		me.inventory.add_file(parts[1])
	else:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		var who: String = finder.character.capitalize() if finder else GameState.partner_character(me.character).capitalize()
		hud.toast("%s found %s. You have it too." % [who, display_name()] if parts[0] == "key"
			else "%s found a file: %s. It's in your bag." % [who, display_name()])

## Puts the item in p's bag and returns how many didn't fit. A shared or
## party item drops what didn't fit at the spot for anyone; a personal one
## (keep_rest) keeps it here for its owner.
func _give(p: Node, keep_rest := false) -> int:
	var parts := item.split(":")
	var n := 1
	var got := 0
	match parts[0]:
		"ammo":
			# A box lying in the level (or dropped by an infected) holds what
			# this difficulty gives; one a survivor put down holds what they had.
			n = amount if amount > 0 else GameState.ammo_amount(WeaponDB.AMMO[parts[1]]["pickup"])
			got = p.inventory.add_ammo(parts[1], n)
		"weapon":
			if ItemInfo.kind(parts[1]) == "throwable":
				n = maxi(amount, 1)
				got = p.inventory.add(parts[1], n)
			else:
				got = 1 if p.inventory.add_weapon(parts[1]) else 0
		"key":
			p.inventory.add_key(parts[1])
			got = 1
		"file":
			p.inventory.add_file(parts[1])
			got = 1
		_:
			n = maxi(amount, 1)
			got = p.inventory.add_item(item, n)
	p._emit_ammo()
	var hud := get_tree().get_first_node_in_group("hud")
	if got < n and not keep_rest:
		# The bag filled up between the prompt and the pickup: leave the rest.
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("request_drop"):
			level.request_drop(item, global_position, n - got)
	if hud:
		var what := display_name() + (" x%d" % got if got > 1 else "")
		if got > 0 and got < n and keep_rest:
			hud.toast("Picked up %s. No room for the other %d." % [what, n - got])
		else:
			hud.toast(("Picked up " + what) if got > 0 else "No room in your bag")
		if parts[0] == "file" and hud.has_method("show_file_hint"):
			hud.show_file_hint(parts[1])
	return n - got
