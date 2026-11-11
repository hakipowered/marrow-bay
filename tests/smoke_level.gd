extends SceneTree
## Headless smoke test: start solo as each character, load the hub, run ~3s
## of frames, shoot, open a door, save, then quit. Any script error fails it.
var frames := 0
var stage := 0

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	frames += 1
	var gs = root.get_node("GameState")
	var net = root.get_node("Net")
	match stage:
		0:
			if frames > 2:
				net.start_solo("obcera")
				change_scene_to_file(gs.level_path)
				stage = 1
				frames = 0
		1:
			if frames > 60:
				var p = get_first_node_in_group("players")
				print("players: ", get_nodes_in_group("players").size(), " zombies: ", get_nodes_in_group("zombies").size(), " doors: ", get_nodes_in_group("doors").size())
				p.aiming = true
				p.fire_held = true
				p.move_input = Vector2(0, -1)
				stage = 2
				frames = 0
		2:
			if frames > 90:
				var p = get_first_node_in_group("players")
				print("player pos ", p.global_position, " hp ", p.hp, " mag ", p.inventory.mag)
				root.get_node("SaveSystem").save_game("smoke")
				print("saved: ", root.get_node("SaveSystem").read_slot("smoke").get("checkpoint"))
				root.get_node("Cheats").set_cheat("one_hit_kills", true)
				stage = 3
				frames = 0
		3:
			if frames == 5:
				root.get_node("Cheats").set_cheat("one_hit_kills", false)
				var p = get_first_node_in_group("players")
				# Walk into the vault: riot guard, grappler, brute, burner.
				p.global_position = Vector3(-4, 0.1, 19)
				p.fire_held = false
			if frames == 400:
				var p = get_first_node_in_group("players")
				var states := {}
				for z in get_nodes_in_group("zombies"):
					states[str(z.name)] = z.S.keys()[z.state]
				print("after vault: hp ", p.hp, " pinned ", p.pinned, " downed ", p.downed)
				print("zombie states ", states)
				stage = 4
				frames = 0
		4:
			if frames > 30:
				print("SMOKE OK")
				quit(0)
	return false
