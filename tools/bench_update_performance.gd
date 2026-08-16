extends SceneTree

## Which of update_performance()'s four passes actually costs the 20ms.
##
## The device log says the lanes' _process grows from 1.0ms to 19.9ms across
## one Monochrome run - a 20x growth with song progress, which is the
## signature of the O(n log n)-per-note-hit that function performs. But
## "somewhere in that function" is not a target, and this project has twice
## optimised the wrong half of something on a shape that looked right.
##
## So: four passes, timed separately, at note counts a real chart reaches.
##
##   1. build     - append every handler's results into one array
##   2. sort      - sort_custom by time_when_hit, a GDScript comparator
##   3. combo     - walk in time order for total_value and the combo run
##   4. tally     - the second, nested walk for judgment counts and accuracy
##
## Run with:
##   godot --headless --path . --script tools/bench_update_performance.gd

const RESULT := "res://addons/rubicon/scripts/data/game/rubicon_level_note_hit_result.gd"

## Lanes in a Monochrome-shaped level: four player, four opponent.
const HANDLERS := 8

## Notes hit so far, which is what n is. A chart of a few thousand notes
## reaches the top of this range by its last minute.
const SIZES := [200, 600, 1200, 2400]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var script: GDScript = load(RESULT)
	print("%8s %10s %10s %10s %10s %10s" % ["notas", "build", "sort", "combo", "tally", "TOTAL"])

	for n: int in SIZES:
		# One flat pool standing in for the handlers' results arrays, built
		# the way a song builds them: ascending time, spread across lanes.
		var pool: Array = []
		for i: int in n:
			var r: Object = script.new(null)
			r.data_index = i
			r.time_when_hit = float(i) * 8.0 + float(i % HANDLERS)
			r.scoring_value = 1.0
			r.scoring_rating = 1 + (i % 6)
			pool.append(r)

		var t0: int = Time.get_ticks_usec()
		var results: Array = []
		for r: Object in pool:
			results.append(r)
		var build: float = _ms(t0)

		t0 = Time.get_ticks_usec()
		results.sort_custom(script.compare_results_by_time_hit)
		var sort: float = _ms(t0)

		t0 = Time.get_ticks_usec()
		var total_value: float = 0.0
		var combo: int = 0
		var highest: int = 0
		var breaks: Dictionary = {}
		for r: Object in results:
			total_value += r.scoring_value
			if breaks.has(r.data_index):
				combo = 0
				continue
			if r.scoring_rating >= 4:
				combo = 0
			else:
				combo += 1
				if combo > highest:
					highest = combo
		var combo_ms: float = _ms(t0)

		t0 = Time.get_ticks_usec()
		var tally: Array[int] = [0, 0, 0, 0, 0, 0]
		var accuracy: float = 0.0
		for r: Object in pool:
			accuracy += 1.0
			tally[r.scoring_rating - 1] += 1
		var tally_ms: float = _ms(t0)

		print("%8d %9.2fms %9.2fms %9.2fms %9.2fms %9.2fms" % [n, build, sort, combo_ms, tally_ms,
			build + sort + combo_ms + tally_ms])

	print("")
	print("Un frame a 60fps son 16.7ms, y esto corre una vez por CADA nota que cae.")
	print("")
	await _compare_orderings(script)
	quit(0)

## The same work the way a song actually asks for it: one call per note that
## lands, so the cost that matters is the whole run, not one call.
func _compare_orderings(script: GDScript) -> void:
	const CONTROLLER := "res://addons/rubicon/scripts/scene/game/rubicon_level_note_controller.gd"
	const HANDLER := "res://addons/rubicon_mania/scripts/rubicon_level_mania_note_handler.gd"

	print("%8s %14s %14s %10s" % ["notas", "build+sort", "cacheado", "mejora"])
	for n: int in SIZES:
		var controller: Control = load(CONTROLLER).new()
		var handler_script: GDScript = load(HANDLER)
		var handlers: Array = []
		var per_lane: int = int(ceil(float(n) / float(HANDLERS)))

		for lane: int in HANDLERS:
			var handler: Control = handler_script.new()
			handler.results.resize(per_lane)
			handler.note_hit_index = 0
			for i: int in per_lane:
				var r: RefCounted = script.new(handler)
				r.data_index = i
				r.time_when_hit = float(i) * 100.0 + float(lane) * 11.0
				r.scoring_value = 1.0
				r.scoring_rating = 1
				r.scoring_hit = 2
				handler.results[i] = r
			handlers.append(handler)
			controller.note_handlers["lane%d" % lane] = handler

		# Old: rebuild and re-sort on every note.
		var t0: int = Time.get_ticks_usec()
		for beat: int in per_lane:
			for lane: int in HANDLERS:
				handlers[lane].note_hit_index = beat + 1
				var acc: Array = []
				for h: Control in handlers:
					for i: int in h.note_hit_index:
						acc.append(h.results[i])
				acc.sort_custom(script.compare_results_by_time_hit)
		var old_ms: float = _ms(t0)

		for lane: int in HANDLERS:
			handlers[lane].note_hit_index = 0

		t0 = Time.get_ticks_usec()
		for beat: int in per_lane:
			for lane: int in HANDLERS:
				handlers[lane].note_hit_index = beat + 1
				controller._time_ordered_results()
		var new_ms: float = _ms(t0)

		print("%8d %13.1fms %13.1fms %9.1fx" % [n, old_ms, new_ms,
			old_ms / maxf(new_ms, 0.001)])

		for handler: Control in handlers:
			handler.free()
		controller.free()
		await process_frame

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0
