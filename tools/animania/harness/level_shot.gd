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
const MOMENTS := [6.0, 45.0, 66.5, 88.4, 91.0, 92.5, 131.5]

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


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return

	# Three frames per moment: seek, settle, shoot. The settle frame matters - the notes
	# and the camera both interpolate, and shooting on the seek frame catches neither.
	var index: int = (_frames - 4) / 3
	if index >= MOMENTS.size():
		get_tree().quit()
		return

	var step: int = (_frames - 4) % 3
	if step == 0:
		_wind_to(MOMENTS[index])
	elif step == 1:
		# Winding fires every camera bop and AddCameraZoom punch on the way without any
		# real time passing for them to decay in, so they stack - the first version of this
		# shot came out at zoom 2.03 against a base of 0.975. Settling the camera onto its
		# interpolate target is where a real playthrough sits between bops. It has to
		# happen on the frame BEFORE the capture: get_texture() returns what was last
		# rendered, so settling on the capture frame would be a frame too late.
		var camera: Camera2D = get_viewport().get_camera_2d()
		camera.zoom = camera.zoom_interpolate_target
		camera.position = camera.position_interpolate_target

		# Nudge every lane once so the shot has splashes in it. They last four frames at
		# 24fps and a still frame almost never lands on one otherwise, which makes an
		# effect that IS working look absent.
		for side: String in ["Opponent", "Player"]:
			for lane: Node in _level.get_node("UILayer/UI/%s" % side).get_children():
				if lane.has_signal(&"just_pressed") and lane.results.size() > 0:
					lane.just_pressed.emit()
	elif step == 2:
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://level_%03d.png" % int(MOMENTS[index])
		image.save_png(path)
		var tadano: Node = _level.find_child("Tadano", true, false)
		var bars: ColorRect = _level.get_node("CinematicBars/Top")
		print("OUT t=%5.1fs  barras=%3.0fpx  tadano=%-14s zoom=%.3f -> %s" % [
			MOMENTS[index], bars.size.y, tadano.animations[&"sing_left"],
			(get_viewport().get_camera_2d() as Camera2D).zoom.x,
			ProjectSettings.globalize_path(path)])
