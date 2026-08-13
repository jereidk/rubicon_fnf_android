extends SceneTree

## RubiconCharacter._process is now timed, and its cost is subtracted from
## script_max's rest=. This checks the accounting.
##
## rest= is the number the next investigation will be read off, and it is a
## subtraction - which makes it the easiest field in the log to get quietly
## wrong. Two ways in particular:
##
##   the per-frame bucket never clearing, so chars= grows all session and
##   rest= is driven negative by a number that describes minutes of work
##   rather than one frame;
##
##   double-subtraction, the mistake lanes=/bounds=/pump= are already exposed
##   to - they are measured inside notes=, so taking them off as well would
##   remove the same microseconds twice and under-report the remainder.
##
## Both produce a plausible-looking small rest=, which reads as "nothing left
## to find" and ends the search early.
##
## Run with:
##   godot --headless --path . --script tools/test_character_timing.gd

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

	_roll_case()
	await _live_case()
	_peak_case(log_node)
	_rest_case(log_node)
	_rate_case()

	print("")
	if _failures == 0:
		print("todo OK - los personajes estan contabilizados")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The per-frame bucket has to empty itself on a new frame and hold within
## one, or it stops being a per-frame figure at all.
func _roll_case() -> void:
	RubiconCharacter._frame_mark = -1
	RubiconCharacter.roll_frame()
	RubiconCharacter.frame_process_usec = 500
	RubiconCharacter.frame_process_count = 2

	RubiconCharacter.roll_frame()
	_check("dos llamadas en el mismo frame no lo vacian",
		RubiconCharacter.frame_process_usec == 500, "%d" % RubiconCharacter.frame_process_usec)

	RubiconCharacter._frame_mark = -1
	RubiconCharacter.roll_frame()
	_check("un frame nuevo si lo vacia",
		RubiconCharacter.frame_process_usec == 0 and RubiconCharacter.frame_process_count == 0,
		"%d/%d" % [RubiconCharacter.frame_process_usec, RubiconCharacter.frame_process_count])

## A real character in a real tree, so the wrapper is exercised rather than
## the counters being poked by hand. _valid_references() fails on a bare
## character, which is the early return the split was made to time past - if
## the wrapper had been written around the body instead of around the whole
## call, this would measure nothing and the count would stay at zero.
func _live_case() -> void:
	RubiconCharacter.process_usec = 0
	RubiconCharacter._frame_mark = -1
	RubiconCharacter.roll_frame()

	var character := RubiconCharacter.new()
	root.add_child(character)
	await process_frame
	await process_frame

	_check("un personaje en el arbol se cuenta aunque salga temprano",
		RubiconCharacter.frame_process_count >= 1,
		"n=%d" % RubiconCharacter.frame_process_count)

	character.queue_free()
	await process_frame

## The breakdown must describe the frame that set the record, characters
## included - four maxima from four different frames add up to a frame that
## never happened.
func _peak_case(log_node: Node) -> void:
	_reset_peak(log_node)

	_frame(log_node, 2000, 1500, 900)   # cheap frame, characters busy
	_frame(log_node, 9000, 300, 1200)   # the record

	_check("el pico trae los personajes de SU frame",
		log_node._peak_char_usec == 1200, "%d" % log_node._peak_char_usec)
	_check("y cuantos eran", log_node._peak_chars == 3, "%d" % log_node._peak_chars)

	_frame(log_node, 1000, 100, 100)
	_check("un frame barato posterior no pisa el desglose",
		log_node._script_peak_usec == 9000 and log_node._peak_char_usec == 1200,
		"peak=%d chars=%d" % [log_node._script_peak_usec, log_node._peak_char_usec])

## rest= subtracts notes and characters, and nothing else - lanes, bounds and
## pump live inside the note total.
func _rest_case(log_node: Node) -> void:
	_reset_peak(log_node)

	RubiconLevelNoteHandler._frame_mark = -1
	RubiconLevelNoteHandler._roll_frame()
	RubiconLevelNoteHandler.frame_note_usec = 3000
	RubiconLevelNoteHandler.frame_lane_usec = 2000
	RubiconLevelNoteHandler.frame_bounds_usec = 800
	RubiconLevelNoteHandler.frame_pump_usec = 400
	RubiconCharacter._frame_mark = -1
	RubiconCharacter.roll_frame()
	RubiconCharacter.frame_process_usec = 2000
	RubiconCharacter.frame_process_count = 2

	log_node._script_begin_usec = 0
	log_node._close_script_bracket(10000)

	var rest: float = maxf(0.0, float(log_node._script_peak_usec
		- log_node._peak_note_usec - log_node._peak_char_usec) / 1000.0)
	# 10.0 total, 3.0 of notes, 2.0 of characters. lanes/bounds/pump are
	# already inside those 3.0 and must not come off again - subtracting all
	# five would give 0.8ms and hide 4.2ms of unexplained work.
	_check("rest = script - notas - personajes", is_equal_approx(rest, 5.0), "%.2f ms" % rest)

## The running total is a rate over the interval, so reading it must clear it.
func _rate_case() -> void:
	RubiconCharacter.process_usec = 4321
	var first: int = int(RubiconCharacter.take_process_stats()[&"usec"])
	var second: int = int(RubiconCharacter.take_process_stats()[&"usec"])
	_check("el total se lee una vez y se limpia", first == 4321 and second == 0,
		"%d luego %d" % [first, second])

## Drives one frame's worth of accounting by hand.
func _frame(log_node: Node, script_usec: int, note: int, chars: int) -> void:
	RubiconLevelNoteHandler._frame_mark = -1
	RubiconLevelNoteHandler._roll_frame()
	RubiconLevelNoteHandler.frame_note_usec = note

	RubiconCharacter._frame_mark = -1
	RubiconCharacter.roll_frame()
	RubiconCharacter.frame_process_usec = chars
	RubiconCharacter.frame_process_count = 3

	log_node._script_begin_usec = 0
	log_node._close_script_bracket(script_usec)

func _reset_peak(log_node: Node) -> void:
	log_node._script_peak_usec = 0
	log_node._peak_note_usec = 0
	log_node._peak_lane_usec = 0
	log_node._peak_bounds_usec = 0
	log_node._peak_pump_usec = 0
	log_node._peak_char_usec = 0
	log_node._peak_chars = 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
