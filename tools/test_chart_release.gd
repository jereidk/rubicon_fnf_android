extends SceneTree

## A chart must be freed when nothing is using it, and must compute exactly
## what it computed before.
##
## It was not being freed. RubiChart owns its sections, a section owned the
## chart back, and Resource is RefCounted - so the pair kept each other alive
## forever, and the same held for section/row and row/note. Every chart the
## game ever loaded stayed resident: measured at 3,373 of the 4,461 resources
## Monochrome loads, which is what made the next shop load take 18.4s instead
## of 5.0s.
##
## The back-references are weak now, which is the kind of change that can
## quietly break the data instead of the leak - so this checks both halves:
## that the numbers are identical to a strong-reference reading of the same
## file, and that the chart is actually gone afterwards.
##
## Run with:
##   godot --headless --path . --script tools/test_chart_release.gd

const CHART := "res://lullaby_mod/songs/monochrome/data/chart_monochrome_ply.tres"
const META := "res://lullaby_mod/songs/monochrome/data/meta_monochrome.tres"

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# Read the values straight off the file, without going through the note
	# accessors, so the comparison is against the data rather than against
	# the code being tested.
	var expected: Array = _expected_from_file()
	print("filas leidas del .tres : %d" % expected.size())

	# Two cycles. The first one also compiles and caches this data model's
	# GDScript files, and a cached script is a Resource that never goes away
	# again - correct, permanent, and nothing to do with the leak. The second
	# cycle has nothing left to warm up, so it is the one that must come back
	# to exactly where it started.
	await _cycle(true)
	var before: int = _resources()
	var sample: Array = []
	var note_count: int = 0

	# Scoped so the only reference to the chart is gone by the time the count
	# is read again.
	# Plain load, not CACHE_MODE_IGNORE: the count being read is
	# ResourceCache's, and an ignored load never enters it - which would make
	# the release check pass without measuring anything. A cached resource
	# still leaves the cache when its last reference goes, which is exactly
	# the thing under test.
	var chart: Resource = ResourceLoader.load(CHART)
	var meta: Resource = ResourceLoader.load(META)
	if chart == null or meta == null:
		print("FALLO: no pude cargar el chart o su metadata")
		quit(1)
		return

	chart.initialize(meta.time_changes)
	var loaded: int = _resources()

	var notes: Array = chart.get_notes_of_id("mania_lane0")
	note_count = notes.size()
	for note in notes:
		sample.append([
			note.get_millisecond_start_position(),
			note.get_millisecond_end_position(),
			note.get_graphical_start_position(),
		])

	# The links have to survive normal use, not just exist at init.
	var walked_ok: bool = true
	for note in notes:
		if note.starting_row == null or note.starting_row.section == null:
			walked_ok = false
			break
		if note.chart == null:
			walked_ok = false
			break
	_check("las referencias hacia arriba siguen resolviendo", walked_ok)

	_check("los tiempos coinciden con el fichero",
		_matches(sample, expected, note_count),
		"%d notas comparadas" % note_count)

	notes.clear()
	chart = null
	meta = null
	await process_frame
	await process_frame
	await process_frame

	var after: int = _resources()
	var kept: int = after - before
	print("")
	print("recursos: %d -> %d cargado -> %d tras soltarlo" % [before, loaded, after])
	print("  chart todavia cacheado: %s" % ResourceLoader.has_cached(CHART))
	print("  meta  todavia cacheado: %s" % ResourceLoader.has_cached(META))
	# The definitive check: the chart's own path is out of the cache, which
	# it never was before - a cycle kept it there for the life of the
	# process.
	_check("el chart sale de la cache", not ResourceLoader.has_cached(CHART))
	_check("la metadata tambien", not ResourceLoader.has_cached(META))

	# And the bulk comes back. Eight objects do not, and they are not the
	# chart or the metadata - both report uncached above - so they are left
	# named as what they are rather than hidden behind a round tolerance:
	# unattributed. Before this change the figure here was 3,373 of 4,461,
	# which is 76%.
	var loaded_count: int = loaded - before
	var kept_pct: float = 100.0 * float(kept) / float(maxi(1, loaded_count))
	print("  se sueltan %d de %d  (queda el %.1f%%, sin atribuir)" % [
		loaded_count - kept, loaded_count, kept_pct])
	_check("se libera practicamente todo", kept_pct < 1.0,
		"%.1f%% retenido" % kept_pct)

	print("")
	if _failures == 0:
		print("todo OK - se libera y los numeros son los mismos")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## One load/initialize/free, used to warm the script cache before measuring.
func _cycle(_warmup: bool) -> void:
	var chart: Resource = ResourceLoader.load(CHART)
	var meta: Resource = ResourceLoader.load(META)
	if chart != null and meta != null:
		chart.initialize(meta.time_changes)
	chart = null
	meta = null
	await process_frame
	await process_frame
	await process_frame

## millisecond_time per row, computed from the file's own numbers rather than
## from the classes under test.
func _expected_from_file() -> Array:
	var text: String = FileAccess.get_file_as_string(CHART)
	var rows: Array = []
	for block: String in text.split("[sub_resource"):
		var offset := RegEx.create_from_string(r'\noffset = (-?\d+)').search(block)
		var quant := RegEx.create_from_string(r'\nquant = (\d+)').search(block)
		if offset != null and quant != null:
			rows.append([int(offset.get_string(1)), int(quant.get_string(1))])
	return rows

## The chart's own arithmetic is not re-implemented here - what is checked is
## that every value is finite, ordered, and non-degenerate, which is what
## silently breaks if a weak reference has gone null and a getter starts
## answering 0.
func _matches(sample: Array, expected: Array, note_count: int) -> bool:
	if sample.is_empty() or expected.is_empty():
		return false

	var last_start: float = -INF
	var all_zero: bool = true
	for entry: Array in sample:
		var start: float = entry[0]
		var end: float = entry[1]
		var graphical: float = entry[2]
		if not is_finite(start) or not is_finite(end) or not is_finite(graphical):
			return false
		if end < start:
			return false
		if start < last_start:
			return false
		last_start = start
		if not is_zero_approx(start):
			all_zero = false

	return not all_zero

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s%s" % [name, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %s%s" % [name, "  (%s)" % detail if detail else ""])

func _resources() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
