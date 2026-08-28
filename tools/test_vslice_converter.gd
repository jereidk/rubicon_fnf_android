extends SceneTree

## Runs the V-Slice converter on Animania's phone-call and checks what it
## produced against the chart's own JSON.
##
## Running it is not the point - a converter that runs and emits an empty
## chart looks exactly like one that works. So every number here is derived
## twice: once by reading the source JSON in this script, and once by reading
## the .tres the converter wrote. They have to agree.
##
## The one that matters most is the side split. V-Slice's `d` is a lane AND a
## side (0-3 opponent, 4-7 player), and reading it as a plain lane index puts
## every player note on the opponent's strumline - which raises no error,
## produces a full-looking chart, and plays itself.
##
## Run with:
##   godot --headless --path . --script tools/test_vslice_converter.gd

const CONVERTER := "res://addons/rubichart_converter/converters/vslice.gd"
const SONG_DIR := "res://animania_mod/source/songs/phone-call"
const CHART := SONG_DIR + "/phone-call-chart.json"
const META := SONG_DIR + "/phone-call-metadata.json"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# Ground truth, read from the source rather than hardcoded, so editing the
	# slice moves the expectation with it.
	var chart_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART))
	var meta_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META))
	_check(chart_json != null and meta_json != null, "el chart y la metadata se leen")
	if chart_json == null or meta_json == null:
		_finish()
		return

	var difficulties: Array = chart_json["notes"].keys()
	_check(difficulties.size() == 1, "una sola dificultad (%s)" % [difficulties])
	var source_notes: Array = chart_json["notes"][difficulties[0]]

	var want_opponent: int = 0
	var want_player: int = 0
	var want_holds: int = 0
	for n: Dictionary in source_notes:
		if int(n.get("d", 0)) >= 4:
			want_player += 1
		else:
			want_opponent += 1
		if float(n.get("l", 0.0)) > 0.0:
			want_holds += 1

	print("  fuente: %d notas -> oponente %d / jugador %d, %d holds" % [
		source_notes.size(), want_opponent, want_player, want_holds])

	# Convert.
	var converter: GDScript = load(CONVERTER)
	_check(converter != null, "el convertidor carga")
	if converter == null:
		_finish()
		return
	converter.convert_chart([ProjectSettings.globalize_path(CHART),
		ProjectSettings.globalize_path(META)] as Array[String])

	# And read back what it wrote.
	var meta_res: RubiconLevelMetadata = ResourceLoader.load(
		SONG_DIR + "/Meta.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(meta_res != null, "Meta.tres existe")
	if meta_res != null:
		_check(meta_res.time_changes.size() == meta_json["timeChanges"].size(),
			"tantos cambios de tempo como la metadata (%d)" % meta_res.time_changes.size())
		var first: RubiconTimeChange = meta_res.time_changes[0]
		var src_first: Dictionary = meta_json["timeChanges"][0]
		_check(is_equal_approx(first.bpm, float(src_first["bpm"])),
			"bpm %.1f == %.1f" % [first.bpm, float(src_first["bpm"])])
		_check(first.time_signature_numerator == int(src_first["n"])
			and first.time_signature_denominator == int(src_first["d"]),
			"compás %d/%d" % [first.time_signature_numerator, first.time_signature_denominator])

	var opponent: RubiChart = _load_chart("Opponent")
	var player: RubiChart = _load_chart("Player")
	_check(opponent != null and player != null, "los dos strumlines se escribieron")
	if opponent == null or player == null:
		_finish()
		return

	var got_opponent: int = _count_starts(opponent)
	var got_player: int = _count_starts(player)
	_check(got_opponent == want_opponent,
		"oponente: %d notas (esperadas %d)" % [got_opponent, want_opponent])
	_check(got_player == want_player,
		"jugador: %d notas (esperadas %d)" % [got_player, want_player])

	# Holds survive as note ENDS. Losing them is the other silent failure:
	# the chart still has every note, they just all become taps.
	var got_holds: int = _count_ends(opponent) + _count_ends(player)
	_check(got_holds == want_holds,
		"holds: %d (esperados %d)" % [got_holds, want_holds])

	# And nothing escaped into a fifth lane, which is what `d` without the
	# modulo would produce.
	var lanes: Dictionary = {}
	for chart: RubiChart in [opponent, player]:
		for section: RubiChartSection in chart.sections:
			for row: RubiChartRow in section.rows:
				for note: RubiChartNote in row.starts:
					lanes[note.id] = true
	var lane_ids: Array = lanes.keys()
	lane_ids.sort()
	_check(lane_ids.size() <= 4, "solo cuatro carriles: %s" % [lane_ids])

	_finish()


func _load_chart(side: String) -> RubiChart:
	var path: String = "%s/phone-call_%s.tres" % [SONG_DIR, side]
	if not FileAccess.file_exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RubiChart


func _count_starts(chart: RubiChart) -> int:
	var total: int = 0
	for section: RubiChartSection in chart.sections:
		for row: RubiChartRow in section.rows:
			total += row.starts.size()
	return total


func _count_ends(chart: RubiChart) -> int:
	var total: int = 0
	for section: RubiChartSection in chart.sections:
		for row: RubiChartRow in section.rows:
			total += row.ends.size()
	return total


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK   %s" % label)
		return
	_failures += 1
	print("  FAIL %s" % label)


func _finish() -> void:
	print("vslice converter: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
