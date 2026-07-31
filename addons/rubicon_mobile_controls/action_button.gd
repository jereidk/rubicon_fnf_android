extends Button
class_name RubiconActionButton

## Translucent round tap target that dispatches a press+release pair for
## [member action], one frame apart, exactly like a real key tap. Used for
## the menu overlay's Accept/Cancel buttons: some scripts read the raw
## InputEvent (event.is_action_pressed), others poll
## Input.is_action_just_released next frame, so both need to fire for this
## to behave like an actual key press in every listener.

@export var action: StringName = &"ui_accept"

## Optional: only show this button while this bool property is true (e.g.
## a contextual shortcut like "F / Switch Cartridge" that only means
## anything while the cartridge icon is actually focused). Leave
## visible_source unset to always show, which is the common case.
@export var visible_source: Node
@export var visible_property: StringName = &""

## Optional second required condition (AND'd with the first) - needed
## because a Control's own "focused" var can already be true well before
## its menu is actually open (e.g. ConsoleTab.default_focus grabs the
## Cartridges icon's focus as soon as the console scene loads, long
## before the player has looked at the console at all).
@export var visible_source2: Node
@export var visible_property2: StringName = &""

func _ready() -> void:
	pressed.connect(_dispatch)
	button_down.connect(_flash)
	if visible_source == null or visible_property.is_empty():
		set_process(false)
	else:
		visible = _compute_visible()

func _process(_delta: float) -> void:
	visible = _compute_visible()

func _compute_visible() -> bool:
	var v: bool = bool(visible_source.get(visible_property))
	if v and visible_source2 != null and not visible_property2.is_empty():
		v = bool(visible_source2.get(visible_property2))
	return v

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

## Quick bright pulse on touch-down, on top of the pressed/normal
## StyleBoxFlat swap - a flash reads as "the touch registered" far more
## immediately than a style change alone.
func _flash() -> void:
	modulate = Color(1.7, 1.7, 1.7, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
