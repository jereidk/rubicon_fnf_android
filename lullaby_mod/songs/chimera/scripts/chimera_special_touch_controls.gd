extends Control
class_name ChimeraSpecialTouchControls

## Android touch support for Chimera's two "lullaby_special"-driven
## mechanics (HeartbeatController, PictureTakingController). Each one reads
## the keyboard action directly in its own _input(), and each exposes a
## differently-named "is this mechanic currently live" property, so
## RubiconSongTouchControls' generic duck-typed special_button (which only
## understands "started"/"autoplay") can't drive both. This shows a single
## special button whenever either one is actively waiting for input and
## dispatches lullaby_special on tap - the same synthetic-action approach
## RubiconSongTouchControls uses for pause/restart.
##
## The third lullaby_special-driven mechanic, CrawlTimingController, used
## to share this button too, but it also asks for the 4 note lanes (not
## just lullaby_special) with no touch cue at all for those prompts, and
## reading it here would've meant reusing a small floating "TAP!" button
## with no relation to CrawlTimingController's own randomized on-screen
## key prompt. It now has its own dedicated control instead -
## ChimeraEscapeDPad, a D-pad styled like the Collector's Shop's own menu
## navigation pad, covering all 5 of its possible prompts.

@export var special_button: Button
@export var heartbeat: HeartbeatController
@export var picture_taking: PictureTakingController

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if special_button:
		special_button.pressed.connect(_on_special_button_pressed)
		special_button.visible = false

func _process(_delta: float) -> void:
	if not special_button:
		return

	special_button.visible = _is_heartbeat_active() or _is_picture_taking_active()

func _is_heartbeat_active() -> bool:
	return heartbeat != null and heartbeat.beating_enabled and not heartbeat.autoplay

func _is_picture_taking_active() -> bool:
	return picture_taking != null and picture_taking.mechanic_enabled and not picture_taking.autoplay

func _on_special_button_pressed() -> void:
	var press := InputEventAction.new()
	press.action = &"lullaby_special"
	press.pressed = true
	Input.parse_input_event(press)
