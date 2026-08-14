extends SceneTree

## The note pool is now sized to the chart's peak concurrency instead of its
## total note count. This checks the peak is right.
##
## Getting it wrong is asymmetric, which is why the brute-force cross-check
## below exists rather than a few hand-written expectations:
##
##   too high  - the old behaviour. Memory and a load-time hitch, invisible in
##               play, which is exactly why it survived this long.
##   too low   - spawn_note() falls through to instantiate() mid-song, which
##               is a stutter in the middle of a chart. This is the direction
##               that must not be got wrong.
##
## So the sweep is checked against an independent O(n^2) count of what is
## actually alive at every moment. Two implementations of the same question,
## one of them obviously correct and too slow to ship.
##
## Run with:
##   godot --headless --path . --script tools/test_pool_sizing.gd

## The handler's own defaults, so the test measures the window the game uses.
const BOUND_MAX := 2000.0
const BOUND_MIN := -1000.0
const MODE_ID := &"mania"

var _failures: int = 0
## Checks actually performed. A run where every case threw would otherwise
## reach the end with zero failures and print "todo OK" - which is exactly
## what the first version of this test did.
var _checks: int = 0
const EXPECTED_CHECKS := 10

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# A sparse chart: notes four seconds apart, so the 3s window never holds
	# more than one. The old sizing would have prewarmed all 40.
	_case("disperso: nunca se solapan", _chart(40, 4000.0, 0.0), 1)

	# Every note 100ms apart. The window spans start-2000 to end+1000, so
	# 3000ms of notes at 100ms spacing is about 31 alive at once.
	_case("denso: 100ms de separacion", _chart(40, 100.0, 0.0), 31)

	# Holds stay alive for their whole length, so they overlap far more than
	# their spacing suggests - the case a "count them and cap it" rule and a
	# spacing-based estimate would both get wrong.
	_case("holds largos se solapan mas que su separacion",
		_chart(20, 500.0, 2000.0), 20)

	# A chart dense enough to blow past the cap has to stop at it.
	_case("un chart patologico se corta en el tope", _chart(400, 10.0, 0.0),
		RubiconLevelNoteHandler.POOL_PREWARM_MAX, true)

	_empty_case()

	print("")
	if _checks < EXPECTED_CHECKS:
		print("FALLO: solo se ejecutaron %d de %d comprobaciones - algun caso reventó"
			% [_checks, EXPECTED_CHECKS])
		quit(1)
		return

	if _failures == 0:
		print("todo OK - el pool se dimensiona al pico real (%d comprobaciones)" % _checks)
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _case(label: String, notes: Array, expect_raw: int, capped: bool = false) -> void:
	var got: Dictionary = RubiconLevelNoteHandler.peak_concurrent_by_key(
		notes, MODE_ID, BOUND_MAX, BOUND_MIN)
	var sized: int = int(got.get(MODE_ID, 0))

	# The independent count: for every note's entry moment, how many notes are
	# alive, worked out from the interval arithmetic directly.
	var brute: int = _brute_peak(notes)

	var want: int = sized if capped else mini(brute + RubiconLevelNoteHandler.POOL_PREWARM_HEADROOM,
		RubiconLevelNoteHandler.POOL_PREWARM_MAX)

	print("  %s" % label)
	print("      notas=%d  pico_fuerza_bruta=%d  pool=%d%s" % [
		notes.size(), brute, sized, "  (en el tope)" if capped else "",
	])

	if capped:
		_check("    se corta en el tope", sized == RubiconLevelNoteHandler.POOL_PREWARM_MAX,
			"%d" % sized)
	else:
		_check("    coincide con la fuerza bruta", sized == want, "%d vs %d" % [sized, want])
		# The direction that matters. A pool at or above the real peak never
		# instantiates mid-song.
		_check("    cubre el pico real", sized >= brute, "%d >= %d" % [sized, brute])
		_check("    y no es el total del chart", sized < notes.size() or notes.size() <= expect_raw,
			"%d de %d notas" % [sized, notes.size()])


## What the old sizing would never have needed: a chart with no notes must not
## prewarm anything, and must not throw doing it.
func _empty_case() -> void:
	var got: Dictionary = RubiconLevelNoteHandler.peak_concurrent_by_key(
		[], MODE_ID, BOUND_MAX, BOUND_MIN)
	print("  chart vacio")
	_check("    no reserva nada", got.is_empty(), "%d claves" % got.size())

## An O(n^2) count of the widest set of simultaneously-alive notes, done from
## the interval definition rather than from the two-pointer walk.
##
## A note is alive from start-spawning_bound_maximum until its end passes
## spawning_bound_minimum, which is the condition update_bounds() applies.
func _brute_peak(notes: Array) -> int:
	var peak: int = 0
	for i in notes.size():
		var moment: float = notes[i].get_millisecond_start_position() - BOUND_MAX
		var alive: int = 0
		for j in notes.size():
			var enters: float = notes[j].get_millisecond_start_position() - BOUND_MAX
			var leaves: float = notes[j].get_millisecond_end_position() - BOUND_MIN
			# Both bounds inclusive, matching update_bounds(): it retires a note
			# on "end - t < bound_minimum", so one sitting exactly on the
			# boundary is still alive. A strict < here reports one fewer than
			# the engine actually keeps, and the sweep then looks like it is
			# over-allocating by one when it is the cross-check that is wrong.
			if enters <= moment and moment <= leaves:
				alive += 1
		peak = maxi(peak, alive)
	return peak

## A chart of evenly spaced notes, each held for hold_ms.
func _chart(count: int, spacing_ms: float, hold_ms: float) -> Array:
	var notes: Array = []
	for i in count:
		notes.append(_FakeNote.new(float(i) * spacing_ms, float(i) * spacing_ms + hold_ms))
	return notes

## Stands in for a RubiChartNote. The sweep only ever asks a note for its
## start, its end and its type, and building real ones needs a whole chart
## with rows and sections behind them.
class _FakeNote:
	var type: StringName = &""
	var _start: float
	var _end: float

	func _init(start_ms: float, end_ms: float) -> void:
		_start = start_ms
		_end = end_ms

	func get_millisecond_start_position() -> float:
		return _start

	func get_millisecond_end_position() -> float:
		return _end

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok  %-42s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-40s%s" % [label, "  (%s)" % detail if detail else ""])
