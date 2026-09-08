# Renders songs/resonance/resonance.tscn mid-song: stage, characters (sayaka,
# gf, boyfriend), strumlines, notes, health bar and judgment.
#
# Same technique as tools/animania/harness/level_shot.gd: the clock's animation
# is WOUND at high speed to a moment and then PLAYED into it, so method keys
# fire exactly once in order.
#
# FIX: The RubiconInterpolatedCamera2D overrides canvas_transform every frame
# via its _process, preventing our manual canvas_transform from taking effect.
# Disable it and use the viewport's canvas_transform directly.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/level_shot.tscn
extends Node2D

const LEVEL := "res://songs/resonance/resonance.tscn"
# Moments with notes on both sides across the song (resonance is 165.6s long).
const MOMENTS := [
	[10.0, 0.8], [45.0, 0.8], [65.0, 0.8], [90.0, 0.8], [120.0, 0.8], [150.0, 0.8],
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

	# The RubiconInterpolatedCamera2D._set() override prevents both
	# enabled=false and making it non-current, and its _process overrides
	# canvas_transform every frame. Remove it entirely so the viewport uses
	# no camera and we drive canvas_transform ourselves.
	var interp: Camera2D = _level.get_node_or_null("RubiconInterpolatedCamera2D")
	if interp:
		interp.set_process(false)
		interp.queue_free()
		# Give the node a frame to be freed before the first render.
		await get_tree().process_frame
		print("level_shot: queued RubiconInterpolatedCamera2D for removal")
	# Ensure the viewport has NO current camera so our canvas_transform rules.
	var existing: Camera2D = get_viewport().get_camera_2d()
	if existing:
		existing.enabled = false
	print("level_shot: removed camera, canvas_transform will be driven manually")


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
			for running: Tween in get_tree().get_processed_tweens():
				running.custom_step(10.0)
				running.kill()

			# Read the interpolated camera's target position/zoom.
			var interpolated: Camera2D = _level.get_node_or_null("RubiconInterpolatedCamera2D")
			if interpolated:
				var cam_pos: Vector2 = interpolated.position_interpolate_target
				var cam_zoom: Vector2 = interpolated.zoom_interpolate_target
				# Build the canvas transform manually.
				var vp_size := Vector2(get_viewport().get_visible_rect().size)
				var half := vp_size / (2.0 * cam_zoom)
				var origin := cam_pos - half
				get_viewport().canvas_transform = Transform2D(Vector2(cam_zoom.x, 0.0), Vector2(0.0, cam_zoom.y), origin)

			for side: String in ["Opponent", "Player"]:
				for lane: Node in _level.get_node("UILayer/UI/%s" % side).get_children():
					if lane.has_signal(&"just_pressed") and lane.results.size() > 0:
						lane.just_pressed.emit()
			_step = Step.SHOOT

		Step.SHOOT:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "%s/resonance_%03d.png" % [SHOT_DIR, int(moment)]
			image.save_png(path)

			var setter: Node = _level.get_node("RubiconInterpolatedCamera2D/RubiconPositionSetter")
			var point: String = setter._current_point
			var stage: Node = _level.get_node("Stage")
			var vp_size := Vector2(get_viewport().get_visible_rect().size)
			print("OUT t=%5.1fs cam=%s vp=%s sayaka=%s gf=%s bf=%s lanes=%d/%d -> %s" % [
				moment, point, vp_size,
				stage.get_node("Sayaka").position,
				stage.get_node("Girlfriend").position,
				stage.get_node("Boyfriend").position,
				_level.get_node("UILayer/UI/Opponent").get_child_count(),
				_level.get_node("UILayer/UI/Player").get_child_count(),
				path])

			_index += 1
			_step = Step.WIND
