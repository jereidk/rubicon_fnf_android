extends SceneTree

## Pins the memory trace, which is the one diagnostic that has to work while
## nothing else in the game is running.
##
## It exists because the Collector's Shop dies inside change_scene_to_packed()
## on a release build, and every other instrument in this project runs on the
## main thread - which is blocked for the whole of that call. If this thread
## stops when the main thread does, the trace is empty at exactly the moment
## it was written for, and nobody finds out until the next device log comes
## back useless.
##
## So the load-bearing claim here is not "it writes a file". It is that it
## keeps writing while the main thread is stuck. That is what the blocking
## case below actually tests: it freezes this thread with OS.delay_msec() the
## way instantiate() freezes it on the device, and then counts the samples
## that landed during the freeze.
##
## Run with:
##   godot --headless --path . --script tools/test_memory_sampler.gd

const Sampler := preload("res://lullaby_mod/scripts/lullaby/debug/lullaby_memory_sampler.gd")
const TRACE := "user://test_trace.mem"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	if not Sampler.is_supported():
		# Not a pass. A green run on a machine that cannot read /proc would say
		# nothing about the device, and this is the platform it ships to.
		print("FALLO: /proc no es legible aqui, el test no puede afirmar nada")
		quit(1)
		return

	_reader_case()
	await _blocking_case()
	_shape_case()

	print("")
	if _checks < 11:
		print("FALLO: solo %d de 11 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la traza sobrevive a un hilo principal bloqueado")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## /proc reports a length of zero, so the reader cannot use get_as_text().
func _reader_case() -> void:
	var rss: int = Sampler.proc_kb("/proc/self/status", "VmRSS:")
	_check("VmRSS se lee", rss > 0, "%d kB" % rss)

	var peak: int = Sampler.proc_kb("/proc/self/status", "VmHWM:")
	_check("VmHWM se lee y no es menor que VmRSS", peak >= rss,
		"pico %d kB" % peak)

	var avail: int = Sampler.proc_kb("/proc/meminfo", "MemAvailable:")
	_check("MemAvailable se lee", avail > 0, "%d MB" % (avail / 1024))

	_check("una clave inexistente da -1",
		Sampler.proc_kb("/proc/self/status", "NoExiste:") == -1)
	_check("un fichero inexistente da -1",
		Sampler.proc_kb("/proc/nada/de/nada", "VmRSS:") == -1)

## The whole point: samples must land while this thread is not running.
func _blocking_case() -> void:
	var sampler := Sampler.new()
	_check("arranca", sampler.start(TRACE))

	# Blocks this thread the way instantiate() does on the device. Not await,
	# not a timer - those yield, and yielding is precisely what the real
	# failure does not do.
	var blocked_ms := 700
	OS.delay_msec(blocked_ms)

	sampler.stop()

	var lines: PackedStringArray = _trace_lines()
	var expected: int = int(float(blocked_ms) / Sampler.SAMPLE_MS) - 1
	_check("muestrea con el hilo principal bloqueado",
		lines.size() >= expected,
		"%d muestras en %dms, esperaba >=%d" % [lines.size(), blocked_ms, expected])

	# A second stop() must not fault: shutdown reaches it by two paths
	# (WM_CLOSE_REQUEST and PREDELETE) and both may fire.
	sampler.stop()
	_check("stop() dos veces no revienta", true)

## The numbers have to be usable, not merely present.
func _shape_case() -> void:
	var lines: PackedStringArray = _trace_lines()
	_check("la traza tiene muestras", lines.size() > 0, "%d" % lines.size())
	if lines.is_empty():
		return

	var ok_shape: bool = true
	var ok_values: bool = true
	var first_t: int = -1
	var last_t: int = -1
	for line in lines:
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() != 4:
			ok_shape = false
			break
		var t: int = int(parts[0])
		if first_t < 0:
			first_t = t
		last_t = t
		# rss below peak, both positive, avail positive. A trace of zeroes
		# would pass a "did it write" check and be worthless.
		if int(parts[1]) <= 0 or int(parts[2]) < int(parts[1]) or int(parts[3]) <= 0:
			ok_values = false

	_check("cada muestra son 4 campos", ok_shape)
	_check("rss>0, pico>=rss, avail>0 en todas", ok_values)
	_check("el tiempo avanza", last_t > first_t, "%dms de traza" % (last_t - first_t))

	var head := FileAccess.open(TRACE, FileAccess.READ)
	var first_line: String = head.get_line() if head != null else ""
	if head != null:
		head.close()
	_check("lleva cabecera que explica las columnas",
		first_line.begins_with("#") and first_line.contains("rss"))

## Data lines only - the header and the trailer both start with '#'.
func _trace_lines() -> PackedStringArray:
	var file := FileAccess.open(TRACE, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if not line.is_empty() and not line.begins_with("#"):
			out.append(line)
	file.close()
	return out

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
