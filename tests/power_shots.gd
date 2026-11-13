extends SceneTree
## Frames of the vault power route from the player's own camera, HUD on: the
## dead elevator and its note, the breaker before and after, the vault lit,
## the doors open, inside the car, and the ride down.
## xvfb-run -a -s "-screen 0 1400x1000x24" godot --path . --rendering-driver vulkan \
##   --rendering-method mobile --resolution 1400x1000 --script tests/power_shots.gd -- <out_dir>
var out := "/tmp"
var frames := 0
var p: Node
var gs: Node
var cs: Node
var lift: Node
var breaker: Node
var i := 0
var t := 0.0
var ride_t := 0.0
var ride_shots := 0

## [tag, what to do first, where: "lift"/"breaker"/"car", distance, settle seconds]
var shots := [
	["1_lift_dead", "", "lift", 2.6, 1.5],
	["2_lift_note", "", "lift", 0.9, 1.0],
	["3_breaker_off", "", "breaker", 1.3, 1.5],
	["4_breaker_on", "power", "breaker", 1.3, 4.0],
	["5_vault_lit", "", "lift", 4.0, 1.0],
	["6_lift_open", "card", "lift", 2.4, 3.0],
	["7_in_car", "", "car", 0.0, 1.0],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)

func _stand(target: Node3D, dist: float, along := 0.25) -> void:
	var n: Vector3 = target.global_transform.basis.z
	var at: Vector3 = target.global_position + target.global_transform.basis * Vector3(along, 0, 0)
	p.global_position = Vector3(at.x, 0.05, at.z) + n * dist
	p.velocity = Vector3.ZERO
	var face := atan2(n.x, n.z)
	p.body.global_rotation.y = face
	p.yaw = face
	p.pitch = -0.12

func _process(d: float) -> bool:
	frames += 1
	if frames == 3:
		gs = root.get_node("GameState")
		cs = root.get_node("Cutscenes")
		gs.reset_run()
		for beat in ["intro", "gates", "warden", "glass"]:
			gs.set_flag("story_" + beat)
		gs.world_flags["objective"] = "Get the power on: the breaker is in the boiler room, through the vault"
		root.get_node("Net").start_solo("obcera")
		change_scene_to_file(gs.level_path)
		return false
	if frames < 60:
		return false
	if p == null:
		p = get_first_node_in_group("players")
		lift = current_scene.find_child("VaultElevator", true, false)
		breaker = current_scene.find_child("BreakerPanel", true, false)
		for z in get_nodes_in_group("zombies"):
			z.queue_free()
		p.inventory.key_items.append("vault_card")
		p.equip("p9")
		t = -1.0
	if i < shots.size():
		var s: Array = shots[i]
		if t < 0.0:
			match s[1]:
				"power":
					_stand(breaker, 1.0)
					p.interact_ray.force_raycast_update()
					p._update_focus()
					p.interact()
				"card":
					_stand(lift, 1.0, 0.0)
					p.interact_ray.force_raycast_update()
					p._update_focus()
					p.interact()
			t = 0.0
		t += d
		# Re-stand every frame so she doesn't drift while things settle.
		match s[2]:
			"lift": _stand(lift, s[3], 0.0)
			"breaker": _stand(breaker, s[3])
			"car":
				p.global_position = lift.ride_spot(0) + Vector3(0, 0.05, 0)
				var n: Vector3 = lift.global_transform.basis.z
				p.yaw = atan2(n.x, n.z) + PI   # camera behind her, looking out
				p.body.global_rotation.y = p.yaw
				p.pitch = -0.08
		if t > s[4]:
			root.get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
			print("saved ", s[0], "  prompt: \"", p._prompt_text, "\"")
			i += 1
			t = -1.0
			if i == shots.size():
				p.interact_ray.force_raycast_update()
				p._update_focus()
				p.interact()   # Go down
		return false
	# The ride: a frame every couple of seconds of wall time.
	if cs.active:
		ride_t += d
		if ride_t > 0.6:
			ride_t = 0.0
			ride_shots += 1
			root.get_texture().get_image().save_png("%s/8_ride_%02d.png" % [out, ride_shots])
			print("saved ride ", ride_shots)
		return false
	if ride_shots > 0 or frames > 100000:
		quit()
	return false
