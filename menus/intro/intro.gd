class_name GameIntro
extends Control

## Real port of Lullaby's game_intro.gd (scripts/lullaby/game_intro.gd in
## the decompiled recovery). skip_intro is a static var so other scenes can
## flip GameIntro.skip_intro = true and have the intro jump straight to the
## cabin on next load, matching the original's fast-forward behavior.
## Entering the door plays the camera's "go_in" zoom, then go_into_shop()
## hands off to the Cabinet of Novelties (env_collector_shop.tscn).

const SKIPPABLE_AT_SEC := 9.9
const SKIP_AT_SEC := 20.0
const SHOP_SCENE := "uid://bqkjiwokrcvo"

static var skip_intro: bool = false

@export var root_anim_player: AnimationPlayer
@export var camera_anim_player: AnimationPlayer
@export var door_button: Button

@onready var intro_player: AudioStreamPlayer = %IntroPlayer
@onready var initial_timer: Timer = %InitialTimer

@export var intro_skipped: bool = false

@export var skip_button: Button

func _ready() -> void:
	if skip_button:
		skip_button.pressed.connect(skipintro)
		skip_button.visible = not skip_intro
	if skip_intro:
		initial_timer.stop()

		root_anim_player.play(&"intro")
		root_anim_player.seek(SKIP_AT_SEC, true)

		var interactive: AudioStreamInteractive = intro_player.stream
		interactive.initial_clip = 1
		intro_player.play()

func _input(event: InputEvent) -> void:
	var confirm_pressed: bool = _is_confirm_press(event)

	if confirm_pressed:
		if root_anim_player.current_animation == &"intro" and not intro_skipped:
			skipintro()

	if (not door_button) or (not door_button.visible):
		return

	if confirm_pressed:
		click_door()

## Treat a click the same as ui_accept, mirroring the broad "press enter"
## affordance the EnterLabel/DoorButton prompt implies. Touch players use
## the menu touch overlay's Accept button for the same action.
func _is_confirm_press(event: InputEvent) -> bool:
	if event.is_action(&"ui_accept") and event.is_pressed():
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false

func skipintro() -> void:
	if intro_skipped:
		return

	intro_skipped = true
	initial_timer.stop()
	if skip_button:
		skip_button.visible = false

	root_anim_player.play(&"intro")
	root_anim_player.seek(SKIPPABLE_AT_SEC, true)

	var interactive: AudioStreamInteractive = intro_player.stream
	interactive.initial_clip = 1
	intro_player.play()

var _door_entered := false

func click_door() -> void:
	if _door_entered:
		return
	_door_entered = true

	root_anim_player.pause()
	camera_anim_player.play(&"go_in")

	if SaveData.get_flag(&"splash_seen"):
		SaveData.set_flag(&"splash_seen", true)
		SaveData.save()

func go_into_shop() -> void:
	SceneChanger.change_to(SHOP_SCENE, &"hypno", true)

func _on_initial_timer_timeout() -> void:
	root_anim_player.play(&"intro")

func _on_camera_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"go_in":
		go_into_shop()
