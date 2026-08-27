extends Node2D
class_name SafetyLullabyGameoverModule

## The version of this class that actually runs (safety_lullaby_gameover.gd,
## a completely separate script under lullaby_mod/scripts/lullaby/gameover/,
## is dead code - nothing instances it anywhere in the project). Safety
## Lullaby's real gameover is an in-scene cutscene played by this module's
## own animation_player, not a scene change like Monochrome/Chimera use -
## see gameover_module.tscn, instanced as "SafetyLullabyGameoverModule"
## directly inside sng_safety_lullaby.tscn.

@export var animation_player: AnimationPlayer
@export var music: AudioStreamPlayer
@export var skip_intro: bool = false

@export var health_module: RubiconHealthModule
@export var clock: RubiconLevelClock

@export var disable_for_skipping: bool = false

@export_group("Baby Mode", "baby_mode_")
@export var baby_mode_enabled: bool = false
@export var baby_mode_lines: Array[AudioStream]
@export var baby_mode_speaker: AudioStreamPlayer

var activated: bool = false

## Set the moment a retry is accepted, so the second half of a single tap
## cannot start a second one.
##
## One tap is two events on Android - emulate_mouse_from_touch turns a
## finger into an InputEventScreenTouch AND an emulated
## InputEventMouseButton, and the is_tap test below accepts both. Without
## this, _input() ran twice, both copies awaited the same
## animation_finished, and both resumed on the same emission, so
## reload_current_scene() was called twice in one frame. Monochrome had the
## same hole and it was worse there, because it retries through
## SceneChanger: the second change_to() orphaned the first loading screen
## on a CanvasLayer at layer 128 and left it covering the running song.
var _retrying: bool = false

## Whether a retry would be accepted right now - the same condition
## _input() tests, exposed for LullabyGameoverPrompt so the on-screen
## button appears exactly when the screen is listening rather than from a
## second copy of the rule that could drift.
var can_retry: bool:
	get:
		return activated and not _retrying

## The prompt's own buttons, so a tap that lands on one is not ALSO read as
## the tap-anywhere retry below.
##
## Tap-anywhere has to keep working when the prompt is not up, or a broken
## prompt would leave a touch player with no way off this screen at all -
## a real risk, since a GDScript type error fails a whole script silently
## and the node then runs with none. But while the prompt IS up, the buttons
## are the affordance, and tap-anywhere would out-race them: _input() is
## delivered before GUI, so tapping EXIT would fire the retry before the
## button's pressed signal ever reached exit_to_shop().
@export var retry_prompt: LullabyGameoverPrompt

## True from the moment health hits zero (before the cutscene even starts
## playing), false again on a fresh scene load. Local/instance-scoped on
## purpose instead of reusing the static LullabyGameoverModule.has_died -
## that flag is only ever reset by env_collector_shop.gd's _ready(), so it
## would still read true on a retry (reload_current_scene() doesn't touch
## statics), incorrectly keeping other systems gated off after retrying.
## See SafetyLullabyTouchControls, which polls this to hide the pendulum
## hitbox for the whole gameover cutscene, not just once it's animated in.
var is_game_over: bool = false

func _ready() -> void :
	if health_module:
		health_module.health_depleted.connect(activate_gameover, CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void :
	if not can_retry or event.is_echo() or not event.is_pressed():
		return

	# ui_cancel is Esc, gamepad B and Android's hardware Back button. Checked
	# before the tap fallback because leaving is the destructive choice of
	# the two and must never be mistaken for a retry.
	if event.is_action(&"ui_cancel"):
		_retrying = true
		exit_to_shop()
		return

	# ui_accept's default InputMap is Enter/Space/gamepad A - no mouse or
	# touch binding, and Android's touch-emulates-mouse produces an
	# InputEventMouseButton, not an action press, so a touch player needs
	# either the prompt's buttons or this fallback to retry at all.
	var is_tap: bool = (
		(retry_prompt == null or not retry_prompt.visible)
		and (
			event is InputEventScreenTouch
			or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
		)
	)

	if not (event.is_action(&"ui_accept") or is_tap):
		return

	_retrying = true
	animation_player.play(&"retry")
	if music:
		music.stop()
	await animation_player.animation_finished
	if is_inside_tree():
		# Through SceneChanger, not get_tree() directly: the reload itself is
		# identical, but the raw call is invisible to the five autoloads that
		# listen for a scene change - which is why the pendulum hitbox came
		# back on the top strip after a retry however the Mobile row was set.
		SceneChanger.reload_current()


func activate_gameover() -> void :
	if disable_for_skipping:
		return

	is_game_over = true
	LullabyGameoverModule.has_died = true

	if clock and clock.animation_player:
		clock.animation_player.pause()

	if not animation_player:
		printerr("Needs animation player to play gameover cutscene!")
		return

	if skip_intro:
		animation_player.play(&"game_over_skip")
	else:
		animation_player.play(&"game_over")

	await animation_player.animation_finished

	if music:
		music.play()

	activated = true

	if not baby_mode_enabled or not baby_mode_speaker:
		return

	baby_mode_speaker.stream = baby_mode_lines.pick_random()
	baby_mode_speaker.play()


## Same destination and the same has_died reset the pause menu's Exit does
## (kalos_pause_menu.gd), so dying and quitting leaves the shop in the state
## quitting from the pause menu would have. end_manually is true because the
## shop drives its own PreloadCamera3D before handing the screen over.
##
## Unlike the retry above this does not play the retry animation first: that
## animation exists to cover a reload of this same scene, and there is
## nothing to cover when the loading screen is about to take over anyway.
func exit_to_shop() -> void :
	if music:
		music.stop()
	LullabyGameoverModule.has_died = false
	SceneChanger.change_to("res://lullaby_mod/rooms/env_collector_shop.tscn", &"hypno", true)
