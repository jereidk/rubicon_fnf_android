# Renders songs/resonance/resonance.tscn mid-song: stage, characters, strumlines, notes,
# health bar and judgment, all at once.
#
# Same technique as tools/animania/harness/level_shot.gd (clock wound + played).
#
# RENDER FIX:
#   The RubiconInterpolatedCamera2D is a normal Camera2D — it only lerps its
#   position/rotation/zoom toward *_interpolate_target in _process; it never
#   overwrites the viewport canvas_transform. When the level enters the tree and
#   the interp camera is the only camera, Godot automatically makes it current,
#   exactly like phone-call. So we keep it in the tree and settle it onto its
#   interpolate targets right before capture, exactly like the animania harness.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/level_shot.tscn
extends Node2D

const LEVEL := "res://songs/resonance/resonance.tscn"
# Moments with notes on both sides across the song (resonance is 171.3s long).
const MOMENTS := [
	[10.0, 1.6], [45.0, 1.6], [65.0, 1.6], [90.0, 1.6], [120.0, 1.6], [150.0, 1.6],
]
const WIND_SPEED := 20.0
const SHOT_DIR := "/tmp/hq_renders"

var _level: Node
var _clock: Node
var _frames: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_level = load(LEVEL).instantiate()
	add_child(_level)
	_clock = _level.get_node("RubiconLevelClock")
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _wind_step(target: float) -> bool:
	var player: AnimationPlayer = _clock.animation_player
	if player.current_animation_position >= target:
		player.speed_scale = 1.0
		return true
	player.speed_scale = WIND_SPEED
	return false


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

	var moment: float = (MOMENTS[_index] as Array)[0]
	var play_in: float = (MOMENTS[_index] as Array)[1]
	var clock: AnimationPlayer = _clock.animation_player

	match _step:
		Step.WIND:
			if _wind_step(moment - play_in):
				_step = Step.PLAY

		Step.PLAY:
			if clock.current_animation_position >= moment:
				_step = Step.SETTLE

		Step.SETTLE:
			# Drain every tween to its end value, the way a real playthrough is
			# by now (mirrors the animania harness).
			for running: Tween in get_tree().get_processed_tweens():
				running.custom_step(10.0)
				running.kill()

			# Settle the interp camera onto its interpolate targets before the
			# capture frame, exactly like animania phone-call. This is where a
			# real playthrough sits between bops, and it has to happen on the
			# frame BEFORE the capture: get_texture() returns what was last
			# rendered.
			var camera: Camera2D = get_viewport().get_camera_2d()
			if camera:
				camera.zoom = camera.zoom_interpolate_target
				camera.position = camera.position_interpolate_target

			# One splash nudge per lane so a working effect is not absent.
			for side: String in ["Opponent", "Player"]:
				for lane: Node in _level.get_node("UILayer/UI/%s" % side).get_children():
					if lane.has_signal(&"just_pressed") and lane.results.size() > 0:
						lane.just_pressed.emit()
			_step = Step.SHOOT

		Step.SHOOT:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "%s/resonance_%03d.png" % [SHOT_DIR, int(moment)]
			image.save_png(path)

			var stage: Node = _level.get_node_or_null("Stage")
			var cam: Camera2D = get_viewport().get_camera_2d()
			var cam_info: String = "none"
			if cam:
				cam_info = "pos=%s zoom=%s" % [cam.position, cam.zoom]
			print("OUT t=%5.1fs cam=%s stage_visible=%s stage_mod=%s -> %s" % [
				moment, cam_info,
				stage.visible if stage else "n/a",
				stage.modulate if stage else "n/a",
				path])

			_index += 1
			_step = Step.WIND
