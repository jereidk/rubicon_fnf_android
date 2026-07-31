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

## Optional escape hatch: whenever this bool property is true, the overlay
## is forced active even if active_source says otherwise. Needed because
## a single state enum doesn't capture every "player needs input right
## now" case - e.g. the Cabinet of Novelties' console sets the shop's
## state to BUSY for the whole time it's open (not just its boot
## animation), so gating purely on that state would hide the overlay
## exactly while the player is navigating the console menu.
@export var force_active_source: Node
@export var force_active_property: StringName = &""

## Node+property polled every frame to pick the D-pad's visual style:
## continuous joystick drag for free-look camera panning, or a discrete
## arrow D-pad for fixed menu selection. style_joystick_states lists the
## values of style_property (read from style_source, e.g. a
## CollectorShop and "state") that mean "show the joystick" - every
## other value (including ones the overlay is only visible for via
## force_active_source, like the console) shows the arrow D-pad instead.
## Leave style_source unset to keep the D-pad's own default style always.
@export var style_source: Node
@export var style_property: StringName = &""
@export var style_joystick_states: Array[int] = []

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
	if not active and force_active_source != null and not force_active_property.is_empty():
		active = bool(force_active_source.get(force_active_property))

	if dpad and style_source != null and not style_property.is_empty():
		var state_value: int = int(style_source.get(style_property))
		var wants_joystick: bool = style_joystick_states.has(state_value)
		dpad.visual_style = RubiconVirtualDPad.VisualStyle.JOYSTICK if wants_joystick else RubiconVirtualDPad.VisualStyle.ARROWS

	if active == visible:
		return

	visible = active
	if dpad:
		dpad.set_process_input(active)
		if not active:
			dpad._release()
