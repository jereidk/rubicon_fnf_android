# Renders songs/phone-call/phone_call.tscn mid-song: stage, characters, strumlines, notes,
# health bar and judgment, all at once.
#
# The clock reads its time off RubiconLevelClock/AnimationPlayer, so this seeks straight to
# a moment with notes on screen instead of waiting for the song to get there.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/level_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
# Moments the chart's camera events make interesting: the opening letterbox at 100px, the
# widest bars of the song, the tightest, and the ending - plus a plain mid-song frame.
const MOMENTS := [6.0, 45.0, 66.5, 88.4, 92.5, 95.0, 133.0]

## How long the clock is left to PLAY before a shot, rather than wound to it.
##
## Winding fires a method key only when the seek lands close after it, and when two keys sit
## close together it fires only the nearest - the chart's endAnimation and endConv are 24.6ms
## apart at 132.2s, and a wound clock plays the second and skips the first. Letting the last
## stretch play normally is what makes a shot show what the song actually does.
const PLAY_IN := 1.6

var _level: Node
var _clock: Node
var _frames: int = 0

## Method-track keys are not reliably fired by seeking - a seek only runs a key if it lands
## close after it (measured: from 65.0, a 1.0s jump fires the key at 65.477 and a 2.0s jump
## does not). So the camera bops, the letterbox state and tadano's alt pose set only exist
## in a shot if the clock is WALKED to the moment rather than dropped on it.
const WIND_STEP := 0.5


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	_clock = _level.get_node("RubiconLevelClock")
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _wind_to(target: float) -> void:
	var player: AnimationPlayer = _clock.animation_player
	var at: float = player.current_animation_position
	while at < target:
		at = minf(at + WIND_STEP, target)
		player.seek(at, true)


enum Step { WIND, PLAY, SETTLE, SHOOT }

var _step: Step = Step.WIND
var _index: int = 0


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return

	if _index >= MOMENTS.size():
		get_tree().quit()
		return

	var moment: float = MOMENTS[_index]
	var clock: AnimationPlayer = _clock.animation_player

	match _step:
		Step.WIND:
			_wind_to(moment - PLAY_IN)
			_step = Step.PLAY

		Step.PLAY:
			# Played, not wound. Winding fires a method key only when the seek lands close
			# after it, and when two keys sit close together it fires only the nearest -
			# the chart's endAnimation and endConv are 24.6ms apart at 132.2s, and a wound
			# clock plays the second and skips the first.
			if clock.current_animation_position >= moment:
				_step = Step.SETTLE

		Step.SETTLE:
			# Winding fires every camera bop and AddCameraZoom punch on the way with no real
			# time for them to decay in, so they stack - the first version of this came out
			# at zoom 2.03 against a base of 0.975. Settling onto the interpolate target is
			# where a real playthrough sits between bops, and it has to happen on the frame
			# BEFORE the capture: get_texture() returns what was last rendered.
			var camera: Camera2D = get_viewport().get_camera_2d()
			camera.zoom = camera.zoom_interpolate_target
			camera.position = camera.position_interpolate_target

			# A splash lasts four frames at 24fps and a still almost never lands on one,
			# which makes a working effect look absent. One nudge per lane fixes that.
			for side: String in ["Opponent", "Player"]:
				for lane: Node in _level.get_node("UILayer/UI/%s" % side).get_children():
					if lane.has_signal(&"just_pressed") and lane.results.size() > 0:
						lane.just_pressed.emit()
			_step = Step.SHOOT

		Step.SHOOT:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "user://level_%03d.png" % int(moment)
			image.save_png(path)

			var stood_up: bool = _level.get_node("PhoneCallEvents")._stood_up
			var bars: ColorRect = _level.get_node("CinematicBars/Top")
			print("OUT t=%5.1fs  barras=%3.0fpx  de pie=%-3s zoom=%.3f -> %s" % [
				moment, bars.size.y, "si" if stood_up else "no",
				(get_viewport().get_camera_2d() as Camera2D).zoom.x,
				ProjectSettings.globalize_path(path)])

			_index += 1
			_step = Step.WIND
