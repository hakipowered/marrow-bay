extends "res://scripts/ui/inventory_menu.gd"
## The item box screen, opened at a safe room's box: the box on the left, the
## bag in the middle (the same slots as the bag screen), the selected thing up
## close on the right, with what you can do with it.
##
## Tap a bag item twice (or STORE) to put the whole stack in the box; a gun
## goes in with the rounds loaded in it. Tap a box item twice (or TAKE) to
## take one bag slot's worth out; TAKE ALL takes as much as the bag holds.
## The box is one store behind every box, and both survivors share it: in
## co-op the partner can have it open at the same time, and what they move
## shows up here as it happens.
##
## You keep at least one weapon on you: the box won't take the last one.

const BOX_COLS := 3
const BOX_ROWS := 4

var box: Node            # the ItemBox this was opened at
var _side := "bag"       # where the selection is: "bag" or "box"
var _box_key := -1       # the selected box entry (GameState.item_box key)
var _box_idx := 0        # where it was in the list, for when it's gone
var _box_scroll: ScrollContainer
var _box_grid: GridContainer
var _box_slots: Array[Button] = []
var _box_count: Label
var _box_hint: Label
var _bag_count: Label
var _note_until := 0.0
var _press_scroll := 0

func _ready() -> void:
	super()
	# A heading over the bag, level with the box's.
	var col := _grid.get_parent()
	var head := _column_head("YOUR BAG")
	_bag_count = head.get_child(2)
	col.add_child(head)
	col.move_child(head, 0)
	var store: Node = GameState.item_box
	store.changed.connect(_refresh)
	store.given.connect(_on_given)
	store.refused.connect(func(text: String): _note(text, DANGER))

# ---------- Open / close ----------

## The bag screen's open, for anything that calls it on this screen.
func open(p: Player) -> void:
	open_box(p, null)

func open_box(p: Player, at_box: Node) -> void:
	player = p
	box = at_box
	if player == null:
		return
	if not player.inventory_changed.is_connected(_refresh):
		player.inventory_changed.connect(_refresh)
	_tab = "items"
	_combine_from = -1
	_side = "bag"
	_box_key = -1
	_box_idx = 0
	_sel = _first_filled()
	if _sel < 0 and not GameState.item_box.is_empty():
		_side = "box"
		_box_key = int(GameState.item_box.sorted()[0]["k"])
	_note_until = 0.0
	visible = true
	_coop_note.visible = Net.is_coop()
	if not Net.is_coop():
		get_tree().paused = true
	player.fire_held = false
	Sfx.ui("ui_open", -6.0)
	if is_instance_valid(box):
		box.set_in_use(true)
	GameState.item_box.refresh_from_host()
	_box_scroll.scroll_vertical = 0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	_refresh()

func close() -> void:
	if not visible:
		return
	super()
	if is_instance_valid(box):
		box.set_in_use(false)
	box = null

func _process(delta: float) -> void:
	super(delta)
	if not visible or player == null:
		return
	# Knocked down, or (with keys on a computer) walked off: the box shuts.
	if player.downed or player.dead or (is_instance_valid(box) and player.global_position.distance_to(box.global_position) > 3.5):
		close()

# ---------- Building the layout ----------

func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.add_child(_lbl("ITEM BOX", "head", 66, INK))
	var bar := ColorRect.new()
	bar.color = Color(BLOOD, 0.9)
	bar.custom_minimum_size = Vector2(6, 66)
	h.add_child(bar)
	var sub := _lbl("One store behind every safe room's box.", "serif", 34, DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_coop_note = _lbl("THE WORLD KEEPS MOVING", "ui", 26, Color(DANGER, 0.9))
	_coop_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_coop_note)
	var x := _flat_button("CLOSE", 32, Vector2(200, 86))
	x.pressed.connect(close)
	h.add_child(x)
	return h

