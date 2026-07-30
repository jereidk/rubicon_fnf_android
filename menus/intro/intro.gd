extends Control

## Port of Lullaby's game_intro.gd. The original is compiled bytecode we
## can't recover, so this reimplements the behavior its exported
## properties and animation tracks describe: a 20s painted intro
## ("intro" animation on root_anim_player, cycling the OpeningShot ->
## EngineShot -> CabinShot tabs), which becomes skippable partway through,
## ending on the cabin with "Press Enter to start". Entering plays the
## camera's "go_in" zoom into the door, then hands off to whatever comes
## after the intro.
##
## The Cabinet of Novelties intro/shop that follows in the real mod isn't
## built yet, so this currently lands on the main menu placeholder.

const NEXT_SCENE := "res://menus/main/main_menu.tscn"
const SKIPPABLE_AT_SEC := 9.9

@export var root_anim_player: AnimationPlayer
@export var camera_anim_player: AnimationPlayer
@export var door_button: Button

@onready var enter_label: Label = $EnterLabel

var intro_skipped := false
var _entered := false

func _on_initial_timer_timeout() -> void:
	root_anim_player.play("intro")

func _process(_delta: float) -> void:
	if root_anim_player.is_playing() and root_anim_player.current_animation == "intro":
		intro_skipped = root_anim_player.current_animation_position >= SKIPPABLE_AT_SEC

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return

	if enter_label.visible:
		click_door()
		get_viewport().set_input_as_handled()
	elif intro_skipped and root_anim_player.current_animation == "intro":
		root_anim_player.seek(root_anim_player.current_animation_length, true)
		get_viewport().set_input_as_handled()

func click_door() -> void:
	if _entered:
		return
	_entered = true
	camera_anim_player.play("go_in")

func _on_camera_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"go_in":
		SceneChanger.change_scene(NEXT_SCENE)
