extends Node

## Every engine error and warning, in a file the player always has.
##
## The gap this closes: until now the diagnostics log could only record errors
## that somebody had hand-routed through `ErrorHandler.show_warning()` or
## `show_error()`, and there are exactly six such calls in the project - all of
## them catastrophic load failures that stop the game anyway. Everything else
## went to Android's logcat, which no player is ever going to send you:
##
##   * every push_error/push_warning this project writes, including the ones
##     added specifically to report a failure (console_late_resources.gd warns
##     when a deferred path does not resolve - that warning reached nobody)
##   * every red error the engine raises, e.g. "There is no animation with
##     name 'x'", which is the exact failure the console's sprite_animations
##     table exists to avoid and which nothing could have told us about
##   * every GDScript runtime error
##
## `OS.add_logger()` with a Logger subclass catches all three. Verified on
## 4.7.1 against this project before any of this was written: a push_error, a
## push_warning and an engine-side set_animation() failure all arrive, with
## the C++ file and line and an error_type that separates error from warning.
##
## SEPARATE FILE, and always on, for one reason: the diagnostics log now ships
## OFF, and the situation this is for is a player reporting a crash with
## nothing to send. A file that is only created the first time something
## actually goes wrong costs nothing on a session where nothing does. When the
## diagnostics log IS running it gets the same errors too, through `captured`,
## because only that file can say what the game was doing at the time.

## Where the file goes, mirroring the diagnostics log so both land in the same
## place and the player only has one folder to find.
const ANDROID_APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
const FALLBACK_LOG_DIR := "user://logs"
const ANDROID_PACKAGE := "com.rubicon.fnf"

## Kept, newest first. Small - these files only exist for sessions that had
## errors, and one is usually a few lines.
const MAX_ERROR_FILES := 5

## Distinct errors recorded per session before this stops opening new ones.
##
## The cap is on DISTINCT errors, not on total: a single error firing every
## frame collapses into one line with a counter, so the runaway case costs one
## entry, not sixty a second. What the cap protects against is a hundred
## different errors, which is a broken build rather than a bug report.
const MAX_DISTINCT := 200

## Emitted on the main thread for each newly seen error, so the diagnostics log
## can put it on its own timeline. Only the first occurrence of each distinct
## error is emitted; repeats are counted in the file instead of re-announced.
signal captured(kind: String, where: String, message: String)

var _sink: _Sink
var _file: FileAccess
var _path: String = ""

## Distinct error key -> how many times it has fired.
var _seen: Dictionary[String, int] = {}

## Filled from any thread, drained on the main one. See _Sink.
var _pending: Array[Dictionary] = []
var _lock: Mutex = Mutex.new()

## True while this node is writing. A failure inside the write would come
## straight back through the logger, and recursing into a half-written file is
## a worse bug than the one being reported.
var _writing: bool = false


