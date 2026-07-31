class_name ShopTouchControls
extends Control

## Android touch overlay for the Cabinet of Novelties free-look scene.
## Rubicon addition (not part of the original mod): the ported
## MouseController drives camera panning off Input.get_axis("ui_right",
## "ui_left") before falling back to mouse-edge hover, so holding either
## look zone here just presses/releases those built-in UI actions and
## MouseController.gd needs no changes. Tap-to-interact already works via
## Godot's default touch-emulates-mouse (RightClick is bound to the left
## mouse button), so this overlay only needs to add what touch genuinely
## lacks: a look control and a visible way to back out of a focused view.

@export var shop: CollectorShop
@export var look_zone_width_percent: float = 0.22
@export var back_button: Control

var _look_touches: Dictionary = {}

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process_input(false)
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _process(_delta: float) -> void:
	if back_button:
		back_button.visible = shop != null and shop.state == shop.ShopStates.FOCUSED

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_touch(event.index, event.position, true)

func _release_all() -> void:
	for index in _look_touches.keys():
		_release_action(_look_touches[index])
	_look_touches.clear()

func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		_release_look(index)
		return

	var zone: int = _get_look_zone(pos)
	var previous_zone: int = _look_touches.get(index, 0)
	if zone == previous_zone:
		return

	if previous_zone != 0:
		_release_action(previous_zone)
	if zone != 0:
		_press_action(zone)
		_look_touches[index] = zone
	else:
		_look_touches.erase(index)

func _release_look(index: int) -> void:
	if not _look_touches.has(index):
		return
	_release_action(_look_touches[index])
	_look_touches.erase(index)

func _get_look_zone(pos: Vector2) -> int:
	if back_button and back_button.visible and back_button.get_global_rect().has_point(pos):
		return 0

	var zone_width: float = size.x * look_zone_width_percent
	if pos.x < zone_width:
		return -1
	if pos.x > size.x - zone_width:
		return 1
	return 0

func _press_action(zone: int) -> void:
	Input.action_press(&"ui_left" if zone < 0 else &"ui_right")

func _release_action(zone: int) -> void:
	Input.action_release(&"ui_left" if zone < 0 else &"ui_right")

func _on_back_pressed() -> void:
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
