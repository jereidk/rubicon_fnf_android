@tool
class_name RubiconLevelNoteController extends Control

@export var chart : RubiChart:
	get:
		return _chart
	set(val):
		_chart = val
		_chart_dirty = true

@export var note_overrides : RubiconLevelNoteDatabase:
	get:
		return _override_note_database
	set(val):
		_override_note_database = val
		_reset_note_database()

@export var scroll_speed_multiplier : float = 1.0
@export var autoplay : bool = false
@export var preview_as_autoplay : bool = true
@export var inputs : RubiconLevelNoteInputMap

# TODO: These could probably be named better.
@export var disable_inputs: bool = false

## Timing offsets, both in milliseconds, restored from the mod's own Rubicon.
##
## offset_input shifts when a press is judged (the player's audio latency);
## offset_note_position shifts where notes are drawn (their video latency).
## They are deliberately separate: fixing a display delay by moving the
## judgment window would desync hits from the music.
##
## Without these the console's Offset and Visual Offset rows had nothing to
## drive - lullaby_song_settings.gd assigns both behind an `in` check, so
## they silently did nothing on this engine build.
@export_group("Offsets", "offset_")
@export var offset_input: float = 0.0
@export var offset_note_position: float = 0.0

@export_group("Performance", "performance_")
@export var performance_accuracy_percent: float = 100

@export_subgroup("Score", "performance_score_")
@export var performance_score_max: int = 1000000
@export var performance_score_value: int = 0

@export_subgroup("Combo", "performance_combo_")
@export var performance_combo_value: int = 0
@export var performance_combo_highest: int = 0

@export_subgroup("Hits", "performance_hits_")
@export var performance_hits_perfect : int
@export var performance_hits_great : int
@export var performance_hits_good : int
@export var performance_hits_okay : int
@export var performance_hits_bad : int
@export var performance_hits_miss :  int

var note_handlers : Dictionary[String, RubiconLevelNoteHandler]

var _chart : RubiChart
var _chart_dirty : bool = false

var _level : RubiconLevel

var _override_note_database : RubiconLevelNoteDatabase
var _internal_note_database : Dictionary[StringName, RubiconLevelNoteMetadata]

static var is_playtesting:bool

signal note_changed(result:RubiconLevelNoteHitResult, has_ending_row:bool)
signal performance_updated

signal handler_just_pressed(handler_name: StringName)
signal handler_just_released(handler_name: StringName)

func _init() -> void:
	set_process_internal(true)

func get_note_database() -> Dictionary[StringName, RubiconLevelNoteMetadata]:
	return _internal_note_database

func update_chart() -> void:
	var metadata : RubiconLevelMetadata = get_level_metadata()
	if metadata == null or metadata.time_changes.is_empty():
		return

	_chart.initialize(metadata.time_changes)
	for id in note_handlers:
		note_handlers[id].update_notes()

func get_level_clock() -> RubiconLevelClock:
	if _level != null:
		return _level.clock

	return null

func get_level_metadata() -> RubiconLevelMetadata:
	if _level != null:
		return _level.metadata

	return null

func get_hit_count() -> int:
	var count : int = 0
	for key: String in note_handlers:
		var handler : RubiconLevelNoteHandler = note_handlers[key]
		count += handler.note_hit_index

	return count

## Every hit result so far, in the order they were hit.
##
## Kept across calls. update_performance() runs once per note that lands, and
## it used to rebuild this array and re-sort it from scratch every time, which
## is O(n log n) per note and therefore O(n squared log n) per song. Benched
## against real result objects on a desktop runner, the sort alone is 60-63%
## of the whole function at every size and it is the superlinear term:
##
##     notes     build      sort     combo     tally     TOTAL
##       200    0.05ms    0.40ms    0.09ms    0.06ms    0.59ms
##      1200    1.19ms    3.26ms    0.58ms    0.36ms    5.39ms
##      2400    2.63ms    8.05ms    1.27ms    0.91ms   12.85ms
##
## A phone is several times slower again, which is how Monochrome's device log
## measured the lanes' own _process growing from 1.0ms early in the song to
## 19.9ms by the end - a 20x degradation with nothing but progress.
##
## Caching it is safe because this array carries order and nothing else. The
## order depends only on time_when_hit, which hit_note() writes once; reset()
## rewrites flags, scoring_value, scoring_rating and scoring_hit but never the
## time, and break_combo_indexes changes which notes break the run without
## moving anything. Both callers below still walk these objects live on every
## call, so every one of those mutations is still picked up - what is cached
## is where each result sits, never what it is worth.
##
## Ties in time_when_hit resolve differently than sort_custom happened to
## resolve them. sort_custom is not stable, so that order was already
## arbitrary between two notes hit on the same millisecond.
var _perf_order : Array[RubiconLevelNoteHitResult] = []

