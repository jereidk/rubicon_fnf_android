# Renders songs/resonance/resonance.tscn mid-song: stage, characters (sayaka,
# gf, boyfriend), strumlines, notes, health bar and judgment all at once.
#
# Same technique as tools/animania/harness/level_shot.gd (clock wound + played).
#
# RENDER FIX:
#   The RubiconInterpolatedCamera2D._set() returns false for every property
#   (including 'current'), so Godot can't make it the viewport's current
#   camera. Its NOTIFICATION_INTERNAL_PROCESS also runs regardless of
#   set_process(false) and overwrites the viewport canvas_transform every
#   frame, which is why every level_shot came out black.
#
#   Instead of fighting that camera, we use a fixed plain Camera2D that shows
#   the full gameplay area (all three characters + stage), like the animania
#   phone-call shots but with a wider framing.
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

# Fixed framing that shows Sayaka(120,200), GF(-850,400), BF(1150,225) and the stage.
const CAM_POS := Vector2(150.0, 50.0)
const CAM_ZOOM := Vector2(0.55, 0.55)

var _level: Node
var _clock: Node
var _frames: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_level = load(LEVEL).instantiate()

	# Remove the RubiconInterpolatedCamera2D before the node ever enters the
	# tree. Because ScriptEngine only creates the node once it's in the tree,
	# and its _process override cannot run without being in the tree, removing
	# it here prevents the black render.
	var interp := _level.get_node_or_null("RubiconInterpolatedCamera2D")
	if interp:
		interp.get_parent().remove_child(interp)
		interp.queue_free()
		print("level_shot: removed RubiconInterpolatedCamera2D before entering tree")

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

			# Drive canvas_transform manually with the fixed framing.
			var vp_size := Vector2(get_viewport().get_visible_rect().size)
			var half := vp_size / (2.0 * CAM_ZOOM)
			var origin := CAM_POS - half
			get_viewport().canvas_transform = Transform2D(
				Vector2(CAM_ZOOM.x, 0.0), Vector2(0.0, CAM_ZOOM.y), origin)

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
				moment, CAM_ZOOM.x,
				stage.get_node("Sayaka").position,
				stage.get_node("Girlfriend").position,
				stage.get_node("Boyfriend").position,
				_level.get_node("UILayer/UI/Opponent").get_child_count(),
				_level.get_node("UILayer/UI/Player").get_child_count(),
				path])

			_index += 1
			_step = Step.WIND
