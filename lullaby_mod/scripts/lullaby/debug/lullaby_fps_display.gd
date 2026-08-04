class_name LullabyFPSDisplay extends Node

enum CurrentState
{
	NONE = 0,
	VERY_SIMPLE = 1,
	BASIC = 2,
	ADVANCED = 3
}

var current_state: CurrentState = CurrentState.VERY_SIMPLE

@export var container: Control

@export_group("FPS", "fps_")
@export var fps_average_counter: Label
@export var fps_low_counter: Label
@export var fps_high_counter: Label

@export var game_name_label: Label
@export var game_version_label: Label
@export var game_type_label: Label
@export var godot_version_label: Label
@export var debug_only_section: Control
@export var ram_label: Label
@export var vram_label: Label

## Rendering/memory diagnostics - ADVANCED only, aimed at "why is this
## lagging" (draw calls/primitives for GPU-bound frames, process/physics
## time for CPU-bound frames, node/object counts for leak-style creep).
@export_group("Diagnostics", "diag_")
@export var diag_render_method_label: Label
@export var diag_gpu_label: Label
@export var diag_draw_calls_label: Label
@export var diag_primitives_label: Label
@export var diag_objects_drawn_label: Label
@export var diag_video_mem_label: Label
@export var diag_buffer_mem_label: Label
@export var diag_node_count_label: Label
@export var diag_orphan_node_label: Label
@export var diag_object_count_label: Label
@export var diag_process_time_label: Label
@export var diag_physics_time_label: Label
@export var diag_physics_3d_objects_label: Label

## VERY_SIMPLE (the default) - just "FPS: 60 • Memory: 500 MB", nothing
## else. simple_container is a separate node from container (which holds
## the Classic/GameInfo/GodotInfo/DebugOnly blocks) since exactly one of
## the two is ever visible at a time and they'd otherwise fight over the
## same on-screen corner.
@export var simple_container: Control
@export var simple_label: Label

var _last_simple_fps: int = -1
var _last_simple_mem: int = -1

var _fps_tracker: PackedInt32Array
var _fps_index: int = 0
var _disable_quick_restart: bool = false

var _last_average: int = -1
var _last_low: int = -1
var _last_high: int = -1
var _last_ram_used: int = -1
var _last_ram_peak: int = -1
var _last_vram_used: int = -1

var _last_draw_calls: int = -1
var _last_primitives: int = -1
var _last_objects_drawn: int = -1
var _last_video_mem: int = -1
var _last_buffer_mem: int = -1
var _last_node_count: int = -1
var _last_orphan_nodes: int = -1
var _last_object_count: int = -1
var _last_process_time: int = -1
var _last_physics_time: int = -1
var _last_physics_3d_objects: int = -1

func _ready() -> void :
	game_name_label.text = ProjectSettings.get("application/config/name")
	game_version_label.text = ProjectSettings.get("application/config/version")
	game_type_label.text = "[%s]" % ("Editor" if Engine.is_editor_hint() else ("Debug" if OS.is_debug_build() else "Release"))

	var godot_version: Dictionary = Engine.get_version_info()
	godot_version_label.text = "%s" % [godot_version["string"]]

	diag_render_method_label.text = RenderingServer.get_current_rendering_method()
	diag_gpu_label.text = RenderingServer.get_video_adapter_name()

	_fps_tracker.resize(60)
	_fps_tracker.fill(0)

	update_visibility()

