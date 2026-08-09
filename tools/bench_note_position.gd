extends SceneTree

## Times what RubiconLevelManiaNote._process asks the chart for on every
## frame, per note.
##
## Each visible note calls get_graphical_start_position_relative(now), which
## is two linear scans over the chart's scroll velocities plus a
## starting_row.section.chart property chain - and half of it,
## get_graphical_start_position(), depends only on the note's own row and so
## is the same answer every frame for the whole song. The other half asks for
## the position at `now`, which is the same answer for every note in the
## frame.
##
## Run with:
##   godot --headless --path . --script tools/bench_note_position.gd

const CHART := "res://lullaby_mod/songs/monochrome/data/chart_monochrome_ply.tres"
const META := "res://lullaby_mod/songs/monochrome/data/meta_monochrome.tres"

## Roughly the census peak for Monochrome, times a few hundred frames.
const NOTES := 24
const FRAMES := 600

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var chart: Resource = load(CHART)
	if chart == null:
		print("FALLO: no pude cargar %s" % CHART)
		quit(1)
		return

	var meta: Resource = load(META)
	if meta == null:
		print("FALLO: no pude cargar %s" % META)
		quit(1)
		return

	# Rows only know their section and their millisecond time once the chart
	# has been walked against the song's time changes - which is what
	# RubiconLevelNoteController does before any of this is asked for.
	chart.initialize(meta.time_changes)

	# The same call the handler makes to fill its own data array, so the
	# notes carry the row and section links their position math needs.
	var lane: Array = chart.get_notes_of_id("mania_lane0")
	if lane.size() < NOTES:
		print("FALLO: la lane solo dio %d notas, esperaba %d" % [lane.size(), NOTES])
		quit(1)
		return

	var notes: Array = lane.slice(0, NOTES)

	print("chart      : %s" % CHART)
	print("velocities : %d" % chart.scroll_velocities.size())
	print("notas      : %d, %d frames" % [NOTES, FRAMES])
	print("")

	# What happens today.
	var began: int = Time.get_ticks_usec()
	var sink: float = 0.0
	for frame in FRAMES:
		var now: float = float(frame) * 16.666
		for note in notes:
			sink += note.get_graphical_start_position_relative(now)
	var current: int = Time.get_ticks_usec() - began

	# The same answer with the constant half hoisted out of the loop and the
	# "where is the playhead" half asked once per frame instead of once per
	# note.
	var starts: Array[float] = []
	for note in notes:
		starts.append(note.get_graphical_start_position())

	began = Time.get_ticks_usec()
	var sink2: float = 0.0
	for frame in FRAMES:
		var now: float = float(frame) * 16.666
		var here: float = RubiChartScrollVelocity.get_graphic_position_at_millisecond(
			chart.scroll_velocities, now)
		for i in NOTES:
			sink2 += starts[i] - here
	var hoisted: int = Time.get_ticks_usec() - began

	if not is_equal_approx(sink, sink2):
		print("FALLO: las dos formas no dan el mismo resultado (%f vs %f)" % [sink, sink2])
		quit(1)
		return

	print("  como esta hoy : %7.3f ms/frame  (%d us en total)" % [
		float(current) / FRAMES / 1000.0, current])
	print("  hoisted        : %7.3f ms/frame  (%d us en total)" % [
		float(hoisted) / FRAMES / 1000.0, hoisted])
	print("  ahorro         : %7.3f ms/frame  (%.0f%%)" % [
		float(current - hoisted) / FRAMES / 1000.0,
		100.0 * float(current - hoisted) / float(current)])
	quit(0)
