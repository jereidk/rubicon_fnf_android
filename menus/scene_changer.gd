extends CanvasLayer

## Autoload (see project.godot [autoload]) that handles fading between menu
## scenes, since Rubicon has no scene-flow system of its own to build on.

const FADE_DURATION := 0.35

var _fade_rect: ColorRect
var _busy := false

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true

	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)
	await tween.finished

	get_tree().change_scene_to_file(path)

	var tween_in := create_tween()
	tween_in.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
	await tween_in.finished

	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
