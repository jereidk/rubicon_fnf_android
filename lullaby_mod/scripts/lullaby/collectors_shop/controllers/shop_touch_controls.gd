class_name ShopTouchControls
extends Control

## Android touch overlay for the Cabinet of Novelties free-look scene.
## Rubicon addition (not part of the original mod): the ported
## MouseController drives camera panning off Input.get_axis("ui_right",
## "ui_left") before falling back to mouse-edge hover, so the D-pad's
## left/right zones pressing/releasing those same built-in UI actions is
## all MouseController.gd needs - no changes there. Tap-to-interact
## already works via Godot's default touch-emulates-mouse (RightClick is
## bound to the left mouse button), so this overlay only needs to add
## what touch genuinely lacks: a look control and a visible way to back
## out of a focused view. Navigation is D-pad only (no raw touch-drag
## look) so a swipe meant to look around never gets misread as a tap on
## a prop/door underneath it.

@export var shop: CollectorShop
@export var back_button: Control
@export var dpad: RubiconVirtualDPad

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		if dpad:
			dpad.set_process_input(false)
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
			if dpad:
				dpad._release()

## Some real mod scripts (e.g. prp_sign.gd) poll
## Input.is_action_just_released("ui_cancel") instead of reading the raw
## event, so a press with no matching release (as a real key tap would
## produce) never satisfies them. Dispatch both, one frame apart, to match
## a real key press+release.
func _on_back_pressed() -> void:
	var press := InputEventAction.new()
	press.action = &"ui_cancel"
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = &"ui_cancel"
	release.pressed = false
	Input.parse_input_event(release)
