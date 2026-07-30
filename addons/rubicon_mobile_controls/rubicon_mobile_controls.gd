@tool
extends Control
class_name RubiconMobileControls

## Full-height "hitbox" style touch control: divides the control's rect into
## [member lane_count] vertical zones. Tapping/holding anywhere inside a zone
## presses that lane, mirroring a physical hitbox controller layout instead
## of small individual buttons.

signal lane_pressed(lane_id: int)
signal lane_released(lane_id: int)

const MOUSE_TOUCH_INDEX := -1000

@export var lane_count: int = 4:
	set(value):
		lane_count = maxi(value, 1)
		queue_redraw()

## Fraction of the control's height (from the top) left untouched, so HUD
## elements like a pause button aren't covered by the hitbox zones.
@export_range(0.0, 1.0, 0.01) var hitbox_top_percent: float = 0.2:
	set(value):
		hitbox_top_percent = value
		queue_redraw()

@export var show_outlines: bool = true:
	set(value):
		show_outlines = value
		queue_redraw()

@export var outline_color: Color = Color(1, 1, 1, 0.35):
	set(value):
		outline_color = value
		queue_redraw()

@export var outline_width: float = 2.0:
	set(value):
		outline_width = value
		queue_redraw()

@export var fill_color: Color = Color(1, 1, 1, 0.03):
	set(value):
		fill_color = value
		queue_redraw()

@export var pressed_fill_color: Color = Color(1, 1, 1, 0.16):
	set(value):
		pressed_fill_color = value
		queue_redraw()

@export var haptic_feedback: bool = true
@export var haptic_duration_ms: int = 35

var _touch_to_lane: Dictionary = {}
var _lane_active_count: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process_input(false)
		return

	var handler: Node = get_node_or_null("/root/RubiconTouchInput")
	if handler != null:
		lane_pressed.connect(handler._on_mobile_controls_lane_pressed)
		lane_released.connect(handler._on_mobile_controls_lane_released)

func _draw() -> void:
	var top_y: float = size.y * hitbox_top_percent
	if top_y >= size.y or lane_count <= 0:
		return

	var zone_width: float = size.x / float(lane_count)
	for i in range(lane_count):
		var rect := Rect2(i * zone_width, top_y, zone_width, size.y - top_y)
		var is_pressed: bool = _lane_active_count.get(i, 0) > 0
		var fill: Color = pressed_fill_color if is_pressed else fill_color
		if fill.a > 0.0:
			draw_rect(rect, fill, true)
		if show_outlines:
			draw_rect(rect, outline_color, false, outline_width)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.position, event.pressed)

func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var lane: int = _get_lane_for_position(pos)
		if lane < 0:
			return
		_touch_to_lane[index] = lane
		_press_lane(lane)
	else:
		if not _touch_to_lane.has(index):
			return
		var lane: int = _touch_to_lane[index]
		_touch_to_lane.erase(index)
		_release_lane(lane)

func _handle_drag(index: int, pos: Vector2) -> void:
	if not _touch_to_lane.has(index):
		return

	var new_lane: int = _get_lane_for_position(pos)
	var old_lane: int = _touch_to_lane[index]
	if new_lane < 0 or new_lane == old_lane:
		return

	_touch_to_lane[index] = new_lane
	_release_lane(old_lane)
	_press_lane(new_lane)

func _press_lane(lane: int) -> void:
	var count: int = _lane_active_count.get(lane, 0)
	_lane_active_count[lane] = count + 1
	if count == 0:
		lane_pressed.emit(lane)
		if haptic_feedback:
			Input.vibrate_handheld(haptic_duration_ms)
	queue_redraw()

func _release_lane(lane: int) -> void:
	var count: int = _lane_active_count.get(lane, 0)
	if count <= 0:
		return

	count -= 1
	if count <= 0:
		_lane_active_count.erase(lane)
		lane_released.emit(lane)
	else:
		_lane_active_count[lane] = count
	queue_redraw()

func _release_all() -> void:
	for lane in _lane_active_count.keys():
		lane_released.emit(lane)
	_lane_active_count.clear()
	_touch_to_lane.clear()
	queue_redraw()

func _get_lane_for_position(pos: Vector2) -> int:
	if pos.y < size.y * hitbox_top_percent:
		return -1
	if pos.x < 0.0 or pos.x >= size.x:
		return -1

	var zone_width: float = size.x / float(lane_count)
	return clampi(int(pos.x / zone_width), 0, lane_count - 1)
