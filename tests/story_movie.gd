extends SceneTree
## Films one in-engine story scene as it really plays (solo, Zegan), with
## Godot's Movie Maker, so every shot, gesture and line can be checked at its
## real timing with the letterbox on:
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 960x720 \
##       --write-movie /tmp/warden.avi --fixed-fps 10 \
##       --script tests/story_movie.gd -- warden [glass_seen]
## (Vulkan, e.g. Mesa lavapipe: the Compatibility renderer has no screen
## texture, so the frosted pane renders black there. 960x720 is about the
## shape of the Fold's inner screen.) "glass_seen" plays the warden scene as
## if they had already seen the thing behind the reading room glass.
## "c2_intercom" is chapter 2's tannoy scene: the Undercroft with the
## generator running, which starts it as soon as everyone is ready.
## The cutscene clock runs on game time, so the film matches the phone even
## though software rendering is far slower than real time.

const ENTER := {
	"warden": Vector3(13.4, 0.1, 2.6),
	"glass": Vector3(-15.8, 0.1, 6.5),
	"c2_intercom": Vector3(44.0, 0.1, 2.0),
}
## Chapter 2 up to the lights coming on (the tannoy scene comes next).
const C2_POWER := ["story_c2_arrival", "c2_arrival", "story_c2_hall", "story_c2_hunt", "c2_hunt",
	"c2_hunt_over", "c2_clock_open", "taken:c2_fuse", "taken:c2_diesel", "taken:c2_crank",
	"c2_fuel_in", "c2_fuse_in", "c2_crank_in", "power:undercroft"]

var scene_id := "warden"
var seen_glass := false
var cs: Node
var gs: Node
var step := 0
var t := 0.0
var _until := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		scene_id = a[0]
	seen_glass = "glass_seen" in a

func _process(delta: float) -> bool:
	t += delta
	if t > 600.0:
		print("TIMEOUT")
		quit(1)
	if cs == null and root.has_node("Cutscenes"):
		cs = root.get_node("Cutscenes")
		gs = root.get_node("GameState")
	match step:
		0:
			if t > 0.2:
				gs.reset_run()
				var flags := ["story_intro", "story_gates"]
				if scene_id == "glass":
					flags.append("story_warden")
				elif seen_glass:
					flags.append("story_glass")
				if scene_id.begins_with("c2_"):
					flags = C2_POWER.duplicate()
					gs.level_path = "res://scenes/levels/undercroft.tscn"
					gs.shared_checkpoint = "ch2_hall"
				for f in flags:
					gs.set_flag(f)
				root.get_node("Net").start_solo("zegan")
				change_scene_to_file(gs.level_path)
				step = 1
				_until = t + 2.5
		1:
			if t > _until:
				for z in get_nodes_in_group("zombies"):
					z.set_physics_process(false)
					z.state = 0
				var p = get_first_node_in_group("players")
				p.global_position = ENTER[scene_id]
				step = 2
				_until = t + 5.0
				print("entering ", scene_id, " at ", snappedf(t, 0.1))
		2:
			if cs.active:
				print("scene ", cs.current, " started at ", snappedf(t, 0.1))
				step = 3
			elif t > _until:
				print("scene did not start")
				quit(1)
		3:
			if not cs.active:
				print("scene ended at ", snappedf(t, 0.1))
				step = 4
				_until = t + 1.0
		4:
			if t > _until:
				quit(0)
	return false
