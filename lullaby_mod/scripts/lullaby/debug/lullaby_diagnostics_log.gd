extends Node

## Writes a diagnostics log to disk so problems that only happen on a real
## phone can be read after the fact instead of reproduced on demand.
##
## The on-screen debug display already shows FPS, memory and render counters,
## but it only shows them NOW - by the time the player notices a stutter the
## interesting numbers are two seconds gone, and nobody can read a counter
## while playing anyway. This records the same figures continuously, keeps a
## rolling window of recent frames, and writes a detailed snapshot whenever
## something is actually worth looking at.
##
## It is deliberately quiet during normal play. Writing a line every frame
## would produce a log too large to read, cost I/O on the very frames that
## are already struggling, and bury the real events. Instead it logs:
##
##   - a heartbeat every HEARTBEAT_SECONDS, so there is always a baseline to
##     compare a spike against
##   - a frame spike, when a frame takes SPIKE_FACTOR times longer than the
##     recent median (this is what a stutter looks like from in here)
##   - a memory jump, when static memory grows by MEMORY_JUMP_MB at once
##   - scene changes, with the before/after memory and how long the load took
##   - every error and warning that reaches ErrorHandler
##
## Each entry carries the full counter set, so any single line is enough to
## tell a CPU-bound stall (process time up, draw calls flat) from a GPU one
## (draw calls and VRAM up) from a leak (orphan nodes climbing across
## heartbeats) - which is exactly the distinction that decides how to fix it.

const LOG_DIR := "user://logs"
const MAX_LOG_FILES := 5

## A frame this much slower than the recent median counts as a spike. 2.5x is
## high enough that ordinary jitter doesn't trip it but low enough to catch a
## hitch the player would feel.
const SPIKE_FACTOR := 2.5
const SPIKE_MIN_MS := 24.0

const MEMORY_JUMP_MB := 24.0
const HEARTBEAT_SECONDS := 5.0
const WINDOW_SIZE := 120

## Spikes cluster - one stutter can trip the check for several frames running,
## and a loading screen can trip it dozens of times. Rate-limited so a single
## bad moment costs a few lines rather than a few hundred.
const SPIKE_COOLDOWN_SECONDS := 0.5

var log_path: String = ""

var _file: FileAccess
var _frame_times: PackedFloat32Array
var _frame_index: int = 0
var _frames_seen: int = 0

var _time_since_heartbeat: float = 0.0
var _time_since_spike: float = 999.0
var _last_memory: int = 0
var _peak_memory: int = 0
var _lowest_fps: int = -1
var _session_start_ms: int = 0

var _scene_change_started_ms: int = 0
var _scene_change_memory: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not Settings.lullaby_diagnostics_log:
		set_process(false)
		return

	if not _open_log():
		set_process(false)
		return

	_frame_times.resize(WINDOW_SIZE)
	_frame_times.fill(0.0)
	_session_start_ms = Time.get_ticks_msec()
	_last_memory = OS.get_static_memory_usage()
	_peak_memory = _last_memory

	_write_header()

	# ErrorHandler is an autoload declared before this one, so it already
	# exists. Both of its entry points are routed here so a crash screen the
	# player dismisses still leaves a record behind.
	if ErrorHandler.has_signal("logged"):
		ErrorHandler.logged.connect(_on_error_logged)

	if SceneChanger.has_signal("scene_change_started"):
		SceneChanger.scene_change_started.connect(_on_scene_change_started)
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_change_finished)

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0

	var median: float = _median_frame_ms()
	_frame_times[_frame_index] = frame_ms
	_frame_index = (_frame_index + 1) % WINDOW_SIZE
	_frames_seen += 1

	var fps: int = int(round(1.0 / maxf(delta, 0.0001)))
	if _lowest_fps < 0 or fps < _lowest_fps:
		_lowest_fps = fps

	var memory: int = OS.get_static_memory_usage()
	if memory > _peak_memory:
		_peak_memory = memory

	_time_since_heartbeat += delta
	_time_since_spike += delta

	# Needs a full window before the median means anything, otherwise the
	# first frames after a load all read as spikes against a near-empty
	# buffer.
	if _frames_seen > WINDOW_SIZE and _time_since_spike >= SPIKE_COOLDOWN_SECONDS:
		if frame_ms >= SPIKE_MIN_MS and frame_ms >= median * SPIKE_FACTOR:
			_time_since_spike = 0.0
			_entry("SPIKE", "frame=%.1fms median=%.1fms (%.1fx)" % [frame_ms, median, frame_ms / maxf(median, 0.001)])

	var grew_mb: float = float(memory - _last_memory) / 1048576.0
	if grew_mb >= MEMORY_JUMP_MB:
		_entry("MEMORY", "+%.1f MB in one frame" % grew_mb)
	_last_memory = memory

	if _time_since_heartbeat >= HEARTBEAT_SECONDS:
		_time_since_heartbeat = 0.0
		_entry("HEARTBEAT", "fps_now=%d fps_low=%d median=%.1fms" % [fps, _lowest_fps, median])
		_lowest_fps = -1

