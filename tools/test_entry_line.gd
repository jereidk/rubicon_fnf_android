extends SceneTree

## Writes one real entry and reads it back off disk.
##
## Every other test in here pokes the log's counters and checks the arithmetic.
## None of them ever checked that the line actually renders, and that is the
## one failure that takes the whole log with it: the counter line is a single
## format string with about seventy arguments, and GDScript answers an
## argument-count mismatch by printing an error and storing the *unformatted*
## string. Every entry for the entire session then reads as literal "%d"s.
##
## Nothing catches that before a device build. The counters would all still be
## correct, all their tests would still pass, and the log would be worthless -
## which is worse than it being missing, because the run has to be done again.
##
## Run with:
##   godot --headless --path . --script tools/test_entry_line.gd

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var log_node: Node = root.get_node_or_null("DiagnosticsLog")
	if log_node == null:
		print("FALLO: no encontre el autoload DiagnosticsLog")
		quit(1)
		return

	# The log is off unless the setting is on, and a headless run is not
	# obliged to have it on. Open one by hand so the test measures the format
	# string rather than the setting.
	if log_node._file == null and not log_node._open_log():
		print("FALLO: no pude abrir un log para la prueba")
		quit(1)
		return

	log_node.mark("prueba de formato")
	log_node._file.flush()

	var line: String = _last_entry(log_node.log_path)
	if line.is_empty():
		print("FALLO: no se escribio ninguna entrada")
		quit(1)
		return

	print("linea: %s" % line)
	print("")

	# The tell for a mismatch. GDScript leaves the specifiers in place, so a
	# single surviving "%" anywhere in the rendered line means the whole thing
	# failed to format.
	_check("la linea se formateo entera", not line.contains("%"),
		"primer %% en la col %d" % line.find("%") if line.contains("%") else "")

	_check("es la entrada que pedimos",
		line.contains("MARK") and line.contains("prueba de formato"))

	# The fields added most recently, which are the ones a mismatch would have
	# been introduced by.
	_check("trae el desglose de personajes", line.contains("chars="))
	_check("trae la tasa de personajes", line.contains("chars=0.00ms/s")
		or line.contains("ms/s") and line.count("chars=") == 2,
		"chars aparece %d veces" % line.count("chars="))
	_check("trae rest=", line.contains("rest="))

	# A spot-check that the arguments did not slide by one, which formats
	# cleanly and reports every number under the wrong name.
	_check("script_max sigue delante de spawn",
		line.find("script_max=") < line.find("spawn="))
	_check("chars= del pico esta dentro de script_max(...)",
		line.find("chars=") > line.find("script_max=")
		and line.find("chars=") < line.find("rest="))
	_check("la linea termina en la escena", line.contains("scene="))

	# The histogram rides on HEARTBEAT rather than on every line, so it is
	# checked where it lives.
	var shape: String = log_node._take_frame_shape()
	_check("el histograma tambien se formatea",
		not shape.contains("%%") and shape.contains("hist=[") and shape.contains("vsync="),
		shape)

	print("")
	if _failures == 0:
		print("todo OK - la linea se escribe entera")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## Last non-empty line of the log, which is the entry just written.
func _last_entry(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""

	var last: String = ""
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if not line.is_empty():
			last = line
	f.close()
	return last

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %-48s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-48s%s" % [label, "  (%s)" % detail if detail else ""])
