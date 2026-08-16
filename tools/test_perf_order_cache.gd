extends SceneTree

## The cached hit order has to equal the one the sort produced, every time.
##
## update_performance() used to rebuild an array of every result hit so far
## and sort_custom it, once per note that lands - O(n log n) per note, so
## O(n squared log n) across a song. The bench says the sort alone is 60-63%
## of that function and Monochrome's device log measured the consequence: the
## lanes' _process growing from 1.0ms at the start of the song to 19.9ms by
## the end, purely with progress.
##
## The array is now kept and extended instead. That is only safe if it holds
## nothing but order, so this test does not check that the new code is fast -
## it checks that at every step it returns exactly what the old build-and-sort
## returned, element for element.
##
## The sequence deliberately includes what makes this hard:
##   - notes landing across eight lanes, interleaved in time
##   - misses, whose time_when_hit is pushed a second into the future by
##     hit_note() and therefore arrive out of order
##   - a hold in progress, which counts while HIT_INCOMPLETE and stops
##     counting when it resolves - moving a handler's range backwards
##   - a rewind, which moves note_hit_index backwards
##
## Run with:
##   godot --headless --path . --script tools/test_perf_order_cache.gd

const CONTROLLER := "res://addons/rubicon/scripts/scene/game/rubicon_level_note_controller.gd"
const HANDLER := "res://addons/rubicon_mania/scripts/rubicon_level_mania_note_handler.gd"
const RESULT := "res://addons/rubicon/scripts/data/game/rubicon_level_note_hit_result.gd"

const LANES := 8
const NOTES_PER_LANE := 40

var _failures: int = 0
var _checks: int = 0
var _steps: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var controller: Control = load(CONTROLLER).new()
	var handler_script: GDScript = load(HANDLER)
	var result_script: GDScript = load(RESULT)

	var handlers: Array = []
	for lane in LANES:
		var handler: Control = handler_script.new()
		handler.results.resize(NOTES_PER_LANE)
		handler.note_hit_index = 0
		for i in NOTES_PER_LANE:
			var r: RefCounted = result_script.new(handler)
			r.data_index = i
			# Interleaved across lanes, ascending overall.
			r.time_when_hit = float(i) * 100.0 + float(lane) * 11.0
			r.scoring_value = 1.0
			r.scoring_rating = 1
			r.scoring_hit = 2
			handler.results[i] = r
		handlers.append(handler)
		controller.note_handlers["lane%d" % lane] = handler

	_check("ocho lanes montados", controller.note_handlers.size() == LANES)

	# Walk the song: one note per lane per beat, with the awkward cases mixed
	# in at fixed points so a failure is reproducible.
	for beat in NOTES_PER_LANE:
		for lane in LANES:
			var handler: Control = handlers[lane]

			if beat == 12 and lane == 3:
				# A miss: hit_note() dates it a second late, so it arrives
				# behind notes that were hit after it.
				handler.results[beat].time_when_hit += 1000.0
				handler.results[beat].scoring_rating = 6

			if beat == 20 and lane == 5:
				# A hold begins: counted while incomplete.
				handler.results[beat].scoring_hit = 1
				_compare(controller, "hold empieza (beat %d)" % beat)
				# ...and then resolves, taking the range backwards.
				handler.results[beat].scoring_hit = 2

			handler.note_hit_index = beat + 1
			_compare(controller, "beat %d lane %d" % [beat, lane])

		if beat == 27:
			# A rewind: every lane steps back four notes.
			for handler in handlers:
				handler.note_hit_index = maxi(0, handler.note_hit_index - 4)
			_compare(controller, "rebobinado en beat %d" % beat)

	_check("se compararon todos los pasos", _steps > 300, "%d pasos" % _steps)

	for handler in handlers:
		handler.free()
	controller.free()

	print("")
	if _checks < 2:
		print("FALLO: solo %d de 2 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el orden cacheado es el mismo que el ordenado")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The original function's ordering, verbatim, as the thing to match.
func _reference(controller: Control) -> Array:
	var results: Array = []
	for key in controller.note_handlers:
		var handler: Control = controller.note_handlers[key]
		if handler.note_hit_index >= handler.results.size():
			results.append_array(handler.results)
			continue

		var current: RefCounted = handler.results[handler.note_hit_index]
		var target: int = handler.note_hit_index
		if current != null and current.scoring_hit == 1:
			target += 1

		for i in target:
			results.append(handler.results[i])

	results.sort_custom(func(x, y): return x.time_when_hit < y.time_when_hit)
	return results

func _compare(controller: Control, label: String) -> void:
	_steps += 1
	var want: Array = _reference(controller)
	var got: Array = controller._time_ordered_results()

	if want.size() != got.size():
		_fail("%s: %d elementos, se esperaban %d" % [label, got.size(), want.size()])
		return

	# Element for element. Ties in time_when_hit are the one place the two may
	# legitimately differ - sort_custom is not stable - so those compare by
	# time rather than by identity.
	for i in want.size():
		if want[i] == got[i]:
			continue
		if is_equal_approx(want[i].time_when_hit, got[i].time_when_hit):
			continue
		_fail("%s: posicion %d tiene t=%.1f, se esperaba t=%.1f"
			% [label, i, got[i].time_when_hit, want[i].time_when_hit])
		return

	# And the order itself has to be non-decreasing, which is the property the
	# combo walk depends on.
	for i in range(1, got.size()):
		if got[i].time_when_hit < got[i - 1].time_when_hit:
			_fail("%s: desordenado en %d (%.1f tras %.1f)"
				% [label, i, got[i].time_when_hit, got[i - 1].time_when_hit])
			return

func _fail(message: String) -> void:
	if _failures < 6:
		print("  FALLO %s" % message)
	_failures += 1

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
