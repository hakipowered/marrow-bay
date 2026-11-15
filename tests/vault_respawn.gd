extends SceneTree
## Records Vault: the brute, the grappler and the riot cop, a death, and
## Continue. In 0.13 Bulmaim met only one big guy, died to him, and after
## Continue found him alive and the other two already gone. The three
## started in a back aisle the boxes and the drum sealed off from the
## infected's navmesh (only the brute's straight-line charge got out), and a
## checkpoint taken mid-fight kept whatever had died by then. Checks that:
##  1. Stepping into the vault, all three come out after her, and the fight
##     music plays.
##  2. Two of them die (the drum), she runs back through the Great Hall's
##     checkpoint with the brute on her: no checkpoint is taken mid-fight.
##  3. Killed by him, Continue puts all three back alive in the vault (and
##     the drum back), and the fight music plays again when they come.
## Prints VAULT RESPAWN OK, or VAULT RESPAWN FAIL with the reasons.
const VAULT := ["Z_vault_1", "Z_vault_grab", "Z_vault_2"]
const INSIDE := Vector3(-6, 0.1, 17.6)
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var fails := []
var notes := []
var first_level: Node = null
var _music_seen := false
var _came := {}
var _life := 1

func _process(d: float) -> bool:
	frames += 1
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and stage < 30 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	if stage >= 3 and stage < 30:
		_watch()
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				_begin_life()
				stage = 2
				t = 0.0
		2:
			# In the Great Hall's checkpoint: that's where Continue brings her.
			t += d
			if t > 1.0:
				var gs = root.get_node("GameState")
				if gs.shared_checkpoint != "hall":
					fails.append("hall checkpoint not reached (%s)" % gs.shared_checkpoint)
				_enter_vault()
				stage = 3
				t = 0.0
		3:
			# Just inside the vault door: they should all come for her.
			t += d
			p.hp = 100.0   # (not dying yet)
			if (_came.size() == 3 and _music_seen) or t > 20.0:
				notes.append("life 1: came for her %s after %.1f s, fight music %s" % [str(_came.keys()), t, str(_music_seen)])
				if _came.size() < 3:
					fails.append("life 1: only %s came for her" % str(_came.keys()))
				if not _music_seen:
					fails.append("life 1: no fight music with all three on her")
				# The drum goes up: the riot cop and the grappler die, the
				# brute shrugs it off.
				for n in ["Z_vault_1", "Z_vault_grab"]:
					var z = _z(n)
					if z and z.state != z.S.DEAD:
						z.take_hit(400.0, "fuel_drum", "torso", Vector3(0, 0, -1))
				root.get_node("GameState").set_flag("broken:vault_drum")
				# She runs back into the hall, through its checkpoint, the
				# brute after her.
				p.global_position = Vector3(0, 0.1, 4.0)
				var b = _z("Z_vault_2")
				if b:
					b.global_position = Vector3(-2.5, 0.0, 9.0)
					b.state = b.S.CHASE
				stage = 4
				t = 0.0
		4:
			t += d
			p.hp = 100.0
			if t > 3.0:
				var snap: Dictionary = root.get_node("SaveSystem").checkpoint_snapshot
				var gone := []
				for n in VAULT:
					if snap.get("flags", {}).has("dead:" + n):
						gone.append(n)
				notes.append("ran through the hall checkpoint with the brute on her: the checkpoint remembers dead %s" % str(gone))
				if not gone.is_empty():
					fails.append("checkpoint taken mid-fight: %s stay dead after Continue" % str(gone))
				stage = 5
				t = 0.0
		5:
			t += d
			if not p.dead:
				p.hp = 1.0
				p.apply_damage(50.0, _z("Z_vault_2"))
			if t > 7.0:
				first_level = get_first_node_in_group("level")
				first_level.vote_continue()
				stage = 6
				t = 0.0
		6:
			t += d
			var lvl = get_first_node_in_group("level")
			if lvl != null and lvl != first_level and t > 1.0 and get_first_node_in_group("players") != null:
				_life = 2
				_check_after_continue()
				_begin_life()
				stage = 7
				t = 0.0
			elif t > 10.0:
				fails.append("Continue did not reload")
				stage = 30
		7:
			t += d
			if t > 1.0:
				_enter_vault()
				stage = 8
				t = 0.0
		8:
			t += d
			p.hp = 100.0
			if (_came.size() == 3 and _music_seen) or t > 20.0:
				notes.append("life 2: came for her %s after %.1f s, fight music %s" % [str(_came.keys()), t, str(_music_seen)])
				if _came.size() < 3:
					fails.append("life 2: only %s came for her" % str(_came.keys()))
				if not _music_seen:
					fails.append("life 2: no fight music after Continue")
				stage = 30
		30:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("VAULT RESPAWN OK")
			else:
				print("VAULT RESPAWN FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

func _z(n: String) -> Node:
	var lvl = get_first_node_in_group("level")
	return lvl.get_node_or_null(n) if lvl else null

func _begin_life() -> void:
	p = get_first_node_in_group("players")
	p.global_position = Vector3(0, 0.1, 4)
	p.hp = 100.0
	_music_seen = false
	_came = {}
	# Only the vault's three: the rest of the first area stays out of it.
	for z in get_nodes_in_group("zombies"):
		if not str(z.name) in VAULT:
			z.queue_free()
	var alive := []
	for n in VAULT:
		var z = _z(n)
		if z and z.state != z.S.DEAD:
			alive.append(n)
	notes.append("life %d starts with %s in the vault" % [_life, str(alive)])

func _enter_vault() -> void:
	var door = get_first_node_in_group("level").get_node("Door_vault_door")
	if not door.is_open:
		door._rpc_set_open(true, Vector3(0, 0, 1))
	p.global_position = INSIDE
	p.yaw = PI   # looking into the vault

func _watch() -> void:
	if p == null or not is_instance_valid(p):
		return
	if root.get_node("Music").current_track() == "fight":
		_music_seen = true
	for n in VAULT:
		var z = _z(n)
		if z == null or z.state == z.S.DEAD:
			continue
		if z.state in [z.S.CHASE, z.S.ATTACK, z.S.CHARGE, z.S.PINNING, z.S.STAGGER] and z.global_position.distance_to(p.global_position) < 3.0:
			_came[n] = true

func _check_after_continue() -> void:
	for n in VAULT:
		var z = _z(n)
		if z == null:
			fails.append("after Continue %s is gone (flag dead: %s)" % [n, str(root.get_node("GameState").has_flag("dead:" + n))])
		elif z.state == z.S.DEAD:
			fails.append("after Continue %s lies dead" % n)
	if root.get_node("GameState").has_flag("broken:vault_drum"):
		fails.append("after Continue the vault drum is still blown")
