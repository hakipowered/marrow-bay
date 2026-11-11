extends SceneTree
## Checks explosive friendly fire and thrown grenades on a solo session.
var f := 0
var p: Node3D
var hp0 := 0.0

func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		root.get_node("Net").start_solo("zegan")
		change_scene_to_file(root.get_node("GameState").level_path)
	if f == 40:
		p = get_first_node_in_group("players")
		hp0 = p.hp
		root.get_node("Combat").explode(p.global_position + Vector3(1, 0, 0), 220.0, 5.0, "frag", 99)
		print("explode: hp ", hp0, " -> ", p.hp)
		if p.hp >= hp0:
			print("FF FAIL: no damage")
			quit(1)
		p.hp = p.max_hp
		root.get_node("Cheats").flags["no_explosive_ff"] = true
		root.get_node("Combat").explode(p.global_position + Vector3(1, 0, 0), 220.0, 5.0, "frag", 99)
		if p.hp < p.max_hp:
			print("FF FAIL: cheat ignored")
			quit(1)
		root.get_node("Cheats").flags["no_explosive_ff"] = false
		# Throw a real frag at our own feet.
		root.get_node("Combat")._rpc_projectile("frag", p.global_position + Vector3(0, 1.5, 0), Vector3(0.1, -1.0, 0).normalized(), 1)
	var live := false
	if f > 41:
		for n in current_scene.get_children():
			if n.get("weapon_id") == "frag":
				live = true
	if f > 45 and not live and f < 100000:
		print("frag thrown: hp ", p.max_hp, " -> ", p.hp)
		if p.hp >= p.max_hp:
			print("FF FAIL: frag did not detonate near player")
			quit(1)
		else:
			print("FF OK")
			quit(0)
		f = 100000
	return false
