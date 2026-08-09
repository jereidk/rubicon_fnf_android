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

	# ui_accept's default InputMap is Enter/Space/gamepad A - no mouse or
	# touch binding, and Android's touch-emulates-mouse produces an
	# InputEventMouseButton, not an action press - see
	# safety_lullaby_gameover.gd's identical fix for the fuller story.
	var is_tap: bool = (
		event is InputEventScreenTouch
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	)

	if event.is_action(&"ui_accept") or is_tap:
		_transitioning = true
		animation_player.play(&"over_confirm")
		await animation_player.animation_finished

		SceneChanger.change_to(&"uid://dfflo57l50r1f", &"hypno")
