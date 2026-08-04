extends Control
class_name ChimeraHeartbeatTouchZone

## Android touch support for Chimera's heartbeat mechanic (HeartbeatController,
## heartbeat_controller.gd). Wraps a RubiconMechanicHitbox (the same reusable
## translucent tap-zone widget Safety Lullaby's pendulum uses) around the
## heart sprite's own on-screen position instead of a floating button
## unrelated to where the heart actually is - same "touch what you see"
## reasoning as ChimeraEscapeDPad.
##
## The heart lives under a Node3D ("SerenaHeartbeat") purely for scene
## organization - it's still a real CanvasItem with an ordinary 2D screen
## position (see heartbeat_controller.gd's own line_reference doc), just
## repositioned once per cutscene beat rather than continuously, so
## following it here is a matter of polling its position each frame, not
## projecting anything through a 3D camera.

@export var hitbox: Control
@export var heartbeat: HeartbeatController
@export var heart_sprite: CanvasItem

@export var hitbox_size: Vector2 = Vector2(260, 260)

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

	var should_show: bool = heartbeat.beating_enabled and not heartbeat.autoplay and not get_tree().paused
	if should_show != hitbox.visible:
		hitbox.visible = should_show
		if not should_show and hitbox.has_method("_release_all"):
			hitbox.call("_release_all")

	if not should_show:
		return

	var center: Vector2 = heart_sprite.get_global_transform_with_canvas().origin
	hitbox.position = center - hitbox_size * 0.5
