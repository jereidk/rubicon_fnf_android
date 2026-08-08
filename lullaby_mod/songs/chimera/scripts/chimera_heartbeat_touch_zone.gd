extends Control
class_name ChimeraHeartbeatTouchZone

## Android touch support for Chimera's heartbeat mechanic (HeartbeatController,
## heartbeat_controller.gd). Wraps a RubiconActionButton (action_button.gd -
## the same discrete, keycap-styled tap button the Collector Shop's own
## Accept/Cancel/F buttons use, and ChimeraPictureTakingTouchZone's own
## button) around the heart sprite's own on-screen position instead of a
## floating button unrelated to where the heart actually is - same "touch
## what you see" reasoning as ChimeraEscapeDPad, now expressed as an actual
## button instead of a big translucent hitbox zone (RubiconMechanicHitbox),
## matching how the D-pad reads as a set of discrete key-shaped buttons
## rather than one ambient tap surface.
##
## The heart lives under a Node3D ("SerenaHeartbeat") purely for scene
## organization - it's still a real CanvasItem with an ordinary 2D screen
## position (see heartbeat_controller.gd's own line_reference doc), just
## repositioned once per cutscene beat rather than continuously, so
## following it here is a matter of polling its position each frame, not
## projecting anything through a 3D camera.

@export var hitbox: Button
@export var heartbeat: HeartbeatController
@export var heart_sprite: CanvasItem

@export var hitbox_size: Vector2 = Vector2(180, 180)

## Showcase Mode only; see LullabyShowcase.
const SHOWCASE_TOUCH_INDEX: int = -1000
const SHOWCASE_FLASH_SECONDS: float = 0.1

var _was_beaten: bool = false

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
		hitbox.size = hitbox_size

	# Needs to keep running through get_tree().paused = true so it can hide
	# the hitbox when that happens - same reasoning as RubiconMechanicHitbox/
	# RubiconMobileControls' identical process_mode override.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not hitbox or not heartbeat or not heart_sprite:
		return

	var should_show: bool = (heartbeat.beating_enabled
		and LullabyShowcase.mechanic_controls_visible(heartbeat.autoplay)
		and not get_tree().paused)
	hitbox.visible = should_show

	# In Showcase Mode the mechanic plays itself, so the button flashes on
	# each automatic beat instead of sitting inert. has_beaten is watched
	# rather than hooking a signal because heartbeat_controller.gd is carried
	# over from the pck and matches it line for line - adding a signal there
	# would be a divergence for a purely cosmetic feature. It is set true in
	# heart_beat() and cleared in reset_timer(), so the false->true edge is
	# exactly one beat.
	var beaten: bool = heartbeat.has_beaten
	if beaten and not _was_beaten and should_show:
		LullabyShowcase.flash_control(hitbox, get_tree(), SHOWCASE_TOUCH_INDEX,
			SHOWCASE_FLASH_SECONDS)
	_was_beaten = beaten

	if not should_show:
		return

	var center: Vector2 = heart_sprite.get_global_transform_with_canvas().origin
	hitbox.position = center - hitbox_size * 0.5
