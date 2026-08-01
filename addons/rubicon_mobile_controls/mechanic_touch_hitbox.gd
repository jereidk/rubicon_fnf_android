extends Control
class_name RubiconMechanicHitbox

## Full-rect touch zone for a song's "special mechanic" input (e.g. Safety
## Lullaby's pendulum, bound to lullaby_special - see
## song_touch_controls.gd's own doc comment for the general pattern that
## button used). Meant to sit exactly in RubiconMobileControls' own
## hitbox_top_percent dead zone (the top strip that hitbox deliberately
## leaves untouched for HUD elements) - a song only ever has one mechanic
## active during gameplay, so unlike the 4-lane note hitbox there's no
## need to divide this into zones: the whole rect is one big, forgiving
## tap target, styled the same way (translucent fill + outline) but red to
## read as a different kind of input from the note lanes below it.
##
## Unlike RubiconMobileControls, this uses Control's own _gui_input()
## instead of raw _input() with manual position math - simpler, and fine
## here because a single zone has no per-lane state to track; ordinary GUI
## hit-testing already limits events to this control's own rect.

signal hit
signal released

@export var action: StringName = &"lullaby_special"

@export var show_outline: bool = true
@export var outline_color: Color = Color(1, 0, 0, 0.55)
@export var outline_width: float = 2.0
@export var fill_color: Color = Color(1, 0, 0, 0.08)
@export var pressed_fill_color: Color = Color(1, 0, 0, 0.28)

const MOUSE_TOUCH_INDEX := -1000

var _active_touches: Dictionary = {}

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		# _gui_input() only fires for a visible Control anyway, but also
		# stop consuming/blocking clicks meant for whatever's underneath.
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all()

func _draw() -> void:
	var is_pressed: bool = not _active_touches.is_empty()
	var fill: Color = pressed_fill_color if is_pressed else fill_color
	var rect := Rect2(Vector2.ZERO, size)

	if fill.a > 0.0:
		draw_rect(rect, fill, true)
	if show_outline:
		draw_rect(rect, outline_color, false, outline_width)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.pressed)

func _handle_touch(index: int, pressed: bool) -> void:
	if pressed:
		if _active_touches.has(index):
			return
		_active_touches[index] = true
		if _active_touches.size() == 1:
			_dispatch(true)
			hit.emit()
	else:
		if not _active_touches.has(index):
			return
		_active_touches.erase(index)
		if _active_touches.is_empty():
			_dispatch(false)
			released.emit()

	queue_redraw()

func _dispatch(pressed: bool) -> void:
	var press_event := InputEventAction.new()
	press_event.action = action
	press_event.pressed = pressed
	Input.parse_input_event(press_event)

func _release_all() -> void:
	if _active_touches.is_empty():
		return

	_active_touches.clear()
	_dispatch(false)
	released.emit()
	queue_redraw()
