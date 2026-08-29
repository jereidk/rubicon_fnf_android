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
const MOMENTS := [93.0, 100.0]
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


func _rect_of(name: String) -> Rect2:
	var character: Node2D = _level.find_child(name, true, false)
	var symbol: Node2D = character.get_child(0)
	var bounds: Rect2 = Rect2()
	if symbol is AnimatedSprite2D:
		var texture: Texture2D = (symbol as AnimatedSprite2D).sprite_frames \
			.get_frame_texture((symbol as AnimatedSprite2D).animation, 0)
		bounds = Rect2(symbol.position, texture.get_size() * symbol.scale.abs())
		if symbol.scale.x < 0.0:
			bounds.position.x = symbol.position.x - bounds.size.x
	var transform: Transform2D = character.get_viewport_transform() \
		* character.get_global_transform()
	return Rect2(transform * bounds.position, transform.get_scale() * bounds.size)


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

	# The WINDOW's size, not get_visible_rect(): the viewport transform maps into window
	# pixels (1365 wide here) while get_visible_rect() reports the project's logical 1920,
	# and dividing by the wrong one shrank every fraction by 0.711.
	var screen := Vector2(get_window().size)
	var camera: Camera2D = get_viewport().get_camera_2d()
	var tadano: Rect2 = _rect_of("TadanoStand")
	var komi: Rect2 = _rect_of("KomiStand")
	var events: Node = _level.get_node("PhoneCallEvents")
	print("OUT t=%5.1f zoom=%.3f cam=(%.0f, %.0f)  tadano cx=%.3f  komi cx=%.3f" % [
		player.current_animation_position, camera.zoom.x,
		camera.position.x, camera.position.y,
		tadano.get_center().x / screen.x, komi.get_center().x / screen.x])
	for name: String in ["TadanoStand", "KomiStand"]:
		var character: Node2D = _level.find_child(name, true, false)
		print("OUT     %-12s en mundo x=%.0f y=%.0f" % [
			name, character.global_position.x, character.global_position.y])
	print("OUT     puntos de pie: %s" % [events.get("stand_cast").keys()])
	_index += 1
