class_name TouchStick
extends Control
## Floating virtual joystick: appears where the thumb lands in its zone.
signal moved(v: Vector2)

var _touch := -1
var _origin := Vector2.ZERO
var value := Vector2.ZERO
var radius := 140.0
var _knob := Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_origin = event.position
			_knob = _origin
		elif not event.pressed and event.index == _touch:
			_touch = -1
			value = Vector2.ZERO
			moved.emit(value)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch:
		var d: Vector2 = event.position - _origin
		value = d.limit_length(radius) / radius
		_knob = _origin + d.limit_length(radius)
		moved.emit(value)
		queue_redraw()

func _draw() -> void:
	if _touch == -1:
		draw_circle(Vector2(size.x * 0.35, size.y * 0.6), radius, Color(1, 1, 1, 0.05))
		return
	draw_circle(_origin, radius, Color(1, 1, 1, 0.08))
	draw_arc(_origin, radius, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	draw_circle(_knob, radius * 0.38, Color(1, 1, 1, 0.35))
