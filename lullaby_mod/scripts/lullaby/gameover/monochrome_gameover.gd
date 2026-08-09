extends Node2D
class_name MonochromeGameover

static var skip_first_part: bool = true;

@export var animation_player: AnimationPlayer;
@export var boyfriend_scene: Node2D;


@export var baby_mode_speaker: AudioStreamPlayer
@export var baby_mode_lines: Array[AudioStream]

## One tap is two events on Android: emulate_mouse_from_touch is on by
## default, so a finger produces an InputEventScreenTouch AND an emulated
## InputEventMouseButton, and the is_tap test below accepts both. Without
## this guard _input() ran twice, both copies awaited the same
## animation_finished, and both resumed on the same emission - calling
## SceneChanger.change_to() twice in one frame. The second call overwrites
## _current_loader while the first loading screen is still parented to a
## CanvasLayer at layer 128, so the song restarted and played correctly
## underneath a black loading screen that nothing owned any more. That is
## the bug in the screenshot.
##
## Safety Lullaby had the same hole and it is not visible there, which is
## why only Monochrome was reported: its live module retries with
## reload_current_scene() instead of going through SceneChanger, so a double
## tap queued two reloads rather than orphaning a loading screen. Guarded
## too, in safety_lullaby_gameover_module.gd. (The transitioning guard in
## safety_lullaby_gameover.gd protects nothing - nothing instances that
## script; see the module's own docstring.)
var _transitioning: bool = false

## Whether a retry would be accepted right now. Read by
## LullabyGameoverPrompt so the on-screen button appears exactly when the
## screen is listening, and disappears the moment it stops - the same
## condition _input() below tests, rather than a second copy of it that
## could drift.
var can_retry: bool:
	get:
		return not _transitioning and boyfriend_scene != null and boyfriend_scene.visible

## The prompt's own buttons, so a tap that lands on one is not ALSO read as
## the tap-anywhere retry below.
##
## Tap-anywhere has to keep working when the prompt is not up, or a broken
## prompt would leave a touch player with no way off this screen at all -
## which is a real risk here, since a GDScript type error fails a whole
## script silently and the node then runs with none. But while the prompt IS
## up, the buttons are the affordance, and tap-anywhere would out-race them:
## _input() is delivered before GUI, so tapping EXIT would fire the retry
## before the button's pressed signal ever reached exit().
@export var retry_prompt: LullabyGameoverPrompt

func _ready() -> void :
	if skip_first_part:
		animation_player.play(&"over_loop")
	else:
		animation_player.play(&"over_start")

func _on_animation_changed(_old: StringName, new: StringName) -> void :
	if new == &"over_loop" and Settings.lullaby_baby_mode and baby_mode_speaker:
		baby_mode_speaker.stream = baby_mode_lines.pick_random()
		baby_mode_speaker.play()

func _input(event: InputEvent) -> void :
	if not can_retry or event.is_echo() or not event.is_pressed():
		return

	# ui_cancel is Esc, gamepad B and Android's hardware Back button. Checked
	# before the tap fallback because leaving is the destructive choice of
	# the two and must never be mistaken for a retry.
	if event.is_action(&"ui_cancel"):
		_transitioning = true
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

	if event.is_action(&"ui_accept") or is_tap:
		_transitioning = true
		animation_player.play(&"over_confirm")
		await animation_player.animation_finished

		SceneChanger.change_to(&"uid://dfflo57l50r1f", &"hypno")

## Same destination and the same has_died reset the pause menu's Exit does
## (gb_pause_menu.gd), so dying and quitting leaves the shop in the state
## quitting from the pause menu would have. end_manually is true because the
## shop drives its own PreloadCamera3D before handing the screen over.
func exit_to_shop() -> void :
	LullabyGameoverModule.has_died = false
	SceneChanger.change_to("res://lullaby_mod/rooms/env_collector_shop.tscn", &"hypno", true)