## How much of each handler's results array is already in _perf_order, so a
## call only has to look at what arrived since the last one.
var _perf_folded : Dictionary[String, int] = {}

## The set in time order, maintained rather than rebuilt.
##
## Rebuilds outright when a handler goes backwards - a rewind, a reset that
## takes a note out of HIT_INCOMPLETE, or a different set of handlers
## entirely. That fallback is the original function verbatim, so the worst
## case is what this used to cost every time.
func _time_ordered_results() -> Array[RubiconLevelNoteHitResult]:
	var rebuild : bool = _perf_folded.size() != note_handlers.size()
	var targets : Dictionary[String, int] = {}

	for key: String in note_handlers:
		var handler : RubiconLevelNoteHandler = note_handlers[key]
		targets[key] = _folded_target_of(handler)
		if not rebuild and (not _perf_folded.has(key) or targets[key] < _perf_folded[key]):
			rebuild = true

	if rebuild:
		_perf_order.clear()
		_perf_folded.clear()
		for key: String in note_handlers:
			var handler : RubiconLevelNoteHandler = note_handlers[key]
			for i in targets[key]:
				_perf_order.append(handler.results[i])
			_perf_folded[key] = targets[key]

		_perf_order.sort_custom(RubiconLevelNoteHitResult.compare_results_by_time_hit)
		return _perf_order

	var arrived : Array[RubiconLevelNoteHitResult] = []
	for key: String in note_handlers:
		var handler : RubiconLevelNoteHandler = note_handlers[key]
		for i in range(_perf_folded[key], targets[key]):
			arrived.append(handler.results[i])
		_perf_folded[key] = targets[key]

	if arrived.is_empty():
		return _perf_order

	# Almost always a straight append: a note hit now is later than every note
	# hit before it. The exception is a miss, whose time_when_hit is pushed a
	# second into the future by hit_note(), so it can land behind a real hit
	# that follows it.
	arrived.sort_custom(RubiconLevelNoteHitResult.compare_results_by_time_hit)
	if _perf_order.is_empty() or not RubiconLevelNoteHitResult.compare_results_by_time_hit(
			arrived[0], _perf_order[_perf_order.size() - 1]):
		_perf_order.append_array(arrived)
		return _perf_order

	_merge_into_order(arrived)
	return _perf_order

## The end of the range of a handler's results that counts as hit.
##
## note_hit_index, plus the note being held right now - a hold in progress has
## already scored its head and the original counted it, so it stays counted.
func _folded_target_of(handler : RubiconLevelNoteHandler) -> int:
	if handler.note_hit_index >= handler.results.size():
		return handler.results.size()

	var current_result : RubiconLevelNoteHitResult = handler.results[handler.note_hit_index]
	if current_result != null and current_result.scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE:
		return handler.note_hit_index + 1

	return handler.note_hit_index

## Merges an already-sorted run into the already-sorted cache, backwards from
## the end so each insertion point is found in one pass. Only reached when a
## late-timed miss has to slot in behind notes hit after it.
func _merge_into_order(arrived : Array[RubiconLevelNoteHitResult]) -> void:
	var merged : Array[RubiconLevelNoteHitResult] = []
	merged.resize(_perf_order.size() + arrived.size())

	var a : int = _perf_order.size() - 1
	var b : int = arrived.size() - 1
	for out in range(merged.size() - 1, -1, -1):
		if b < 0 or (a >= 0 and RubiconLevelNoteHitResult.compare_results_by_time_hit(
				arrived[b], _perf_order[a])):
			merged[out] = _perf_order[a]
			a -= 1
		else:
			merged[out] = arrived[b]
			b -= 1

	_perf_order = merged

