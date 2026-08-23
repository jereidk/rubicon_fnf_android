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
## mirrors Chimera's own per-mechanic dedicated-script pattern
## (chimera_escape_dpad.gd, chimera_heartbeat_touch_zone.gd,
## chimera_picture_taking_touch_zone.gd) rather than trying to force this
## into the generic special_button/mechanic_source duck-typing.

## How long the hitbox stays flashed "pressed" after a showcase-mode
## autoplay pendulum hit (LullabyPendulumServer.pendulum_hit) - mirrors a
## quick real tap rather than the full input_hit_window_ms.
const SHOWCASE_HIT_FLASH_SECONDS: float = 0.1
const SHOWCASE_TOUCH_INDEX: int = -2000

@export var hitbox: Control
@export var pendulum_server: LullabyPendulumServer

## The score/health HUD (UILayer/GameUI/DefaultHUD). Kept wired, and
## deliberately NOT part of the visibility rule any more.
##
## It used to be: `hitbox.visible = mechanic_active and hud_visible`, on the
## reasoning that the HUD already fades itself out on cutscenes so following it
## covers cutscenes, gameover and pause generically. That is true for a HUD
## element. This is not a HUD element - it is the only way to play the
## mechanic on a touch device, and coupling the two made the last third of the
## song unplayable.
##
## The song's own Timeline says so. Reading the two tracks out of
## `sng_safety_lullaby.tscn`'s `play` animation:
##
##     LullabyPendulumServer:started    0.00 off  33.73 ON  159.08 off  160.04 ON  194.37 off
##     DefaultHUD:modulate.a            0.00 0    31.53 0   33.73 1     158.00 1   159.03 0
##
## and the HUD has no key after 159.03, so it stays at alpha 0 to the end. The
## overlap of "pendulum running" and "HUD faded" is 159.03-159.08 and then
## **160.04-194.37: thirty-four seconds** in which the pendulum keeps asking
## for `lullaby_special` every half measure and keeps taking `retention_loss`
## (-15 of 100) on every miss, so seven missed measures reach 0 and fire
## `mechanic_failed`. On desktop that section is fine - the HUD is gone but the
## key still works, and the pendulum itself is scene geometry, still swinging on
## screen to keep time against. On Android the hitbox was the input, and hiding
## it deleted the input while leaving the punishment. "Si el Hitbox desaparece,
## como lo hago en primer lugar" - exactly.
##
## Nothing is lost by dropping the term. `started` is already false for every
## cutscene (0-33.73 and 159.08-160.04), pause has its own check below and so
## does gameover, so outside those two windows the rule never differed. It only
## ever changed the answer where the mechanic was live.
##
## `song_touch_controls.gd` keeps the same coupling for the pause and restart
## buttons, and should: those really are HUD, and nothing is lost when they fade
## with it.
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

	if pendulum_server:
		pendulum_server.pendulum_hit.connect(_on_pendulum_hit)

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

	# Showcase Mode wants this hitbox visibly flashing along with the
	# pendulum's own autoplay hits (see _on_pendulum_hit below), so it
	# stays shown during autoplay instead of hiding like normal autoplay
	# (e.g. the debug "Autoplay?" toggle) does. The rule itself lives in
	# LullabyShowcase now - Chimera needs the same one.
	var mechanic_active: bool = (pendulum_server.started
		and LullabyShowcase.mechanic_controls_visible(pendulum_server.autoplay))

	# The mechanic decides, and only the mechanic. See default_hud above for the
	# thirty-four seconds this cost.
	hitbox.visible = mechanic_active

func _on_pendulum_hit() -> void:
	LullabyShowcase.flash_control(hitbox, get_tree(), SHOWCASE_TOUCH_INDEX,
		SHOWCASE_HIT_FLASH_SECONDS)
