extends SceneTree
## Headless checks for shootable drums, cans, crates, windows and lamps:
##  1. One pistol round into the courtyard drum blows it within half a second:
##     an infected beside it dies, the survivor 9 m away is unhurt, a wreck
##     and a burning pool are left, and the save flag is set.
##  2. Drums chain: setting off one boiler-room drum takes the other drum and
##     the fuel can with it.
##  3. Fire cooks a drum off: not at once, but within a few seconds.
##  4. A window pane shatters from one round and the next one flies through.
##  5. A street lamp bursts and its light goes dark.
##  6. A crate takes two pistol rounds (and a knife takes two slashes on the
##     rain barrel); a steel drum shrugs off the knife.
##  7. A Thumper grenade landing by the vault drum sets it off.
##  8. After a retry, the blown drum loads as a wreck and the others intact.
## Prints BREAKABLES OK, or BREAKABLES FAIL with the reasons.
## godot --headless --path . --script tests/breakables.gd
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var fails := []
var z: Node = null
var hp0 := 0.0

func _initialize() -> void:
	pass

func _b(id: String) -> Node:
	return root.get_node("/root/Combat").get_tree().current_scene.find_child("Breakable_" + id, true, false)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("  FAIL ", what)
	else:
		print("  ok   ", what)

## Fire the pistol from the camera at a point, the way the player does.
func _shoot_at(target: Vector3, weapon := "p9") -> void:
	var cam: Camera3D = p.camera
	var from := cam.global_position
	var dir := (target - from).normalized()
	root.get_node("Combat").fire(p, weapon, from, [dir], p._muzzle_pos())

