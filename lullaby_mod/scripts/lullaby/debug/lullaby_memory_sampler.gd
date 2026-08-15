class_name LullabyMemorySampler extends RefCounted

## A memory trace written from its own thread, so it keeps sampling while the
## main thread is blocked.
##
## The Collector's Shop dies on a release build somewhere inside
## change_scene_to_packed(), and the main log cannot see in: that call
## instantiates 1698 resources without yielding, so between the SCENE_IN entry
## and the process disappearing there is no frame, no _process, and no
## opportunity to write anything. Every diagnostic that runs on the main
## thread goes blind at exactly the moment worth watching.
##
## This does not run on the main thread. Every SAMPLE_MS it reads this
## process's resident memory and the kernel's remaining headroom and appends a
## line, flushed immediately. If the process is killed, the trace ends at the
## last sample before the kill - and the shape of the last second says which
## kind of death it was:
##
##   rss climbing hard, avail falling to near zero  -> the kernel killed us
##   rss flat, trace simply stops                   -> we faulted
##   rss flat for seconds, then stops               -> Android gave up on an
##                                                     unresponsive main thread
##
## Those three need three different fixes, and nothing else in this project
## can currently tell them apart.
##
## Its own file, deliberately. Sharing the main log's FileAccess across two
## threads would need a mutex on every entry the game writes, to buy nothing:
## the traces are trivially read side by side by timestamp, and a separate
## file cannot corrupt the log it is trying to explain.

## Fast enough to catch a spike inside a single blocking call, slow enough that
## the thread costs nothing measurable - two small /proc reads at 10Hz.
const SAMPLE_MS := 100

## Sampling stops here regardless. A trace is a debugging aid for a session
## that ends in a crash; left unbounded through a long play session it would
## be a large file nobody reads. At 10Hz this is about 36000 lines.
const MAX_SAMPLES := 36000

var _thread: Thread
var _running := false
var _mutex := Mutex.new()
var _path: String = ""

## Where the trace was written, for the main log to name in its own header.
func get_path() -> String:
	return _path

## Reads one kB value out of a /proc file.
##
## Static because the sampler thread calls it and it touches no state, and
## get_line() rather than get_as_text() because /proc reports a length of zero
## and get_as_text() believes it, returning empty from a file with content.
static func proc_kb(path: String, key: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var found: int = -1
	while true:
		var line: String = file.get_line()
		if line.is_empty():
			break
		if not line.begins_with(key):
			continue
		for token in line.split(" ", false):
			if token.is_valid_int():
				found = int(token)
				break
		break
	file.close()
	return found

## True where /proc is readable, which is Linux and Android. Everywhere else
## this whole object is skipped rather than started and left writing "-".
static func is_supported() -> bool:
	return proc_kb("/proc/self/status", "VmRSS:") >= 0

func start(log_path: String) -> bool:
	if _running or not is_supported():
		return false
	_path = log_path
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("# t_ms rss_kb peak_kb avail_kb")
	file.store_line("# rss  = this process (VmRSS), peak = its highest ever (VmHWM)")
	file.store_line("# avail= what the kernel can still hand out (MemAvailable)")
	file.close()

	_running = true
	_thread = Thread.new()
	if _thread.start(_loop.bind(_path)) != OK:
		_running = false
		_thread = null
		return false
	return true

func stop() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	# Blocking on purpose: the thread holds a FileAccess, and letting the
	# object die with it still writing is how a trace ends up truncated by the
	# shutdown it was supposed to record.
	_thread.wait_to_finish()
	_thread = null

func _is_running() -> bool:
	_mutex.lock()
	var value: bool = _running
	_mutex.unlock()
	return value

func _loop(path: String) -> void:
	# Opened on this thread and never touched from another, which is what makes
	# the whole design lock-free apart from the stop flag.
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()

	var samples: int = 0
	while _is_running() and samples < MAX_SAMPLES:
		file.store_line("%d %d %d %d" % [
			Time.get_ticks_msec(),
			proc_kb("/proc/self/status", "VmRSS:"),
			proc_kb("/proc/self/status", "VmHWM:"),
			proc_kb("/proc/meminfo", "MemAvailable:"),
		])
		# Every sample, because the last one before a kill is the only one that
		# matters and a buffered tail is exactly what a kill throws away.
		file.flush()
		samples += 1
		OS.delay_msec(SAMPLE_MS)

	file.store_line("# fin (%d muestras)" % samples)
	file.flush()
	file.close()
