extends CanvasLayer
## FPS and memory, on top of whatever is running.
##
## An autoload rather than a node in a scene, because the port changes scenes - title to
## song - and a per-scene overlay would blink out exactly when the frame time is worth
## watching: during the load.
##
## Only in debug builds. A release export never pays for it.

## Above the HUD (2), the death layer (1) and the letterbox, so nothing draws over it.
const LAYER := 128
## Refreshed a few times a second rather than every frame: a number that changes 60 times a
## second cannot be read, and rebuilding the string that often is itself measurable.
const REFRESH := 0.25
## Tapping this corner toggles it, for devices with no keyboard. Kept off the lanes.
const TOGGLE_CORNER := Vector2(160.0, 160.0)

var _label: Label
var _timer: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(24.0, 16.0)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH:
		return
	_timer = 0.0
	_refresh()


func _refresh() -> void:
	_label.text = "FPS: %d | MEMORY: %d MBS" % [
		Engine.get_frames_per_second(),
		int(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0),
	]


## F3 on a desktop, a tap in the top-left corner on a phone.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible
	elif event is InputEventScreenTouch and event.pressed:
		if event.position.x < TOGGLE_CORNER.x and event.position.y < TOGGLE_CORNER.y:
			visible = not visible
