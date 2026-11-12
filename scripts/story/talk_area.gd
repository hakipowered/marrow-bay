extends Area3D
## Lets a player talk to a story character (Warden Hardass after his scene).
var story: Node

func interact_text(_player: Node) -> String:
	return "Talk to Warden Hardass"

func interact(_player: Node) -> void:
	if story and story.has_method("talk_to_hardass"):
		story.talk_to_hardass()
