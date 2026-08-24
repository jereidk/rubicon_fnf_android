extends Node


@export var animation_player: AnimationPlayer

## Set the moment a way out of the credits is taken, so the second half of
## one press cannot take it again.
##
## _input() below used is_action(), which matches a release as well as a
## press, and every synthetic action in this project arrives as both: OK on
## the touch overlay, the virtual dpad and Android's hardware Back all
## dispatch a press and then a release one frame later. So a single tap
## called SceneChanger.change_to() twice - the same double call that
## orphaned a loading screen over Monochrome after a retry, since the second
## one reassigns _current_loader while the first screen is still parented to
## a CanvasLayer at layer 128.
##
## SceneChanger refuses a re-entrant change now, so this can no longer soft
## lock on its own. Guarded here too because the skip should be one press
## either way, and because the animation_finished branches below can race
## the same call.
var _leaving: bool = false


func _on_animation_finished(anim_name: StringName) -> void :
	var play_angel: = not SaveData.get_flag(&"credits_scroll_seen")
	match anim_name:
		&"scene":
			if play_angel:
				animation_player.play(&"angel")
				animation_player.seek(0.0, true)
				return

			_leave()

		&"angel":
			SaveData.set_flag(&"credits_scroll_seen", true)
			SaveData.save()
			_leave()


## The same way out, as something a finger can hit.
##
## The skip existed and was unreachable on the port: `ui_accept` is Enter, Space
## and the gamepad's A, and this screen ships no touch control at all - so on a
## phone the credits could only be sat through, every single time the three
## songs were cleared.
##
## Available from the moment the credits appear, on every viewing.
##
## It used to be gated - like the keyboard path still was - on
## `credits_scroll_seen`, i.e. only from the second viewing onward. That rule
## cannot survive the change next to it: the credits now play themselves exactly
## once, so a skip offered only on the second viewing is a skip nobody is ever
## offered.
@export var skip_button: BaseButton

## Marks the credits as having appeared, which is what stops them repeating.
##
## Written here rather than at the end, because every other exit is real: the
## player backs out, closes the app, or skips. `credits_scroll_seen` keeps its
## own meaning - watched all the way through the angel - and four other places
## still read it for that.
func _ready() -> void :
	if not SaveData.get_flag(&"credits_shown"):
		SaveData.set_flag(&"credits_shown", true)
		SaveData.save()

	if skip_button != null:
		skip_button.text = tr("Skip")

func _on_skip_pressed() -> void :
	_leave()

func _input(event: InputEvent) -> void :
	if _leaving or not event.is_pressed() or event.is_echo():
		return

	if event.is_action(&"ui_accept"):
		_leave()


func _leave() -> void :
	if _leaving:
		return

	_leaving = true
	SceneChanger.change_to("uid://bqkjiwokrcvo", &"hypno", true)
