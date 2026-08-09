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

	# ui_accept's default InputMap is Enter/Space/gamepad A - no mouse or
	# touch binding, and Android's touch-emulates-mouse produces an
	# InputEventMouseButton, not an action press - see
	# monochrome_gameover.gd's identical fix for the fuller story.
	var is_tap: bool = (
		event is InputEventScreenTouch
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	)

	if not (event.is_action(&"ui_accept") or is_tap):
		return

	_retrying = true
	animation_player.play(&"retry")
	if music:
		music.stop()
	await animation_player.animation_finished
	if is_inside_tree():
		get_tree().reload_current_scene()


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
