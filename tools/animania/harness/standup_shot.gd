# Shoots tadano-stand's two earliest FocusCamera moments after standUP() (beat 232), which
# is where a camera bug that only ever shows up post-stand-up would be caught: the chart's
# first `char=0` focus after the swap (97.89s) and its second (110.53s), both settled 4s in.
#
# Written to verify a fix, not to explore: `STAND_CAST`'s camera offsets in
# build_level_scene.gd were being scaled by FUNKIN_TO_RUBICON, which is the same "world
# offsets stay verbatim, the 1.5 lives on the camera" bug this project has hit before -
# tadano's stand point landed 100px right of where his own cameraOffsets put it, framing
# empty stage instead of him.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/standup_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const MOMENTS := [101.9, 114.6]
const WIND_SPEED := 20.0

var _level: Node
var _clock: Node
var _frames: int = 0
var _index: int = 0
var _step: int = 0

func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true

func _wind_step(target: float) -> bool:
	var player: AnimationPlayer = _clock.animation_player
	if player.current_animation_position >= target:
		player.speed_scale = 1.0
		return true
	player.speed_scale = WIND_SPEED
	return false

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	if _index >= MOMENTS.size():
		get_tree().quit()
		return
	_clock = _level.get_node("RubiconLevelClock")
	match _step:
		0:
			if _wind_step(MOMENTS[_index]):
				_step = 1
		1:
			for running: Tween in get_tree().get_processed_tweens():
				running.custom_step(10.0)
				running.kill()
			var camera: Camera2D = get_viewport().get_camera_2d()
			camera.zoom = camera.zoom_interpolate_target
			camera.position = camera.position_interpolate_target
			_step = 2
		2:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "user://standup_%03d.png" % int(MOMENTS[_index] * 10)
			image.save_png(path)
			print("OUT t=%.1f -> %s" % [MOMENTS[_index], ProjectSettings.globalize_path(path)])
			_index += 1
			_step = 0
