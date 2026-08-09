class_name LullabyInputBinds

## Turns an action name into the text of whatever is currently bound to it,
## for UI that has to say "press THIS" without hardcoding a key.
##
## Two things make that harder than InputMap.action_get_events(): gameplay
## actions live in Settings.input_game rather than the InputMap, and an
## action usually has several events bound (a key AND a gamepad button), so
## which one to show depends on what the player last touched.
##
## Extracted from shop_bind_ui.gd, which does the $action$ substitution in a
## Label - this is the same resolution it always did.
##
## RubiconActionButton has a resolver of its own and that is deliberate, not
## a duplicate to be merged: everything in addons/rubicon_mobile_controls
## reads only ProjectSettings and has to keep loading in a project with no
## Settings autoload at all, so its version is InputMap-only. This one adds
## the Settings.input_game fallback for actions that never reach the
## InputMap. If you collapse the two, the addon stops standing alone.

enum BindType {
	KBM,
	CONTROLLER,
}

## Which family of device an event belongs to, or -1 for events that say
## nothing about it (InputEventAction, screen touch).
##
## shop_bind_ui.gd's version of this read
##   `input is InputEventKey or InputEventMouseButton or InputEventMouseMotion`
## which is `(input is InputEventKey) or (InputEventMouseButton) or (...)` -
## a bare class reference is truthy, so it returned true for everything and
## the CONTROLLER branch could never be selected. Written out properly here.
static func type_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		return BindType.KBM
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return BindType.CONTROLLER
	return -1

static func has_action(action_name: StringName) -> bool:
	return InputMap.has_action(action_name) or Settings.input_game.has(action_name)

## The events bound to an action, from whichever of the two maps holds it.
static func events_for(action_name: StringName) -> Array[InputEvent]:
	if InputMap.has_action(action_name):
		return InputMap.action_get_events(action_name)

	var from_settings: Variant = Settings.input_game.get(action_name)
	var out: Array[InputEvent] = []
	if from_settings is Array:
		for event: Variant in from_settings:
			if event is InputEvent:
				out.append(event)
	return out

## Preferred event for an action, given what the player is using. Falls back
## to the first binding of any type rather than to nothing, so an action
## bound only on a gamepad still shows something to a keyboard player.
static func event_for(action_name: StringName, bind_type: int) -> InputEvent:
	var events: Array[InputEvent] = events_for(action_name)
	if events.is_empty():
		return null

	for event: InputEvent in events:
		if type_of(event) == bind_type:
			return event

	return events[0]

## Display text for an action's current binding, or "" when it has none.
##
## as_text() spells a key event out as e.g. "Enter (Physical)", which is
## noise on a prompt; the suffix is dropped the same way shop_bind_ui.gd
## drops it.
static func text_for(action_name: StringName, bind_type: int = BindType.KBM) -> String:
	var event: InputEvent = event_for(action_name, bind_type)
	if event == null:
		return ""

	return event.as_text().replace(" (Physical)", "").replace(" - Physical", "")
