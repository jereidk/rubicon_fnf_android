# Renders one moment of phone-call over a GRID of camera positions, so a screenshot of the
# original can be matched against the port by search instead of by formula.
#
# Why search: the stage's layers each have their own scroll factor, so a camera error does
# NOT translate the picture - every layer moves by a different amount. Sliding one image
# over the other can never line up more than one layer at a time, and Godot's Parallax2D
# and Flixel's scrollFactor do not agree closely enough to invert on paper. Re-rendering at
# a candidate camera and scoring the whole frame does agree, because it is the same
# renderer that produced the port.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/camera_sweep.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const MOMENT := 9.2
const PLAY_IN := 1.6
const WIND_STEP := 0.5

# Coarse grid, in Funkin world pixels, around the camera the port currently uses.
const DX := [-60.0, -30.0, 0.0, 30.0]
const DY := [-60.0, -30.0, 0.0, 30.0]

## What the grid moves: "camera" or "tadano". When it is tadano, the camera is held at its
## own target plus CAMERA_FIX - the correction the camera sweep already measured - so his
## offset is read against a frame that is otherwise right.
const SWEEP := "camera"
const CAMERA_FIX := Vector2(0.0, 0.0)

var _level: Node
var _clock: Node
var _frames: int = 0
var _step: int = 0
var _base: Vector2
var _index: int = 0
var _home: Vector2


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	_clock = _level.get_node("RubiconLevelClock")
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _wind_step(target: float) -> bool:
	var player: AnimationPlayer = _clock.animation_player
	var at: float = player.current_animation_position
	if at >= target:
		return true
	player.seek(minf(at + WIND_STEP, target), true)
	return player.current_animation_position >= target


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	var clock: AnimationPlayer = _clock.animation_player
	var camera: Camera2D = get_viewport().get_camera_2d()
	match _step:
		0:
			if _wind_step(MOMENT - PLAY_IN):
				_step = 1
		1:
			if clock.current_animation_position >= MOMENT:
				_step = 2
		2:
			# The clock is left where it is from here on: the animation player would keep
			# writing `position` every frame otherwise, and the whole point is to hold a
			# camera the sweep chose.
			clock.pause()
			camera.zoom = camera.zoom_interpolate_target
			_base = camera.position_interpolate_target
			# The opening is all TWEENS, which run on frames and not on the clock, so a
			# wound harness catches them mid-flight: tadano halfway through his walk-in,
			# and the tween writing his x back every frame over anything the harness sets
			# - which cost a measurement round, since he came out 360px right of where he
			# had been put and it read as a placement error.
			#
			# Run them out rather than kill them. custom_step lands every one of them on
			# its end value, which is where a real playthrough is by 9.2s; killing them
			# freezes them wherever they are, and the first version of this left the title
			# card sitting at alpha 1 over the whole stage.
			for running: Tween in get_tree().get_processed_tweens():
				running.custom_step(10.0)
			var tadano: Node2D = _level.get_node("Stage/Tadano")
			print("tadano en %s, camara real %s, objetivo %s, zoom %.4f" % [
				tadano.position, camera.position, _base, camera.zoom.x])
			tadano.position.x = 50.0
			_home = tadano.position
			_step = 3
		3:
			var dx: float = DX[_index % DX.size()]
			var dy: float = DY[_index / DX.size()]
			var shift: Vector2 = Vector2(dx, dy)
			camera.position = _base + (CAMERA_FIX if SWEEP == "tadano" else shift)
			camera.position_interpolate_target = camera.position
			camera.position_interpolate_offset = Vector2.ZERO
			if SWEEP == "tadano":
				var who: Node2D = _level.get_node("Stage/Tadano")
				who.position = _home + shift
			_step = 4
		4:
			# get_texture() returns what was last rendered, so the shot is a frame late.
			var image: Image = get_viewport().get_texture().get_image()
			image.save_png("user://sweep_%03d.png" % _index)
			_index += 1
			if _index >= DX.size() * DY.size():
				print("listo: %d capturas" % _index)
				get_tree().quit()
				return
			_step = 3
