extends Control
class_name MonochromeTypingTouchControls

## Android touch support for Monochrome's TypingChallenge mechanic
## (Stage/TypingChallenge). Desktop players type on a physical keyboard;
## TypingChallenge._input() reads raw InputEventKey letter by letter. There
## is no keyboard on Android, so this shows a RubiconOnScreenKeyboard while
## the challenge is actually prompting for input and forwards taps straight
## into TypingChallenge.input_letter() - the same public entry point the
## keyboard path already funnels into, so no changes to TypingChallenge
## itself are needed.

@export var typing_challenge: TypingChallenge
@export var keyboard: RubiconOnScreenKeyboard

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if keyboard:
		keyboard.key_pressed.connect(_on_key_pressed)

func _process(_delta: float) -> void:
	if not keyboard or not typing_challenge:
		return

	keyboard.visible = (
		typing_challenge.active
		and typing_challenge.prompt_user
		and not typing_challenge.autoplay
		and not typing_challenge.challenge_over
	)

func _on_key_pressed(character: String) -> void:
	if not typing_challenge:
		return
	typing_challenge.input_letter(character)