func _process(delta: float) -> void :
	if current_state == CurrentState.NONE:
		return

	var tracker_size: int = _fps_tracker.size()
	_fps_index = (_fps_index + 1) % tracker_size
	_fps_tracker[_fps_index] = floori(1.0 / delta);

	var average: int = 0
	var low: int = _fps_tracker[0]
	var high: int = 0
	for i in tracker_size:
		var current_value: int = _fps_tracker[i]
		average += _fps_tracker[i]

		if current_value < low:
			low = current_value

		if current_value > high:
			high = current_value

	average = floori(float(average) / tracker_size)

	if current_state == CurrentState.VERY_SIMPLE:
		var mem_used: int = OS.get_static_memory_usage()
		if average != _last_simple_fps or mem_used != _last_simple_mem:
			_last_simple_fps = average
			_last_simple_mem = mem_used
			simple_label.text = "FPS: %d • Memory: %s" % [average, to_memory_format(mem_used)]
		return

	if average != _last_average:
		_last_average = average
		fps_average_counter.text = str(average)
	if low != _last_low:
		_last_low = low
		fps_low_counter.text = str(low)
	if high != _last_high:
		_last_high = high
		fps_high_counter.text = str(high)

	if current_state < CurrentState.ADVANCED:
		return

	var ram_used: int = OS.get_static_memory_usage()
	var ram_peak: int = OS.get_static_memory_peak_usage()
	var vram_used: int = floori(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))

	if ram_used != _last_ram_used or ram_peak != _last_ram_peak:
		_last_ram_used = ram_used
		_last_ram_peak = ram_peak
		ram_label.text = "%s / %s" % [to_memory_format(ram_used), to_memory_format(ram_peak)]

	if vram_used != _last_vram_used:
		_last_vram_used = vram_used
		vram_label.text = "%s" % [to_memory_format(vram_used)]

	var draw_calls: int = floori(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if draw_calls != _last_draw_calls:
		_last_draw_calls = draw_calls
		diag_draw_calls_label.text = str(draw_calls)

	var primitives: int = floori(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if primitives != _last_primitives:
		_last_primitives = primitives
		diag_primitives_label.text = str(primitives)

	var objects_drawn: int = floori(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	if objects_drawn != _last_objects_drawn:
		_last_objects_drawn = objects_drawn
		diag_objects_drawn_label.text = str(objects_drawn)

	var video_mem: int = floori(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	if video_mem != _last_video_mem:
		_last_video_mem = video_mem
		diag_video_mem_label.text = to_memory_format(video_mem)

	var buffer_mem: int = floori(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	if buffer_mem != _last_buffer_mem:
		_last_buffer_mem = buffer_mem
		diag_buffer_mem_label.text = to_memory_format(buffer_mem)

	var node_count: int = floori(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if node_count != _last_node_count:
		_last_node_count = node_count
		diag_node_count_label.text = str(node_count)

	var orphan_nodes: int = floori(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if orphan_nodes != _last_orphan_nodes:
		_last_orphan_nodes = orphan_nodes
		diag_orphan_node_label.text = str(orphan_nodes)

	var object_count: int = floori(Performance.get_monitor(Performance.OBJECT_COUNT))
	if object_count != _last_object_count:
		_last_object_count = object_count
		diag_object_count_label.text = str(object_count)

	# Rounded to the nearest 0.1ms - these already jitter every frame, no
	# point re-stringifying every last float epsilon of noise.
	var process_time: int = roundi(Performance.get_monitor(Performance.TIME_PROCESS) * 10000.0)
	if process_time != _last_process_time:
		_last_process_time = process_time
		diag_process_time_label.text = "%.1f ms" % (process_time / 10.0)

	var physics_time: int = roundi(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 10000.0)
	if physics_time != _last_physics_time:
		_last_physics_time = physics_time
		diag_physics_time_label.text = "%.1f ms" % (physics_time / 10.0)

	var physics_3d_objects: int = floori(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	if physics_3d_objects != _last_physics_3d_objects:
		_last_physics_3d_objects = physics_3d_objects
		diag_physics_3d_objects_label.text = str(physics_3d_objects)

func update_visibility() -> void :
	match current_state:
		CurrentState.NONE:
			container.visible = false
			debug_only_section.visible = false
			simple_container.visible = false
		CurrentState.VERY_SIMPLE:
			container.visible = false
			debug_only_section.visible = false
			simple_container.visible = true
		CurrentState.BASIC:
			container.visible = true
			debug_only_section.visible = false
			simple_container.visible = false
		CurrentState.ADVANCED:
			container.visible = true
			debug_only_section.visible = true
			simple_container.visible = false

func _input(event: InputEvent) -> void :
	if event.is_action_pressed("quick_restart") and get_tree().current_scene is RubiconLevel and not _disable_quick_restart:
		SceneChanger.change_to(get_tree().current_scene.scene_file_path, &"hypno")

	if event.is_echo() or not event.is_action_pressed(&"debug_toggle"):
		return
	# VERY_SIMPLE ships in every build (it's the default), ADVANCED stays
	# debug-only, same as before - NONE, VERY_SIMPLE, BASIC in release;
	# all four in debug.
	var limit: int = 4 if OS.is_debug_build() else 3
	current_state = ((current_state + 1) % limit) as CurrentState
	update_visibility()

func to_memory_format(mem: int) -> String:
	if mem >= 1073741824:
		return "%s GB" % snappedf(mem / 1024.0 / 1024.0 / 1024.0, 0.01)
	elif mem >= 1048576:
		return "%s MB" % snappedf(mem / 1024.0 / 1024.0, 0.01)
	elif mem >= 1024:
		return "%s KB" % snappedf(mem / 1024.0, 0.01)
	else:
		return "%s B"
