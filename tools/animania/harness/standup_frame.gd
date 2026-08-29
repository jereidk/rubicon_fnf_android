# Where the standing pair actually land ON SCREEN after the swap, as fractions of the frame,
# so a capture of the original can be measured with the same ruler.
#
# The reference frame the user supplied measures: tadano's centre at 0.301 of the width,
# komi's at 0.574, and both about 0.70 of the frame tall.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/standup_frame.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const MOMENTS := [70.0, 85.0, 93.0]
const WIND_SPEED := 20.0

var _level: Node
var _frames: int = 0
var _index: int = 0
var _settle: int = 0


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	if _index >= MOMENTS.size():
		get_tree().quit()
		return
	var player: AnimationPlayer = _level.get_node("RubiconLevelClock").animation_player
	if player.current_animation_position < MOMENTS[_index]:
		player.speed_scale = WIND_SPEED
		return
	player.speed_scale = 1.0
	_settle += 1
	if _settle < 3:
		return
	_settle = 0
	# The script's own moves are tweens on REAL time, and winding the clock at 20x leaves
	# them far behind - tadano got caught mid-slide and read 187px short of where he ends
	# up. Run them out before measuring anything.
	for running: Tween in get_tree().get_processed_tweens():
		running.custom_step(10.0)
		running.kill()

	var camera: Camera2D = get_viewport().get_camera_2d()
	# Before the swap the standing pair are hidden and the phone pair are on screen.
	var standing: bool = player.current_animation_position >= 91.58
	var half: float = 960.0 / camera.zoom.x
	print("OUT t=%5.1f zoom=%.3f cam=(%.0f, %.0f)" % [
		player.current_animation_position, camera.zoom.x,
		camera.position.x, camera.position.y])
	for name: String in (["TadanoStand", "KomiStand"] if standing else ["Tadano", "Komi"]):
		var character: Node2D = _level.find_child(name, true, false)
		# Where the character's own anchor lands across the frame: 0 is the left edge and
		# 1 the right. Computed from the camera rather than from the sprite's bounds, which
		# depend on how each character happens to be drawn.
		var fraction: float = (character.global_position.x - camera.position.x + half) \
			/ (half * 2.0)
		print("OUT     %-12s mundo x=%-7.0f pantalla %.3f" % [
			name, character.global_position.x, fraction])
	_index += 1
