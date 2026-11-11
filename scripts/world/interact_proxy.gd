extends Area3D
## Routes interaction from a sub-area (a co-op door handle, a downed partner)
## to its owner. Owners can expose proxy_interact_text/proxy_interact to keep
## those separate from their own interact().
var target: Node

func interact_text(player: Node) -> String:
	if target == player:
		return ""
	if target.has_method("proxy_interact_text"):
		return target.proxy_interact_text(player, get_meta("handle", -1))
	return target.interact_text(player, get_meta("handle", -1))

func interact(player: Node) -> void:
	if target == player:
		return
	if target.has_method("proxy_interact"):
		target.proxy_interact(player, get_meta("handle", -1))
	else:
		target.interact(player, get_meta("handle", -1))
