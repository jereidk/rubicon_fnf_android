extends Control
class_name SafetyLullabyTouchControls

## Android touch support for Safety Lullaby's pendulum mechanic
## (LullabyPendulumServer/LullabyPendulum, lullaby_special-driven - see
## lullaby_pendulum_server.gd's own input_hit_window_ms). Shows the
## full-width red hitbox (RubiconMechanicHitbox, mechanic_touch_hitbox.gd)
## only while the pendulum is actually waiting for input - the same
## visibility rule RubiconSongTouchControls' generic special_button used
## (started and not autoplay), just targeting a big tap zone instead of a
## small centered button. A 75ms hit window is hard to land precisely on
## a 160px button while also holding a note lane with the other hand;
## mirrors ChimeraSpecialTouchControls' own dedicated-script pattern
## (chimera_special_touch_controls.gd) rather than trying to force this
## into the generic special_button/mechanic_source duck-typing.

@export var hitbox: Control
@export var pendulum_server: LullabyPendulumServer

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

	if pendulum_server:
		pendulum_server.start_changed.connect(_update_visibility)
		_update_visibility()

func _update_visibility() -> void:
	if not hitbox or not pendulum_server:
		return

	hitbox.visible = pendulum_server.started and not pendulum_server.autoplay
