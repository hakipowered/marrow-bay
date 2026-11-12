extends SceneTree
## Outfits persist: start solo as Obcera in Beach Day, save at the checkpoint,
## change her look, then load the save and check the outfit comes back.
var frames := 0
var stage := 0

func _process(_d: float) -> bool:
	frames += 1
	var gs = root.get_node("GameState")
	var net = root.get_node("Net")
	var saves = root.get_node("SaveSystem")
	match stage:
		0:
			if frames > 2:
				var look: Dictionary = gs.look("obcera")
				look["outfit"] = "beach"
				look["chest"] = 0.9
				gs.customization_by_peer[1] = look
				net.start_solo("obcera")
				change_scene_to_file(gs.level_path)
				stage = 1
				frames = 0
		1:
			if frames == 60:
				var p = get_nodes_in_group("players")[0]
				print("wearing ", p.model.outfit)
				saves.save_game("outfit_test")
				gs.set_look("obcera", gs.default_customization("obcera"))
				print("after reset: ", gs.look("obcera")["outfit"])
				saves.apply_snapshot(saves.read_slot("outfit_test"))
				var back: Dictionary = gs.look("obcera")
				print("after load: ", back["outfit"], " chest ", back["chest"])
				var ok: bool = p.model.outfit == "beach" and back["outfit"] == "beach" and is_equal_approx(float(back["chest"]), 0.9)
				DirAccess.remove_absolute("user://saves/outfit_test.json")
				print("OUTFIT SAVE OK" if ok else "OUTFIT SAVE FAILED")
				quit(0 if ok else 1)
	return false
