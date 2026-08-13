extends SceneTree

## script_max= now carries a breakdown. This checks the breakdown describes
## the frame that set the record, and not four maxima from four frames.
##
## That distinction is the whole point. Four independent per-frame maxima can
## each come from a different frame, and adding them up gives a number that
## never happened - which would send the next investigation somewhere wrong,
## the failure this log has already caused twice. The snapshot is taken at
## the instant the record is beaten, so the parts belong together.
##
## Run with:
##   godot --headless --path . --script tools/test_script_peak_breakdown.gd

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

	# A frame with a small script cost and a large note cost, then a frame
	# with a large script cost and no note cost. If the snapshot were four
	# separate maxima, the second frame's record would be reported carrying
	# the first frame's note time.
	_reset(log_node)

	_frame(log_node, 2000, 1500, 1500, 400, 200)   # cheap frame, notes busy
	_frame(log_node, 9000, 300, 200, 50, 10)       # the record, notes idle

	var peak: int = log_node._script_peak_usec
	var note: int = log_node._peak_note_usec
	var lane: int = log_node._peak_lane_usec

	_check("el record es el frame caro", peak == 9000, "%d" % peak)
	_check("y trae SUS notas, no las del otro frame", note == 300, "%d" % note)
	_check("y sus lanes", lane == 200, "%d" % lane)

	var rest: float = float(peak - note) / 1000.0
	_check("rest es lo que no son notas", is_equal_approx(rest, 8.7), "%.2f ms" % rest)

	# A later cheaper frame must not overwrite the record or its breakdown.
	_frame(log_node, 1000, 900, 900, 100, 50)
	_check("un frame barato posterior no pisa el record",
		log_node._script_peak_usec == 9000 and log_node._peak_note_usec == 300,
		"peak=%d notes=%d" % [log_node._script_peak_usec, log_node._peak_note_usec])

	print("")
	if _failures == 0:
		print("todo OK - el desglose describe un solo frame")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## Drives one frame's worth of accounting by hand, so the test does not
## depend on a song being loaded or on real timings.
func _frame(log_node: Node, script_usec: int, note: int, lane: int,
		bounds: int, pump: int) -> void:
	RubiconLevelNoteHandler._frame_mark = -1
	RubiconLevelNoteHandler._roll_frame()
	RubiconLevelNoteHandler.frame_note_usec = note
	RubiconLevelNoteHandler.frame_lane_usec = lane
	RubiconLevelNoteHandler.frame_bounds_usec = bounds
	RubiconLevelNoteHandler.frame_pump_usec = pump

	log_node._script_begin_usec = 0
	log_node._close_script_bracket(script_usec)

func _reset(log_node: Node) -> void:
	log_node._script_peak_usec = 0
	log_node._peak_note_usec = 0
	log_node._peak_lane_usec = 0
	log_node._peak_bounds_usec = 0
	log_node._peak_pump_usec = 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s%s" % [name, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %s%s" % [name, "  (%s)" % detail if detail else ""])