## Stand her `back` metres from a point, facing it, with the camera on it.
func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	var d := target - at
	p.yaw = atan2(-d.x, -d.z)
	p.body.rotation.y = p.yaw
	p.pitch = 0.0

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	t += d
	match stage:
		0:
			if frames > 2:
				root.get_node("GameState").reset_run()
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				t = 0.0
		1:
			if t > 1.0:
				p = get_first_node_in_group("players")
				for zz in get_nodes_in_group("zombies"):
					if z == null and zz.variant == "shambler":
						z = zz
						continue
					zz.queue_free()
				p.equip("p9")
				_check(get_nodes_in_group("breakables").size() > 20, "breakables placed (%d)" % get_nodes_in_group("breakables").size())
				# 1: courtyard drum, infected beside it, her 9 m off.
				var drum := _b("court_drum_gate")
				var c: Vector3 = drum.global_transform * drum.center
				z.global_position = c + Vector3(1.2, -c.y, 0.6)
				z.set("start_asleep", false)
				_stand(c + Vector3(0.5, -c.y, 9.0), c)
				hp0 = p.hp
				stage = 2
				t = 0.0
		2:
			if t > 0.4 and t - d <= 0.4:
				var drum := _b("court_drum_gate")
				_shoot_at(drum.global_transform * drum.center)
			if t > 1.0:
				var drum := _b("court_drum_gate")
				_check(drum.broken, "one pistol round blows the drum")
				_check(root.get_node("GameState").has_flag("broken:court_drum_gate"), "blown drum is saved")
				_check(z.state == z.get_script().get_script_constant_map()["S"]["DEAD"], "infected beside the drum dies (hp %.0f)" % z.hp)
				_check(is_equal_approx(p.hp, hp0), "survivor 9 m away unhurt (%.0f -> %.0f)" % [hp0, p.hp])
				_check(drum.model == null and drum.get_child_count() > 1, "wreck left standing")
				var pools := 0
				for h in current_scene.get_children():
					if h is Area3D and h.get("kind") == "fire":
						pools += 1
				_check(pools >= 1, "burning pool left")
				# 2: chain in the boiler room.
				_b("boiler_drum_1").host_damage(30.0, "bullet", _b("boiler_drum_1").global_position, Vector3.FORWARD)
				stage = 3
				t = 0.0
		3:
			if t > 1.6:
				_check(_b("boiler_drum_1").broken and _b("boiler_drum_2").broken, "drums chain")
				_check(_b("boiler_jerrycan").broken, "fuel can goes up with them")
				# 3: fire cooks a drum off.
				_b("court_drum_east").host_damage(0.0, "fire", _b("court_drum_east").global_position, Vector3.UP)
				stage = 4
				t = 0.0
		4:
			if t > 1.0 and t - d <= 1.0:
				_check(not _b("court_drum_east").broken, "fire doesn't blow it at once")
			if t > 3.2:
				_check(_b("court_drum_east").broken, "fire cooks the drum off")
				# 4: a hall window.
				var g: Node = null
				for b in get_nodes_in_group("breakables"):
					if b.kind == "glass" and b.breakable_id.begins_with("glass_GreatHall_n") and b.global_position.y < 4.0:
						g = b
						break
				_check(g != null, "great hall window is breakable")
				if g:
					set_meta("glass", g)
					_stand(Vector3(g.global_position.x, 0.05, g.global_position.z + 5.0), g.global_position)
				stage = 5
				t = 0.0
		5:
			var g: Node = get_meta("glass", null)
			if g and t > 0.3 and t - d <= 0.3:
				_shoot_at(g.global_position)
			if g and t > 0.6 and t - d <= 0.6:
				_check(g.broken, "one round shatters the pane")
				_check(g.glass.material_override is ShaderMaterial, "pane shows broken glass")
				var cam: Camera3D = p.camera
				var through: bool = g.shot(g.global_position, Vector3.FORWARD, (g.global_position - cam.global_position).normalized(), 26.0)
				_check(through, "next round flies through the empty frame")
			if t > 0.9:
				# 5: a street lamp.
				var lamp := _b("street_lamp_23")
				_check(lamp != null, "street lamp is shootable")
				if lamp:
					_stand(lamp.global_position + Vector3(0, -lamp.global_position.y + 0.05, -6.0), lamp.global_position)
				stage = 6
				t = 0.0
		6:
			var lamp := _b("street_lamp_23")
			if lamp and t > 0.3 and t - d <= 0.3:
				_shoot_at(lamp.global_position)
			if t > 1.0:
				if lamp:
					_check(lamp.broken, "lamp bursts")
					_check(not lamp.lights[0].visible, "its light goes dark")
				# 6: crate, rain barrel, knife on a drum.
				var crate := _b("hall_crate")
				var c: Vector3 = crate.global_transform * crate.center
				_stand(c + Vector3(0, -c.y + 0.05, 4.0), c)
				set_meta("pickups0", get_nodes_in_group("pickups").size())
				stage = 7
				t = 0.0
		7:
			var crate := _b("hall_crate")
			var c: Vector3 = crate.global_transform * crate.center
			if t > 0.3 and t - d <= 0.3:
				_shoot_at(c)
			if t > 0.5 and t - d <= 0.5:
				_check(not crate.broken, "one round doesn't smash a crate")
				_shoot_at(c)
			if t > 0.9 and t - d <= 0.9:
				_check(crate.broken, "two rounds smash the crate")
				var bar := _b("court_barrel")
				root.get_node("Combat").hurt_breakable(bar, 30.0, "blade", bar.global_position, Vector3.FORWARD)
				_check(not bar.broken, "one slash doesn't break the barrel")
				root.get_node("Combat").hurt_breakable(bar, 30.0, "blade", bar.global_position, Vector3.FORWARD)
				_check(bar.broken, "two slashes break the rain barrel")
				var vd := _b("vault_drum")
				root.get_node("Combat").hurt_breakable(vd, 30.0, "blade", vd.global_position, Vector3.FORWARD)
			if t > 1.4:
				_check(not _b("vault_drum").broken, "a knife only rings off a drum")
				# 7: a Thumper grenade by the vault drum.
				var vd := _b("vault_drum")
				var at: Vector3 = vd.global_position + Vector3(-1.2, 0.1, 0.3)
				root.get_node("Combat").explode(at, 180.0, 4.5, "gl", 1)
				stage = 8
				t = 0.0
		8:
			if t > 0.8:
				_check(_b("vault_drum").broken, "grenade blast sets off the vault drum")
				_check(_b("vault_propane").broken == (_b("vault_propane").global_position.distance_to(_b("vault_drum").global_position) < 5.3), "vault gas bottle goes only if in reach")
				# 8: retry from the checkpoint keeps what's broken.
				root.get_node("GameState").set_flag("broken:street_drum_diner", false)
				reload_current_scene()
				stage = 9
				t = 0.0
		9:
			if t > 1.0:
				var drum := _b("court_drum_gate")
				_check(drum != null and drum.broken and drum.model == null, "blown drum loads as a wreck")
				_check(drum != null and drum.body != null, "wreck still blocks the way")
				var diner := _b("street_drum_diner")
				_check(diner != null and not diner.broken and diner.model != null, "untouched drum loads whole")
				var bar := _b("court_barrel")
				_check(bar != null and bar.broken and bar.body == null, "smashed barrel stays gone")
				print("BREAKABLES OK" if fails.is_empty() else "BREAKABLES FAIL: " + ", ".join(fails))
				quit(0 if fails.is_empty() else 1)
	return false
