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

func _ready() -> void :
	game_name_label.text = ProjectSettings.get("application/config/name")
	game_version_label.text = ProjectSettings.get("application/config/version")
	game_type_label.text = "[%s]" % ("Editor" if Engine.is_editor_hint() else ("Debug" if OS.is_debug_build() else "Release"))

	var godot_version: Dictionary = Engine.get_version_info()
	godot_version_label.text = "%s" % [godot_version["string"]]

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
