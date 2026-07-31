@tool
extends Control
class_name RubiconVirtualDPad

## Cloud-gaming style translucent D-pad: a diamond split into four
## directional zones. Pressing/holding/releasing a zone presses/holds/
## releases the matching ui_up/ui_down/ui_left/ui_right action directly,
## exactly like a held keyboard key - so any menu that already navigates
## via focus_neighbor + those actions works with this with zero changes.
## Sibling to RubiconVirtualJoystick (used for 3D camera look); this one
## is for UI focus navigation instead of analog look/movement.

const ACTIONS := {
	0: &"ui_up",
	1: &"ui_right",
	2: &"ui_down",
	3: &"ui_left",
}

@export var radius: float = 100.0:
	set(value):
		radius = value
		queue_redraw()
@export var anchor_position: Vector2 = Vector2(140, -140):
	set(value):
		anchor_position = value
		queue_redraw()
@export var base_color: Color = Color(1, 1, 1, 0.1):
	set(value):
		base_color = value
		queue_redraw()
@export var pressed_color: Color = Color(1, 1, 1, 0.32):
	set(value):
		pressed_color = value
		queue_redraw()
@export var divider_color: Color = Color(1, 1, 1, 0.25):
	set(value):
		divider_color = value
		queue_redraw()

var _active_zone: int = -1
var _touch_index: int = -1

func _get_origin() -> Vector2:
	var p: Vector2 = anchor_position
	if p.x < 0.0:
		p.x += size.x
	if p.y < 0.0:
		p.y += size.y
	return p

func _draw() -> void:
	var origin: Vector2 = _get_origin()
	for zone in range(4):
		var color: Color = pressed_color if zone == _active_zone else base_color
		var points := PackedVector2Array([
			origin,
			origin + Vector2.from_angle(deg_to_rad(zone * 90.0 - 90.0 - 45.0)) * radius,
			origin + Vector2.from_angle(deg_to_rad(zone * 90.0 - 90.0)) * radius,
			origin + Vector2.from_angle(deg_to_rad(zone * 90.0 - 90.0 + 45.0)) * radius,
		])
		draw_colored_polygon(points, color)
	draw_arc(origin, radius, 0.0, TAU, 32, divider_color, 2.0)
	for zone in range(4):
		var angle: float = deg_to_rad(zone * 90.0 - 90.0 - 45.0)
		draw_line(origin, origin + Vector2.from_angle(angle) * radius, divider_color, 2.0)

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
		_update_zone(event.position)

func _try_start(index: int, pos: Vector2) -> void:
	if _touch_index != -1:
		return

	var origin: Vector2 = _get_origin()
	if pos.distance_to(origin) > radius * 1.4:
		return

	_touch_index = index
	_update_zone(pos)

func _update_zone(pos: Vector2) -> void:
	var origin: Vector2 = _get_origin()
	var offset: Vector2 = pos - origin
	if offset.length() < radius * 0.15:
		_set_zone(-1)
		return

	# atan2 is 0=right, 90=down (Godot's Y-down screen space); rotate so
	# zone 0 (up) starts at -45deg and each zone spans 90deg going clockwise.
	var angle_deg: float = rad_to_deg(offset.angle()) + 90.0 + 45.0
	if angle_deg < 0.0:
		angle_deg += 360.0
	var zone: int = int(angle_deg / 90.0) % 4
	_set_zone(zone)

func _set_zone(zone: int) -> void:
	if zone == _active_zone:
		return

	if _active_zone != -1:
		Input.action_release(ACTIONS[_active_zone])
	if zone != -1:
		Input.action_press(ACTIONS[zone])

	_active_zone = zone
	queue_redraw()

func _release() -> void:
	_touch_index = -1
	_set_zone(-1)