## Public so anything can drop a marker into the log - e.g. a mechanic
## starting, or a cutscene the player says "it breaks here".
func mark(what: String) -> void:
	_entry("MARK", what)

func _on_error_logged(kind: String, message: String, err: int) -> void:
	_entry(kind.to_upper(), "%s (error %d)" % [message.replace("\n", " | "), err])

func _on_scene_change_started(path: String) -> void:
	_scene_change_started_ms = Time.get_ticks_msec()
	_scene_change_memory = OS.get_static_memory_usage()
	_entry("SCENE_OUT", path)

func _on_scene_change_finished(path: String) -> void:
	var took: int = Time.get_ticks_msec() - _scene_change_started_ms
	var delta_mb: float = float(OS.get_static_memory_usage() - _scene_change_memory) / 1048576.0
	_entry("SCENE_IN", "%s took=%dms memory_delta=%+.1fMB" % [path, took, delta_mb])
	# The frame window is meaningless across a load, and every frame after one
	# would otherwise read as a spike against the pre-load median.
	_frames_seen = 0
	_frame_times.fill(0.0)

func _median_frame_ms() -> float:
	if _frames_seen < WINDOW_SIZE:
		return 16.6
	var sorted: Array = Array(_frame_times)
	sorted.sort()
	return sorted[WINDOW_SIZE / 2]

## Every entry carries the whole counter set. It makes lines long, but it
## means a single line answers "what was happening", instead of having to
## correlate it against the nearest heartbeat.
func _entry(kind: String, detail: String) -> void:
	if _file == null:
		return

	var seconds: float = float(Time.get_ticks_msec() - _session_start_ms) / 1000.0
	_file.store_line("[%9.2fs] %-10s %s | ram=%s peak=%s vram=%s draw=%d prims=%d objs=%d nodes=%d orphans=%d proc=%.2fms phys=%.2fms scene=%s" % [
		seconds,
		kind,
		detail,
		_mb(OS.get_static_memory_usage()),
		_mb(_peak_memory),
		_mb(int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		_current_scene_name(),
	])
	# Flushed every entry on purpose: the whole point is to survive a crash or
	# a force-close, and a buffered tail is exactly the part worth reading.
	_file.flush()

## Guarded because the last entry is written from NOTIFICATION_PREDELETE, by
## which point get_tree() is already null - reading current_scene there threw
## on every shutdown and cost the log its final line's context.
func _current_scene_name() -> String:
	var tree: SceneTree = get_tree()
	if tree == null:
		return "-"

	var scene: Node = tree.current_scene
	return scene.scene_file_path.get_file() if scene and not scene.scene_file_path.is_empty() else "?"

func _mb(bytes: int) -> String:
	return "%.0fMB" % (bytes / 1048576.0)

func _open_log() -> bool:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_rotate()

	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	log_path = "%s/lullaby_%s.log" % [LOG_DIR, stamp]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("diagnostics: cannot open %s" % log_path)
		return false
	return true

## Keeps the newest MAX_LOG_FILES. Without this a phone accumulates one file
## per launch forever, and the player is the one paying for the space.
func _rotate() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return

	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".log"):
			files.append(f)
	files.sort()

	var excess: int = files.size() - (MAX_LOG_FILES - 1)
	for i in maxi(excess, 0):
		DirAccess.remove_absolute(LOG_DIR.path_join(files[i]))

func _write_header() -> void:
	if _file == null:
		return
	_file.store_line("Lullaby diagnostics log")
	_file.store_line("date      : %s" % Time.get_datetime_string_from_system())
	_file.store_line("version   : %s" % ProjectSettings.get_setting("application/config/version", "?"))
	_file.store_line("godot     : %s" % Engine.get_version_info()["string"])
	_file.store_line("os        : %s %s" % [OS.get_name(), OS.get_version()])
	_file.store_line("model     : %s" % OS.get_model_name())
	_file.store_line("cpu       : %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	_file.store_line("gpu       : %s" % RenderingServer.get_video_adapter_name())
	_file.store_line("renderer  : %s" % RenderingServer.get_current_rendering_method())
	_file.store_line("memory    : %d MB" % (OS.get_memory_info().get("physical", 0) / 1048576))
	_file.store_line("window    : %s" % DisplayServer.window_get_size())
	_file.store_line("path      : %s" % ProjectSettings.globalize_path(log_path))
	_file.store_line("")
	_file.flush()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _file != null:
			_entry("SHUTDOWN", "session ended")
			_file.close()
			_file = null
