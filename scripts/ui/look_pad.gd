class_name LookPad
extends Control
## Right-side swipe area to turn the camera.
signal look(delta: Vector2)
var _touch := -1
var sensitivity := 1.3

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
		elif not event.pressed and event.index == _touch:
			_touch = -1
	elif event is InputEventScreenDrag and event.index == _touch:
		look.emit(event.relative * sensitivity)
