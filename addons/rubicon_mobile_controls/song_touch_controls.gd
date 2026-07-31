extends Control
class_name RubiconSongTouchControls

## Touch overlay for song gameplay screens. RubiconMobileControls (the
## hitbox) only covers note lanes — this adds the rest of what a
## touch-only Android player needs during a song: pausing, restarting,
## and an optional "special action" button for song-specific mechanics
## normally bound to a single keyboard action (e.g. Lullaby's
## lullaby_special-driven pendulum mechanic in Safety Lullaby, or
## whatever each other song binds to that same action). The special
## button is generic on purpose — wire mechanic_source to whatever node
## exposes "started"/"autoplay" (duck-typed, no hard dependency on any
## Lullaby class from this shared addon) and connect its own state-change
## signal to _on_mechanic_state_changed in the scene's [connection] block.

@export var pause_button: Button
@export var restart_button: Button
@export var special_button: Button
@export var special_action: StringName = &"lullaby_special"
@export var mechanic_source: Node

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process_input(false)
		return

	if pause_button:
		pause_button.pressed.connect(func(): _dispatch(&"funkin_pause"))
	if restart_button:
		restart_button.pressed.connect(func(): _dispatch(&"quick_restart"))
	if special_button:
		special_button.pressed.connect(func(): _dispatch(special_action))
		special_button.visible = false
		_on_mechanic_state_changed()

func _on_mechanic_state_changed() -> void:
	if not special_button or not mechanic_source:
		return

	var started: bool = mechanic_source.get("started") if "started" in mechanic_source else false
	var autoplay: bool = mechanic_source.get("autoplay") if "autoplay" in mechanic_source else false
	special_button.visible = started and not autoplay

func _dispatch(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