## A column's heading: its name in gold, a count on the right.
func _column_head(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_child(_lbl(text, "bold", 30, GOLD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var count := _lbl("", "ui", 28, DIM)
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(count)
	return row

## The box's column, where the bag screen has the heart monitor.
func _build_status() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	var w := BOX_COLS * SLOT + (BOX_COLS - 1) * GAP
	var head := _column_head("IN THE BOX")
	_box_count = head.get_child(2)
	col.add_child(head)
	_box_scroll = ScrollContainer.new()
	# Room for the scroll bar beside the slots.
	_box_scroll.custom_minimum_size = Vector2(w + 22, BOX_ROWS * SLOT + (BOX_ROWS - 1) * GAP)
	_box_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	col.add_child(_box_scroll)
	_box_grid = GridContainer.new()
	_box_grid.columns = BOX_COLS
	_box_grid.add_theme_constant_override("h_separation", int(GAP))
	_box_grid.add_theme_constant_override("v_separation", int(GAP))
	_box_scroll.add_child(_box_grid)
	_box_hint = _lbl("", "ui", 28, DIM)
	_box_hint.custom_minimum_size = Vector2(w + 22, 84)
	_box_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_box_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_box_hint)
	return col

## Enough box slots for everything in it, in whole rows, never fewer than
## the four rows that show.
func _ensure_box_slots(n: int) -> void:
	var want := maxi(BOX_COLS * BOX_ROWS, int(ceil(n / float(BOX_COLS))) * BOX_COLS)
	while _box_slots.size() < want:
		var i := _box_slots.size()
		var b := _make_slot(i, func(): _on_box_slot(i))
		# Drags pass through to the scroll container, so a long box scrolls
		# under a finger; a tap that scrolled doesn't count as a tap.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_down.connect(func(): _press_scroll = _box_scroll.scroll_vertical)
		_box_grid.add_child(b)
		_box_slots.append(b)
	for i in _box_slots.size():
		_box_slots[i].visible = i < want

# ---------- Contents ----------

func _selected_id() -> String:
	if _side == "box":
		return str(GameState.item_box.entry(_box_key).get("id", ""))
	return super()

func _refresh() -> void:
	if player == null or not visible:
		return
	var list: Array = GameState.item_box.sorted()
	# The selected box entry went (taken here or by the partner): select
	# whatever now sits where it was.
	if _side == "box" and _box_key >= 0 and GameState.item_box.entry(_box_key).is_empty():
		_box_key = int(list[mini(_box_idx, list.size() - 1)]["k"]) if not list.is_empty() else -1
	if _side == "box":
		_sel = -1
	if _side == "bag" and (_sel < 0 or player.inventory.slots[_sel] == null):
		_sel = _first_filled()
	_refresh_grid()
	_refresh_box(list)
	_refresh_details()
	var inv := player.inventory
	_bag_count.text = "%d of %d free" % [inv.free_slots(), Inventory.SIZE]
	_hint.remove_theme_color_override("font_color")
	_hint.add_theme_color_override("font_color", DIM)
	_hint.text = "Tap a bag item twice to put it in the box."
	if Time.get_ticks_msec() / 1000.0 > _note_until:
		_box_hint.remove_theme_color_override("font_color")
		_box_hint.add_theme_color_override("font_color", DIM)
		_box_hint.text = "Tap a box item twice to take it." if not list.is_empty() else "The box is empty."

func _refresh_box(list: Array) -> void:
	_ensure_box_slots(list.size())
	_box_count.text = "1 item" if list.size() == 1 else "%d items" % list.size()
	for i in _box_slots.size():
		var b := _box_slots[i]
		if not b.visible:
			continue
		var e: Dictionary = list[i] if i < list.size() else {}
		var id: String = str(e.get("id", ""))
		var icon: TextureRect = b.get_node("Icon")
		var count: Label = b.get_node("Count")
		var tag: Label = b.get_node("Tag")
		var shade: ColorRect = b.get_node("Shade")
		icon.texture = ItemInfo.icon(id) if id != "" else null
		tag.visible = false
		shade.visible = false
		count.text = ""
		count.remove_theme_color_override("font_color")
		if id != "":
			var k := ItemInfo.kind(id)
			var n := int(e["n"])
			if k == "weapon" and WeaponDB.WEAPONS[id].has("mag"):
				count.text = str(int(e["mag"]))
				count.add_theme_color_override("font_color", GOLD if int(e["mag"]) > 0 else DANGER)
			elif n > 1 or k == "ammo" or k == "throwable":
				count.text = str(n)
		var selected: bool = _side == "box" and id != "" and int(e["k"]) == _box_key
		if selected:
			_box_idx = i
		var border := Color(GOLD, 0.95) if selected else Color(GOLD, 0.16)
		var bg := Color(0.06, 0.055, 0.05, 0.95) if id != "" else Color(0.03, 0.03, 0.033, 0.72)
		var sb := _box(bg, border, 8, 4 if selected else 2)
		if selected:
			sb.shadow_color = Color(GOLD, 0.35)
			sb.shadow_size = 12
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _refresh_details() -> void:
	super()
	if _selected_id() != "":
		return
	if _side == "box":
		_name_lbl.text = "Item box"
		_desc.text = "Empty. Tap a bag item twice to put it in." if GameState.item_box.is_empty() else "Tap something in the box to see it here."
	else:
		_name_lbl.text = "Empty slot"
		_desc.text = "Room for a weapon or a stack of supplies."

func _loaded_line(id: String, k: String) -> String:
	if _side != "box":
		return super(id, k)
	var e: Dictionary = GameState.item_box.entry(_box_key)
	if e.is_empty():
		return ""
	if k == "weapon" and WeaponDB.WEAPONS[id].has("mag"):
		var w: Dictionary = WeaponDB.WEAPONS[id]
		# Her own rounds for it, as in the bag view: is it worth taking?
		return "LOADED  %d / %d      CARRIED  %d" % [int(e["mag"]), w["mag"], player.inventory.ammo_count(w["ammo"])]
	if k != "weapon":
		return "IN THE BOX  %d" % int(e["n"])
	return ""

func _add_actions(id: String, k: String) -> void:
	var acts: Array = []
	if _side == "box":
		var e: Dictionary = GameState.item_box.entry(_box_key)
		var room := _room_for(e)
		acts.append(["TAKE", _take.bind(false), room > 0])
		if k != "weapon" and int(e.get("n", 0)) > ItemInfo.stack(id):
			acts.append(["TAKE ALL", _take.bind(true), room > 0])
		acts.append(["EXAMINE", _open_examine.bind(id), true])
	else:
		acts.append(["STORE", _store, true])
		if k in ["weapon", "throwable"]:
			acts.append(["EQUIP" if player.inventory.equipped != id else "IN HAND", _equip.bind(id), player.inventory.equipped != id])
		acts.append(["EXAMINE", _open_examine.bind(id), true])
	for a in acts:
		var b := _flat_button(a[0], 30, Vector2(234, 96))
		b.add_theme_color_override("font_color", INK)
		b.disabled = not a[2]
		b.pressed.connect(a[1])
		_actions.add_child(b)

## How many of a box entry the bag can take now (a gun: one, and only when
## she isn't carrying one already).
func _room_for(e: Dictionary) -> int:
	if e.is_empty():
		return 0
	var inv := player.inventory
	var id: String = e["id"]
	if ItemInfo.kind(id) == "weapon":
		return 1 if inv.count(id) == 0 and inv.free_slots() > 0 else 0
	return mini(inv.room_for(id), int(e["n"]))

func _why_not(e: Dictionary) -> String:
	var id: String = e.get("id", "")
	if ItemInfo.kind(id) == "weapon" and player.inventory.count(id) > 0:
		return "You're already carrying a %s." % ItemInfo.display_name(id)
	return "Your bag is full."

# ---------- Actions ----------

## A bag slot tapped: select it; tapped again, it goes in the box.
func _on_slot(i: int) -> void:
	var again := _side == "bag" and i == _sel
	_side = "bag"
	_box_key = -1
	_sel = i
	if again and player.inventory.slots[i] != null:
		_store()
		return
	Sfx.ui("ui_select", -10.0)
	_refresh()

## A box slot tapped: select it; tapped again, take it.
func _on_box_slot(i: int) -> void:
	if absi(_box_scroll.scroll_vertical - _press_scroll) > 12:
		return
	var list: Array = GameState.item_box.sorted()
	var key: int = int(list[i]["k"]) if i < list.size() else -1
	var again := _side == "box" and key >= 0 and key == _box_key
	_side = "box"
	_sel = -1
	_box_key = key
	_box_idx = i
	if again:
		_take(false)
		return
	Sfx.ui("ui_select", -10.0)
	_refresh()

## The selected bag stack goes in the box, a gun with its loaded rounds.
func _store() -> void:
	var inv := player.inventory
	var s = inv.slots[_sel] if _sel >= 0 else null
	if s == null:
		return
	var id: String = s["id"]
	var n: int = int(s["n"])
	var k := ItemInfo.kind(id)
	if k in ["weapon", "throwable"]:
		var others := inv.weapon_list().filter(func(w): return w != id)
		if others.is_empty():
			_note("Keep one weapon on you. The box won't take your last.", DANGER)
			Sfx.ui("ui_select", -10.0)
			_refresh()
			return
	var rounds: int = int(inv.mag.get(id, 0)) if k == "weapon" else 0
	inv.take_from_slot(_sel, n)
	_after_removal(id)
	player.set("_inv_sync_t", 0.0)
	GameState.item_box.store(id, n, rounds)
	_note("Put %s in the box." % _named(id, n))
	Sfx.ui("ui_combine", -6.0)
	_refresh()

## One bag slot's worth of the selected box entry (all = as much as fits).
## It lands in the bag when the host says yes (_on_given).
func _take(all: bool) -> void:
	var e: Dictionary = GameState.item_box.entry(_box_key)
	if e.is_empty():
		return
	var room := _room_for(e)
	if room <= 0:
		_note(_why_not(e), DANGER)
		Sfx.ui("ui_select", -10.0)
		_refresh()
		return
	var id: String = e["id"]
	var n := 1 if ItemInfo.kind(id) == "weapon" else (room if all else mini(room, ItemInfo.stack(id)))
	GameState.item_box.take(int(e["k"]), n)

func _on_given(id: String, got: int) -> void:
	if not visible:
		return
	if got > 0:
		_note("Took %s." % _named(id, got))
		Sfx.ui("pickup_ammo" if ItemInfo.kind(id) == "ammo" else "pickup", -8.0)
	_refresh()

func _named(id: String, n: int) -> String:
	var name := ItemInfo.display_name(id)
	if ItemInfo.kind(id) == "weapon":
		return "the " + name
	return "%s x%d" % [name, n] if n > 1 else name

## A line under the box for a moment (what just moved, or why it didn't).
func _note(text: String, color := INK) -> void:
	_note_until = Time.get_ticks_msec() / 1000.0 + 2.6
	_box_hint.text = text
	_box_hint.remove_theme_color_override("font_color")
	_box_hint.add_theme_color_override("font_color", color)
	_box_hint.modulate = Color(1.4, 1.3, 1.1)
	create_tween().tween_property(_box_hint, "modulate", Color.WHITE, 0.6)
