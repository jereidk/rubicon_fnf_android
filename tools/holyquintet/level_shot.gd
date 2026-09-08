# Renders songs/resonance/resonance.tscn mid-song: stage, characters (sayaka,
# gf, boyfriend), strumlines, notes, health bar and judgment.
#
# Same technique as tools/animania/harness/level_shot.gd.
#
# FIX: The RubiconInterpolatedCamera2D._set() override returns false for ALL
# properties including 'current', preventing proper viewport camera setup.
# Its _process (NOTIFICATION_INTERNAL_PROCESS) runs regardless of set_process()
# and overwrites canvas_transform every frame.
#
# Solution: remove the camera from the scene tree BEFORE it gets a chance to
# process, then drive canvas_transform manually from its targets.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/level_shot.tscn
extends Node2D

const LEVEL := "res://songs/resonance/resonance.tscn"
const MOMENTS := [
	[10.0, 0.8], [45.0, 0.8], [65.0, 0.8], [90.0, 0.8], [120.0, 0.8], [150.0, 0.8],
]
const WIND_SPEED := 20.0
const SHOT_DIR := "/tmp/hq_renders"

var _level: Node
var _clock: Node
var _interp_pos: Vector2
var _interp_zoom: Vector2
var _frames: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_level = load(LEVEL).instantiate()

	# Remove the RubiconInterpolatedCamera2D BEFORE adding the level to the
	# tree so it never gets a chance to run _process and override viewport
	# canvas_transform.  Cache its targets first.
	var interp := _level.get_node_or_null("RubiconInterpolatedCamera2D") as Camera2D
	if interp:
		_interp_pos = interp.position_interpolate_target
		_interp_zoom = interp.zoom_interpolate_target
		interp.get_parent().remove_child(interp)
		interp.queue_free()
		print("level_shot: removed RubiconInterpolatedCamera2D")

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
			for running: Tween in get_tree().get_processed_tweens():
				running.custom_step(10.0)
				running.kill()

			# The PositionSetter may have updated _interp_pos via animation keys.
			# Re-read from the cached values which track the animation's state.
			var setter := _level.get_node_or_null(
				"RubiconInterpolatedCamera2D/RubiconPositionSetter")
			if setter:
				# The setter stores targets internally; read back the camera's
				# last-known targets from the animation's current_point.
				var point_name: StringName = setter._current_point
				var point_map: Dictionary = setter.point_map
				if point_map.has(point_name) and point_map[point_name] != null:
					var target_node: Node = point_map[point_name]
					# Build global position by walking up the tree.
					var global_pos: Vector2 = target_node.position
					var parent := target_node.get_parent()
					while parent != null and parent != _level:
						if parent is Parallax2D or parent is ParallaxBackground:
							break
						if "position" in parent:
							global_pos += parent.position
						parent = parent.get_parent()
					_interp_pos = global_pos

			# Apply canvas transform.
			var vp_size := Vector2(get_viewport().get_visible_rect().size)
			var half := vp_size / (2.0 * _interp_zoom)
			var origin := _interp_pos - half
			get_viewport().canvas_transform = Transform2D(
				Vector2(_interp_zoom.x, 0.0), Vector2(0.0, _interp_zoom.y), origin)

			for side: String in ["Opponent", "Player"]:
				for lane: Node in _level.get_node("UILayer/UI/%s" % side).get_children():
					if lane.has_signal(&"just_pressed") and lane.results.size() > 0:
						lane.just_pressed.emit()
			_step = Step.SHOOT

		Step.SHOOT:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "%s/resonance_%03d.png" % [SHOT_DIR, int(moment)]
			image.save_png(path)

			var stage: Node = _level.get_node("Stage")
			print("OUT t=%5.1fs zoom=%.3f sayaka=%s gf=%s bf=%s lanes=%d/%d -> %s" % [
				moment, _interp_zoom.x,
				stage.get_node("Sayaka").position,
				stage.get_node("Girlfriend").position,
				stage.get_node("Boyfriend").position,
				_level.get_node("UILayer/UI/Opponent").get_child_count(),
				_level.get_node("UILayer/UI/Player").get_child_count(),
				path])

			_index += 1
			_step = Step.WIND
