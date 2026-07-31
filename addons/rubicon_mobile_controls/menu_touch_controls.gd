extends Control
class_name RubiconMenuTouchControls

## Cloud-gaming style touch overlay for keyboard/gamepad-focus-navigated
## menus: a D-pad (ui_up/down/left/right) plus Accept/Cancel buttons
## (ui_accept/ui_cancel). Every menu already reads these same actions via
## focus_neighbor navigation for keyboard/gamepad players, so this is the
## only touch code menus need - no per-widget tap detection anywhere else.

@export var dpad: RubiconVirtualDPad
@export var accept_button: RubiconActionButton
@export var cancel_button: RubiconActionButton

## Optional: some hosts (e.g. Console) only want this overlay shown while
## a specific bool property is true (e.g. "focused", so the shop's own
## free-look D-pad-equivalent - ShopTouchControls's drag zones/joystick -
## isn't fought over with this one). Leave unset to always show/hide purely
## based on the touch/settings check below.
@export var visibility_source: Node
@export var visibility_property: StringName = &""

var _enabled: bool = true

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_enabled = settings_enabled and has_touch
	if not _enabled:
		visible = false
		set_process_input(false)
		set_process(false)
		if dpad:
			dpad.set_process_input(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = visibility_source == null

func _process(_delta: float) -> void:
	if visibility_source == null or visibility_property.is_empty():
		set_process(false)
		return

	visible = bool(visibility_source.get(visibility_property))