func update_performance() -> void:
	var total_value: float = 0.0
	var note_count: int = 0
	var current_combo: int = 0
	var highest_combo: int = 0

	for key: String in note_handlers:
		note_count += note_handlers[key].data.size()

	var results: Array[RubiconLevelNoteHitResult] = _time_ordered_results()
	for result in results:
		total_value += result.scoring_value

		# A misplay breaks the combo at the note it happened next to, even
		# though that note's own judgment may be fine.
		if result.handler.break_combo_indexes.has(result.data_index):
			current_combo = 0
			continue

		match result.scoring_rating:
			RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY, RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD, RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS:
				current_combo = 0
			_:
				current_combo += 1
				if current_combo > highest_combo:
					highest_combo = current_combo

	performance_combo_value = current_combo
	performance_combo_highest = highest_combo

	if performance_combo_highest == note_count and floori(total_value) == note_count:
		performance_score_value = performance_score_max
	else:
		var base_score: float = (total_value / note_count) * performance_score_max * 0.5
		var bonus_score: float = sqrt((float(performance_combo_highest) / note_count) * 100.0) * performance_score_max * 0.05
		performance_score_value = floori(base_score + bonus_score)

	# _get_result_count_of_rating() previously ran once per judgment (6 calls),
	# each re-scanning every handler's whole hit history, plus a 7th identical
	# scan below for accuracy - all 7 walked the exact same
	# `for key in note_handlers: for i in handler.note_hit_index` range. Folded
	# into a single pass that tallies rating counts and accuracy together.
	var hits_perfect: int = 0
	var hits_great: int = 0
	var hits_good: int = 0
	var hits_okay: int = 0
	var hits_bad: int = 0
	var hits_miss: int = 0
	var total_hits: float = 0.0
	var accuracy_hits: float = 0.0
	for key: String in note_handlers:
		var handler : RubiconLevelNoteHandler = note_handlers[key]
		for i: int in handler.note_hit_index:
			var result: RubiconLevelNoteHitResult = handler.results[i]
			accuracy_hits += result.get_accuracy_value()
			total_hits += 1

			match result.scoring_rating:
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT:
					hits_perfect += 1
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_GREAT:
					hits_great += 1
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_GOOD:
					hits_good += 1
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY:
					hits_okay += 1
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD:
					hits_bad += 1
				RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS:
					hits_miss += 1

	performance_hits_perfect = hits_perfect
	performance_hits_great = hits_great
	performance_hits_good = hits_good
	performance_hits_okay = hits_okay
	performance_hits_bad = hits_bad
	performance_hits_miss = hits_miss

	if total_hits == 0.0:
		performance_accuracy_percent = 100.0
	else:
		performance_accuracy_percent = (accuracy_hits / total_hits) * 100

	performance_updated.emit()

func _reset_note_database() -> void:
	_internal_note_database.clear()
	if _override_note_database != null:
		for key in _override_note_database.defines:
			_internal_note_database[key] = _override_note_database.defines[key]

	var default_database_path : String = ProjectSettings.get_setting("rubicon/defaults/note_database")
	if default_database_path.is_empty() or not ResourceLoader.exists(default_database_path):
		return

	var resource : Resource = ResourceLoader.load(default_database_path)
	if resource is not RubiconLevelNoteDatabase:
		update_chart()
		return

	for key in resource.defines:
		if _internal_note_database.has(key):
			continue

		_internal_note_database[key] = resource.defines[key]

	update_chart()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_INTERNAL_PROCESS:
			if _chart_dirty:
				if _chart != null:
					update_chart()

				_chart_dirty = false
		NOTIFICATION_PARENTED:
			if _level != null:
				_level.changed.disconnect(update_chart)
				_level = null

			var parent : Node = get_parent()
			while parent != null:
				if parent is RubiconLevel:
					_level = parent
					_level.changed.connect(update_chart)
					break

				parent = parent.get_parent()

func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	if property_name.begins_with("performance_"):
		match property_name:
			"performance_score_max":
				property.usage = PROPERTY_USAGE_DEFAULT
			_:
				property.usage = PROPERTY_USAGE_EDITOR

func should_autoplay() -> bool:
	return autoplay or (preview_as_autoplay and Engine.is_editor_hint() and !is_playtesting)

func _input(event: InputEvent) -> void:
	if disable_inputs:
		return

	if should_autoplay() or event.is_echo() or inputs == null or not inputs.has_event_registered(event):
		return

	var id : StringName = inputs.get_handler_id_for_event(event)
	if not note_handlers.has(id):
		return

	var handler : RubiconLevelNoteHandler = note_handlers[id]
	if not handler._should_process():
		return

	if event.is_pressed():
		note_handlers[id]._press(event)
	else:
		note_handlers[id]._release(event)
