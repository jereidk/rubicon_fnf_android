extends ColorRect
class_name RubiconLoadingScreen

## Port of Lullaby's lullaby_loading_screen.gd base behavior: a full-screen
## overlay with an "open"/"close" animation pair and a progress bar driven
## by progress_updated, used by SceneChanger between every state change.

@export var animation_start: StringName = &"open"
@export var animation_end: StringName = &"close"
@export var animation_player: AnimationPlayer

signal progress_updated(value: float)

func play_open() -> void:
	if animation_player == null or not animation_player.has_animation(animation_start):
		return
	animation_player.play(animation_start)
	await animation_player.animation_finished

func play_close() -> void:
	if animation_player == null or not animation_player.has_animation(animation_end):
		return
	animation_player.play(animation_end)
	await animation_player.animation_finished

func set_progress(value: float) -> void:
	progress_updated.emit(value)
