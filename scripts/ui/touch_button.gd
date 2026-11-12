class_name TouchButton
extends Button
## A HUD button that any finger can press. Godot turns only the first finger
## on the screen into a mouse click, and a plain Button only listens to the
## mouse, so with the thumb already on the move stick a second finger on FIRE,
## AIM or a pickup prompt did nothing. This reads the touch itself, by finger,
## and sends the usual button_down / button_up / pressed / toggled signals.
## (On a desktop the mouse arrives as touch index 0, so it still works there.)

var _finger := -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0:
			_finger = event.index
			_down()
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_up(Rect2(Vector2.ZERO, size).grow(40.0).has_point(event.position))
		accept_event()
	elif event is InputEventMouseButton or event is InputEventScreenDrag:
		# The first finger's copy of the same press; the touch already counted.
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _finger >= 0:
		_finger = -1
		_up(false)

func _down() -> void:
	if disabled:
		return
	if toggle_mode:
		button_pressed = not button_pressed
	else:
		var down := get_theme_stylebox("pressed")
		add_theme_stylebox_override("normal", down)
		add_theme_stylebox_override("hover", down)
	button_down.emit()

func _up(inside: bool) -> void:
	if not toggle_mode:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
	button_up.emit()
	if inside and not toggle_mode and not disabled:
		pressed.emit()
