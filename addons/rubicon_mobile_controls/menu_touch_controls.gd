extends Control
class_name RubiconMenuTouchControls

## Cloud-gaming style touch overlay: a joystick (ui_up/down/left/right)
## plus Accept/Cancel buttons (ui_accept/ui_cancel). Every focus-navigated
## menu already reads these same 4 actions via focus_neighbor, and a host
## scene's own look/pan controller can read ui_right/ui_left the same way,
## so a single persistent instance covers a whole scene end to end - no
## separate overlay swapped in per sub-state, no popping in/out as the
## player moves between views. Stays visible and functional everywhere
## except the states named in inactive_states: the one legitimate reason
## to hide it is a state with no player input at all (a scripted
## sequence, a forced camera move), not a change of view.

@export var dpad: RubiconVirtualDPad
@export var accept_button: RubiconActionButton
@export var cancel_button: RubiconActionButton

## Node+property polled every frame (e.g. a CollectorShop and "state").
## Leave active_source unset to stay always visible/functional.
@export var active_source: Node
@export var active_property: StringName = &""
@export var inactive_states: Array[int] = []

var _enabled: bool = true

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_enabled = settings_enabled and has_touch
	if not _enabled:
		visible = false
		set_process(false)
		if dpad:
			dpad.set_process_input(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if active_source == null or active_property.is_empty():
		set_process(false)
		return

	var active: bool = not inactive_states.has(int(active_source.get(active_property)))
	if active == visible:
		return

	visible = active
	if dpad:
		dpad.set_process_input(active)
		if not active:
			dpad._release()
