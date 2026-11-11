extends Area3D
## Routes interaction from a sub-area (like one handle of a co-op door) to its owner.
var target: Node

func interact_text(player: Node) -> String:
	return target.interact_text(player, get_meta("handle", -1))

func interact(player: Node) -> void:
	target.interact(player, get_meta("handle", -1))
