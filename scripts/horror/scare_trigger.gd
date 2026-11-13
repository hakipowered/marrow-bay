class_name ScareTrigger
extends Area3D
## One-shot scripted scare, fired by the host for both players when anyone enters.
## kinds:
##   lights_out   - lights in `room` die for `duration` s (flashlights only), then sputter back
##   stinger      - a sharp musical hit + screen fear spike
##   body_drop    - the ceiling caves in and an infected drops through the hole
##                  (`target`: just above the ceiling hole), lands, gets up
##   shutter_burst - infected spawned at `spots` behind the RollShutter named
##                  `room` pound on it, force it up and come out
##   window_break - glass explodes at `target` and zombies climb in (put
##                  `target` outside the window, out of the players' view)
##   door_bang    - something pounds on the door at `target` (no way in... yet)
##   whisper      - a voice from nowhere, subtitle `text`
##   wake_dead    - corpses tagged `group` get up behind the players

@export var scare_id := ""
@export var kind := "stinger"
@export var room := ""
@export var target := Vector3.ZERO
@export var duration := 6.0
@export var text := ""
@export var group := ""
@export var spawn_count := 0
@export var spots: Array = []
var _fired := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	if GameState.has_flag("scare:" + scare_id):
		_fired = true
	body_entered.connect(func(b): if b is Player and multiplayer.is_server() and not _fired: _fire.rpc())

@rpc("authority", "reliable", "call_local")
func _fire() -> void:
	_fired = true
	GameState.set_flag("scare:" + scare_id)
	var director := get_tree().get_first_node_in_group("horror")
	if director:
		director.run_scare(self)
