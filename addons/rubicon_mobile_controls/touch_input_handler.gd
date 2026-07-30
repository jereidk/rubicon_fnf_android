@tool
extends Node
class_name RubiconTouchInputHandler

## Translates lane taps/releases from a RubiconMobileControls hitbox into
## synthetic InputEventKey presses. RubiconLevelNoteController reads raw
## InputEvents matched against a RubiconLevelNoteInputMap resource (see
## addons/rubicon/scripts/data/game/rubicon_level_note_input_map.gd),
## not the global Godot InputMap action system, so a synthesized key event
## is what actually needs to reach it via Input.parse_input_event.

@export var enabled: bool = true

## Must match the keycodes used by the active RubiconLevelNoteInputMap
## resource (e.g. addons/rubicon_mania/resources/default_input_map.tres).
var lane_to_keycode: Dictionary = {
	0: KEY_D,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K,
}

func handle_touch_input(lane: int, pressed: bool) -> void:
	if not enabled or not lane_to_keycode.has(lane):
		return

	var event := InputEventKey.new()
	event.device = -1
	event.keycode = lane_to_keycode[lane]
	event.pressed = pressed
	Input.parse_input_event(event)

func _on_mobile_controls_lane_pressed(lane_id: int) -> void:
	handle_touch_input(lane_id, true)

func _on_mobile_controls_lane_released(lane_id: int) -> void:
	handle_touch_input(lane_id, false)
