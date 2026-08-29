# Prints, for one moment of phone-call, where every stage layer and character actually
# lands ON SCREEN. Written to compare the port against a screenshot of the original
# frame by frame: a screen rect here can be measured with a ruler over there.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/frame_probe.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const MOMENT := 9.2
const PLAY_IN := 1.6
const WIND_STEP := 0.5

var _level: Node
var _clock: Node
var _frames: int = 0
var _step: int = 0


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
	match _step:
		0:
			if _wind_step(MOMENT - PLAY_IN):
				_step = 1
		1:
			if clock.current_animation_position >= MOMENT:
				_step = 2
		2:
			var camera: Camera2D = get_viewport().get_camera_2d()
			camera.zoom = camera.zoom_interpolate_target
			camera.position = camera.position_interpolate_target
			_step = 3
		3:
			_report()
			get_tree().quit()


## Funkin renders 1280x720; this project renders 1920x1080. Everything is printed in
## FUNKIN screen pixels so it can be laid straight over a screenshot of the mod.
const TO_FUNKIN := 1280.0 / 1920.0


func _report() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	print("clock t=%.3f" % _clock.animation_player.current_animation_position)
	print("camera pos=%s target=%s offset=%s zoom=%.4f  (funkin zoom=%.4f)" % [
		camera.position, camera.position_interpolate_target,
		camera.position_interpolate_offset, camera.zoom.x, camera.zoom.x / 1.5])
	for name: String in ["PlayerCameraPoint", "OpponentCameraPoint", "GirlfriendCameraPoint"]:
		if _level.has_node(name):
			print("  %s = %s" % [name, (_level.get_node(name) as Node2D).position])

	print("--- on screen, in FUNKIN pixels (1280x720) ---")
	var seen: Array[String] = []
	_walk(_level, "", seen)


func _walk(node: Node, path: String, seen: Array[String]) -> void:
	for child: Node in node.get_children():
		var here: String = path + "/" + child.name
		if child is Node2D and not (child is Marker2D):
			var n: Node2D = child
			var t: Transform2D = n.get_global_transform_with_canvas()
			var o: Vector2 = t.origin * TO_FUNKIN
			var extra: String = ""
			if n is Sprite2D and (n as Sprite2D).texture != null:
				var s: Sprite2D = n
				var size: Vector2 = s.texture.get_size() * t.get_scale() * TO_FUNKIN
				extra = " size=(%.0f,%.0f)" % [size.x, size.y]
			if n.visible and n.is_visible_in_tree():
				print("  %-46s at (%7.1f,%7.1f)%s" % [here, o.x, o.y, extra])
		_walk(child, here, seen)
