@tool
extends Control
class_name RubiconVirtualJoystick

## Generic single-axis-friendly on-screen joystick: a fixed base circle at
## [member anchor_position] (relative to this control's rect) with a knob
## that follows the active touch/drag, clamped to [member base_radius] and
## snapping back to center on release. Emits a normalized Vector2 in
## [-1, 1] on both axes via [signal moved]; callers that only care about
## one axis (e.g. shop look) just read .x.

signal moved(value: Vector2)

@export var base_radius: float = 90.0:
	set(value):
		base_radius = value
		queue_redraw()
@export var knob_radius: float = 42.0:
	set(value):
		knob_radius = value
		queue_redraw()
@export var dead_zone: float = 0.08
@export var anchor_position: Vector2 = Vector2(140, -140):
	set(value):
		anchor_position = value
		queue_redraw()
@export var base_color: Color = Color(1, 1, 1, 0.12):
	set(value):
		base_color = value
		queue_redraw()
@export var knob_color: Color = Color(1, 1, 1, 0.28):
	set(value):
		knob_color = value
		queue_redraw()

var value: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO

func _get_origin() -> Vector2:
	var p: Vector2 = anchor_position
	if p.x < 0.0:
		p.x += size.x
	if p.y < 0.0:
		p.y += size.y
	return p

func _draw() -> void:
	var origin: Vector2 = _get_origin()
	draw_circle(origin, base_radius, base_color)
	draw_circle(origin + _knob_offset, knob_radius, knob_color)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_try_start(event.index, event.position)
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)

func _try_start(index: int, pos: Vector2) -> void:
	if _touch_index != -1:
		return

	var origin: Vector2 = _get_origin()
	if pos.distance_to(origin) > base_radius * 1.5:
		return

	_touch_index = index
	_origin = origin
	_update_knob(pos)

func _update_knob(pos: Vector2) -> void:
	var offset: Vector2 = pos - _origin
	if offset.length() > base_radius:
		offset = offset.normalized() * base_radius

	_knob_offset = offset
	queue_redraw()

	var normalized: Vector2 = offset / base_radius if base_radius > 0.0 else Vector2.ZERO
	if normalized.length() < dead_zone:
		normalized = Vector2.ZERO

	value = normalized
	moved.emit(value)

func _release() -> void:
	if _touch_index == -1 and value == Vector2.ZERO:
		return

	_touch_index = -1
	_knob_offset = Vector2.ZERO
	value = Vector2.ZERO
	queue_redraw()
	moved.emit(value)
