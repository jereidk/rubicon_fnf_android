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

## The score/health HUD (UILayer/GameUI/DefaultHUD) already fades itself
## out via modulate:alpha tracks on cutscene animations, but nothing did
## the same for this hitbox - it kept drawing over cutscenes, gameover,
## and the pause menu (whose CanvasLayer draws below UILayer's default
## layer, so it doesn't visually cover the hitbox either). Polling
## default_hud's own modulate/visible each frame - rather than hooking
## every individual cutscene animation - covers all of that generically,
## same idea as the pause case below.
@export var default_hud: CanvasItem

## Safety Lullaby's gameover is an in-scene cutscene (SafetyLullabyGameoverModule,
## not a scene change like Monochrome/Chimera use), and nothing in it fades
## default_hud or pauses the tree - is_game_over covers that gap directly.
@export var gameover_module: SafetyLullabyGameoverModule

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# _process() needs to keep running through get_tree().paused = true (the
	# pause menu's own trigger) so it can react to that transition at all -
	# by default a paused SceneTree stops a Control's _process() outright,
	# which would just leave the hitbox frozen in whatever state it was in
	# the instant pause hit, visible or not.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if hitbox:
		hitbox.visible = false

	_update_visibility()

func _process(_delta: float) -> void:
	_update_visibility()

func _update_visibility() -> void:
	if not hitbox or not pendulum_server:
		return

	if get_tree().paused:
		hitbox.visible = false
		return

	if gameover_module and gameover_module.is_game_over:
		hitbox.visible = false
		return

	var mechanic_active: bool = pendulum_server.started and not pendulum_server.autoplay
	var hud_visible: bool = true
	if default_hud:
		hud_visible = default_hud.visible and default_hud.modulate.a > 0.01

	hitbox.visible = mechanic_active and hud_visible
