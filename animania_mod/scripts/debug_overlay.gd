extends CanvasLayer
## FPS and memory, on top of whatever is running.
##
## An autoload rather than a node in a scene, because the port now changes scenes - title to
## song - and a per-scene overlay would blink out exactly when you want to watch the frame
## time: during the load.
##
## Only in debug builds. A release export never pays for it.

## Above the HUD (2), the death layer (1) and the letterbox, so nothing draws over it.
const LAYER := 128
## Refreshed a few times a second rather than every frame: rebuilding this string at 60fps
## is itself a measurable cost on a phone, and a number that flickers cannot be read.
const REFRESH := 0.25
## Tapping this corner toggles it, for devices with no keyboard. Kept off the lanes and
## above the letterbox bar.
const TOGGLE_CORNER := Vector2(160.0, 160.0)

var _label: Label
var _timer: float = 0.0
## Frame time is sampled every frame even though the text is not, or the worst frame in a
## quarter of a second - the one that makes a phone stutter - never shows up.
var _worst_frame_ms: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(24.0, 16.0)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6, 1.0))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh()


func _process(delta: float) -> void:
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	_timer += delta
	if _timer < REFRESH:
		return
	_timer = 0.0
	_refresh()
	_worst_frame_ms = 0.0


func _refresh() -> void:
	var static_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var peak_mb: float = float(OS.get_static_memory_peak_usage()) / 1048576.0
	var video_mb: float = float(Performance.get_monitor(
		Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0

	_label.text = "\n".join([
		"%d fps   %.1f ms   peor %.1f ms" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			_worst_frame_ms],
		"ram %.1f MB   pico %.1f MB   video %.1f MB" % [static_mb, peak_mb, video_mb],
		"draws %d   nodos %d   objetos %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT)],
	])


## F3 on a desktop, a tap in the top-left corner on a phone.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible
	elif event is InputEventScreenTouch and event.pressed:
		if event.position.x < TOGGLE_CORNER.x and event.position.y < TOGGLE_CORNER.y:
			visible = not visible
