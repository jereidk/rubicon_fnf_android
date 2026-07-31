extends Button
class_name RubiconActionButton

## Translucent round tap target that dispatches a press+release pair for
## [member action], one frame apart, exactly like a real key tap. Used for
## the menu overlay's Accept/Cancel buttons: some scripts read the raw
## InputEvent (event.is_action_pressed), others poll
## Input.is_action_just_released next frame, so both need to fire for this
## to behave like an actual key press in every listener.

@export var action: StringName = &"ui_accept"

func _ready() -> void:
	pressed.connect(_dispatch)

func _dispatch() -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
