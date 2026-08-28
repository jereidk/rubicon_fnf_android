## Converts a V-Slice chart (Funkin' 0.3+, and every mod built on it) to Rubicon.
##
## The format splits in two: `<song>-chart.json` holds notes and events,
## `<song>-metadata.json` holds tempo and play data. Hence needs_metadata().
##
## Two things about it are not obvious from the JSON and decide the mapping:
##
## 1. `d` is not a lane, it is a lane AND a side. 0-3 are the opponent's four
##    lanes and 4-7 are the player's, so the lane is `d % 4` and the side is
##    `d >= 4`. Reading it as a plain lane index silently puts every player
##    note on the opponent's strumline and the song plays itself.
## 2. `notes` is keyed by difficulty, so one chart file carries several
##    charts. Legacy Funkin' had one per file, which is why funkin.gd can
##    save a single pair of .tres and this cannot.
##
## Written against Animania 0.6's `phone-call`: 362 notes, 180 of them holds,
## one difficulty ("standart"), 103 events, one time change at 152bpm 4/4.

static func get_new_parameters() -> Dictionary[String, Variant]:
	return Dictionary()

static func needs_metadata() -> bool:
	return true

static func convert_chart(args: Array[String]) -> void:
	if args.size() < 2:
		push_error("VSlice: needs both the chart and the metadata file")
		return

	var chart_path: String = args[0]
	var meta_path: String = args[1]
	var directory: String = chart_path.get_base_dir()

	# `<song>-chart.json` -> `<song>`, so the output is not named after the
	# input's own "-chart" suffix.
	var file_name: String = chart_path.get_file().get_basename()
	if file_name.ends_with("-chart"):
		file_name = file_name.left(file_name.length() - 6)

	var chart_parse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chart_path))
	var meta_parse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if chart_parse == null or meta_parse == null:
		push_error("VSlice: could not parse the chart or the metadata")
		return

	var metadata: RubiconLevelMetadata = _build_metadata(meta_parse)
	ResourceSaver.save(metadata, "%s/Meta.tres" % [directory])

	var notes_by_difficulty: Dictionary = chart_parse.get("notes", {})
	var single: bool = notes_by_difficulty.size() <= 1

	for difficulty: String in notes_by_difficulty.keys():
		var opponent: RubiChart = RubiChart.new()
		var player: RubiChart = RubiChart.new()

		for note_data: Dictionary in notes_by_difficulty[difficulty]:
			var direction: int = int(note_data.get("d", 0))
			var starting_ms: float = float(note_data.get("t", 0.0))
			var length_ms: float = float(note_data.get("l", 0.0))

			var measure_time: float = RubiconTimeChange.get_measure_at_millisecond(
				metadata.time_changes, starting_ms)
			var measure_length: float = RubiconTimeChange.get_measure_at_millisecond(
				metadata.time_changes, starting_ms + length_ms) - measure_time

			var note: RubiChartNote = RubiChartNote.new()
			note.id = "mania_lane%s" % [direction % 4]

			# V-Slice calls it `k`, and an empty string means the ordinary
			# note - it must not become a note type named "".
			var kind: String = str(note_data.get("k", ""))
			if not kind.is_empty():
				note.type = kind

			var target: RubiChart = player if direction >= 4 else opponent
			chart_add_note_at_measure_time(target, note, measure_time, measure_length)

		var suffix: String = "" if single else "-%s" % difficulty
		ResourceSaver.save(opponent, "%s/%s%s_Opponent.tres" % [directory, file_name, suffix])
		ResourceSaver.save(player, "%s/%s%s_Player.tres" % [directory, file_name, suffix])


## Tempo comes from the metadata's `timeChanges`, which is already a list -
## unlike Codename, where the first change is loose fields on the metadata and
## the rest are chart events.
static func _build_metadata(meta_parse: Dictionary) -> RubiconLevelMetadata:
	var metadata: RubiconLevelMetadata = RubiconLevelMetadata.new()
	var changes: Array = meta_parse.get("timeChanges", [])

	if changes.is_empty():
		# A chart with no timeChanges is malformed, but refusing to convert it
		# is worse than assuming the format's own default.
		var fallback: RubiconTimeChange = RubiconTimeChange.new()
		fallback.bpm = 100.0
		fallback.measure = 0
		fallback.time_signature_numerator = 4
		fallback.time_signature_denominator = 4
		metadata.time_changes.append(fallback)
		push_warning("VSlice: no timeChanges in the metadata, assuming 100bpm 4/4")
		return metadata

	for entry: Dictionary in changes:
		var change: RubiconTimeChange = RubiconTimeChange.new()
		change.bpm = float(entry.get("bpm", 100.0))
		change.time_signature_numerator = int(entry.get("n", 4))
		change.time_signature_denominator = int(entry.get("d", 4))

		# The first change anchors the timeline at measure 0; every later one
		# is placed by the milliseconds of the changes already accepted, which
		# is why this cannot be done in one pass over the whole array.
		if metadata.time_changes.is_empty():
			change.measure = 0
		else:
			change.measure = RubiconTimeChange.get_measure_at_millisecond(
				metadata.time_changes, float(entry.get("t", 0.0)))

		metadata.time_changes.append(change)
		RubiconTimeChange.update(metadata.time_changes)

	return metadata


static func is_equal_approx_with_tolerance(a: float, b: float, tolerance: float) -> bool:
	if a == b:
		return true

	return absf(a - b) < tolerance


## Verbatim in shape from codename.gd: measure time -> the addon's quantised
## (measure, offset, quant) triple. Kept as its own copy rather than shared
## because every converter in this directory carries it and diverging from
## that would be a bigger change than this one.
static func chart_add_note_at_measure_time(chart: RubiChart, note: RubiChartNote,
		measure_time: float, length: float) -> void:
	var base_measure: int = floori(measure_time)
	var measure_offset: float = measure_time - base_measure

	var offset: int = clampi(roundi(measure_offset * RubiChart.quants.back()), 0, RubiChart.quants.back() - 1)
	var quant: RubiChart.Quant = RubiChart.quants.back()
	for cur_quant in RubiChart.quants:
		var result: float = measure_offset * cur_quant
		var is_snapped: bool = fmod(result, 1) == 0
		if not is_snapped:
			var rounded_result: int = roundi(result)
			if not is_equal_approx_with_tolerance(result, rounded_result, 0.1):
				continue

			offset = rounded_result
			quant = cur_quant
			break

		offset = result
		quant = cur_quant
		break

	RubiChartEditorFunctions.chart_add_note_start(chart, note, base_measure, offset, quant)
	if length <= 0:
		return

	base_measure = floori(measure_time + length)
	measure_offset = measure_time + length - base_measure

	offset = clampi(roundi(measure_offset * RubiChart.quants.back()), 0, RubiChart.quants.back() - 1)
	quant = RubiChart.quants.back()
	for cur_quant in RubiChart.quants:
		var result: float = measure_offset * cur_quant
		var is_snapped: bool = fmod(result, 1) == 0
		if not is_snapped:
			var rounded_result: int = roundi(result)
			if not is_equal_approx_with_tolerance(result, rounded_result, 0.1):
				continue

			offset = rounded_result
			quant = cur_quant
			break

		offset = result
		quant = cur_quant
		break

	RubiChartEditorFunctions.chart_add_note_end(chart, note, base_measure, offset, quant)