## The Logger itself, which is not a Node and must not touch the filesystem.
##
## _log_error is called from whatever thread raised the error, and in this
## project that very much includes the ResourceLoader's - the whole shop load
## runs there. FileAccess from two threads at once is a corrupt file, so this
## end only appends to an array under a mutex and the Node drains it in
## _process.
class _Sink extends Logger:
	var owner_log: Node

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if owner_log == null:
			return
		# `rationale` carries the human message when the engine raises it, and
		# is empty for push_error/push_warning where `code` is the message.
		var message: String = rationale if not rationale.is_empty() else code
		owner_log.queue_error(error_type, "%s:%d %s" % [file.get_file(), line, function], message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sink = _Sink.new()
	_sink.owner_log = self
	OS.add_logger(_sink)


func _exit_tree() -> void:
	if _sink != null:
		OS.remove_logger(_sink)
		_sink = null
	_close()


## Called from any thread. Cheap on purpose - a mutex and an append.
func queue_error(error_type: int, where: String, message: String) -> void:
	if _writing:
		return
	_lock.lock()
	_pending.append({"type": error_type, "where": where, "message": message})
	_lock.unlock()


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return

	_lock.lock()
	var batch: Array[Dictionary] = _pending
	_pending = []
	_lock.unlock()

	_writing = true
	for item: Dictionary in batch:
		_record(item["type"], item["where"], item["message"])
	if _file != null:
		_file.flush()
	_writing = false


func _record(error_type: int, where: String, message: String) -> void:
	var kind: String = "WARNING" if error_type == 1 else "ERROR"
	var key: String = "%s|%s|%s" % [kind, where, message]

	if _seen.has(key):
		# Repeats are counted, not repeated - one dictionary bump per frame and
		# nothing else.
		#
		# But the count is also announced as it escalates, at 10, 100, 1000 and
		# so on, and that is a fix for this file's first outing rather than a
		# flourish. The totals used to be written only by _close(), and on
		# Android _close() mostly never runs: the OS kills the process. The
		# 2026-08-24 log came back with trance_shaders.gd erroring from
		# _process - potentially every frame of a whole song - and no way to
		# tell that from a single stray error, because the repeat section was
		# never reached. An error that happens ten thousand times is a
		# different bug from one that happens once, and the file has to say so
		# without depending on a clean exit.
		var count: int = _seen[key] + 1
		_seen[key] = count
		if count >= 10 and count == _next_power_of_ten(count):
			_write("%s (x%d)" % [message.replace("\n", " | "), count],
				"WARNING" if error_type == 1 else "ERROR", where)
		return

	if _seen.size() >= MAX_DISTINCT:
		return
	_seen[key] = 1

	_write(message.replace("\n", " | "), kind, where)
	captured.emit(kind, where, message)


## One entry, two lines: what happened and where it came from.
func _write(text: String, kind: String, where: String) -> void:
	if not _open():
		return
	_file.store_line("[%8.2fs] %-7s %s" % [
		float(Time.get_ticks_msec()) / 1000.0, kind, text])
	_file.store_line("          %s" % where)


## The power of ten at or below `count`, so an escalating repeat is announced
## once per decade rather than once per occurrence.
func _next_power_of_ten(count: int) -> int:
	var power: int = 10
	while power * 10 <= count:
		power *= 10
	return power


## Opened on the first error and not before, so a clean session leaves no file
## and the newest file on the device is always one that has something in it.
func _open() -> bool:
	if _file != null:
		return true

	var dir: String = _pick_dir()
	_rotate(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_path = "%s/lullaby_%s.error" % [dir, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return false

	_file.store_line("Lullaby error log")
	_file.store_line("date    : %s" % Time.get_datetime_string_from_system())
	var version: String = ""
	if ProjectSettings.has_setting("application/config/version"):
		version = str(ProjectSettings.get_setting("application/config/version"))
	_file.store_line("version : %s" % version)
	_file.store_line("os      : %s %s" % [OS.get_name(), OS.get_version()])
	_file.store_line("model   : %s" % OS.get_model_name())
	_file.store_line("gpu     : %s" % RenderingServer.get_video_adapter_name())
	_file.store_line("")
	return true


func _close() -> void:
	if _file == null:
		return
	# The repeat counts, written once, at the end. Anything that fired more
	# than once is the interesting half of this file: an error that happens
	# forty thousand times is a different problem from one that happens once.
	var repeated: Array[String] = []
	for key: String in _seen:
		if _seen[key] > 1:
			repeated.append("%6d x  %s" % [_seen[key], key.replace("|", "  ")])
	if not repeated.is_empty():
		_file.store_line("")
		_file.store_line("--- repeticiones ---")
		repeated.sort()
		for line: String in repeated:
			_file.store_line(line)
	if _seen.size() >= MAX_DISTINCT:
		_file.store_line("")
		_file.store_line("(tope de %d errores distintos alcanzado; el resto no se anoto)" % MAX_DISTINCT)
	_file.flush()
	_file.close()
	_file = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _sink != null:
			OS.remove_logger(_sink)
			_sink = null
		_close()


func _pick_dir() -> String:
	var candidates: Array[String] = []
	if OS.get_name() == "Android":
		candidates.append(ANDROID_APP_LOG_DIR_FMT % _android_package())
	candidates.append(FALLBACK_LOG_DIR)

	for candidate: String in candidates:
		if DirAccess.make_dir_recursive_absolute(candidate) == OK \
				or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return FALLBACK_LOG_DIR


func _android_package() -> String:
	var parts: PackedStringArray = OS.get_user_data_dir().split("/", false)
	var idx: int = parts.find("files")
	if idx > 0:
		return parts[idx - 1]
	return ANDROID_PACKAGE


## Keeps the newest MAX_ERROR_FILES, same as the diagnostics log does with its
## own - a phone should not accumulate one file per crashy session forever.
func _rotate(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array[String] = []
	for name: String in dir.get_files():
		if name.ends_with(".error"):
			files.append(name)
	files.sort()
	var excess: int = files.size() - (MAX_ERROR_FILES - 1)
	for i in maxi(excess, 0):
		dir.remove(files[i])
