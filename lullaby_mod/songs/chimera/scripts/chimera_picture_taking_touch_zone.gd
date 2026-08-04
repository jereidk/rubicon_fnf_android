extends Control
class_name ChimeraPictureTakingTouchZone

## Android touch support for Chimera's picture-taking mechanic
## (PictureTakingController, mch_picturetaking.gd) - a fixed, discrete
## RubiconActionButton (action_button.gd - the same keycap-styled button the
## Collector Shop's own Accept/Cancel/F buttons use, and
## ChimeraHeartbeatTouchZone's own button) sitting in the same bottom-center
## spot ChimeraEscapeDPad occupies during the crawl mechanic - the two never
## show at once, so reusing that screen real estate keeps a consistent
## "big action" spot instead of introducing a second one. Unlike
## Heartbeat/Escape, this mechanic has no on-screen prompt of its own to
## follow and no timing window to hit - PictureTakingController.
## trigger_flash_and_continue() fires immediately on lullaby_special,
## whenever it's pressed - so there's nothing for this script to do but
## show/hide the button.

@export var hitbox: Button
@export var picture_taking: PictureTakingController

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hitbox:
		hitbox.visible = false

	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not hitbox or not picture_taking:
		return

	var should_show: bool = picture_taking.mechanic_enabled and not picture_taking.autoplay and not get_tree().paused
	hitbox.visible = should_show
