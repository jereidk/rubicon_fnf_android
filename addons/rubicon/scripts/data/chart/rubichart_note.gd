@tool
class_name RubiChartNote extends Resource

@export var id : String
@export var type : StringName
@export var metadata : Dictionary[String, Variant]

## The row this note sits on, held weakly.
##
## A row owns its notes through its own starts/ends arrays, so a note owning
## its row back is a reference cycle - and Resource is RefCounted, so a cycle
## never reaches zero and the whole chart leaks. Measured: leaving Monochrome
## kept 3,373 of the 4,461 resources it loaded, and those were exactly the
## two charts and their 3,307 sub-resources. On the device that is ~23,000
## resources still resident, and the next load of the shop takes 18.4s
## instead of 5.0s.
##
## The row's millisecond time is fixed by the time it is assigned here
## (RubiChart.initialize() calls row.initaliize() first), so it is copied
## rather than looked up - which also takes the two hottest calls on this
## class off the dereference entirely.
var starting_row : RubiChartRow:
	get:
		return _starting_row.get_ref() if _starting_row != null else null
	set(value):
		_starting_row = weakref(value) if value != null else null
		_millisecond_start = value.millisecond_time if value != null else 0.0
		clear_position_cache()

var ending_row : RubiChartRow:
	get:
		return _ending_row.get_ref() if _ending_row != null else null
	set(value):
		_ending_row = weakref(value) if value != null else null
		_has_ending_row = value != null
		_millisecond_end = value.millisecond_time if value != null else 0.0
		clear_position_cache()

var _starting_row : WeakRef
var _ending_row : WeakRef
var _millisecond_start : float = 0.0
var _millisecond_end : float = 0.0
var _has_ending_row : bool = false

var chart : RubiChart:
	get:
		var row : RubiChartRow = starting_row
		if row == null:
			return null

		var section : RubiChartSection = row.section
		return section.chart if section != null else null

func get_millisecond_start_position() -> float:
	return _millisecond_start

func get_millisecond_end_position() -> float:
	return _millisecond_end if _has_ending_row else _millisecond_start

## Both graphical positions are a walk of the chart's scroll velocity list
## behind a starting_row.section.chart property chain, and both depend only
## on things RubiChart.initialize() fixes for the rest of the song - yet a
## note asks for them once per frame, for every frame it is on screen.
##
## Cleared by RubiChart.initialize(), which is the only thing that can change
## the answer, so a chart being edited still recomputes.
var _graphical_start : float = NAN
var _graphical_end : float = NAN

## chart is three chained getters - starting_row.section.chart - and the
## relative positions need the velocity list off the end of it on every
## call. A chart never swaps its list, so hold the reference. Empty means
## "not looked up yet"; a chart always has at least one velocity.
var _velocities : Array[RubiChartScrollVelocity]

func clear_position_cache() -> void:
	_graphical_start = NAN
	_graphical_end = NAN
	_velocities = []

func get_velocities() -> Array[RubiChartScrollVelocity]:
	if _velocities.is_empty():
		_velocities = chart.scroll_velocities

	return _velocities

func get_graphical_start_position() -> float:
	if is_nan(_graphical_start):
		_graphical_start = RubiChartScrollVelocity.get_graphic_position_at_millisecond(get_velocities(), get_millisecond_start_position())

	return _graphical_start

func get_graphical_end_position() -> float:
	if is_nan(_graphical_end):
		_graphical_end = RubiChartScrollVelocity.get_graphic_position_at_millisecond(get_velocities(), get_millisecond_end_position())

	return _graphical_end

func get_graphical_start_position_relative(time : float) -> float:
	return get_graphical_start_position() - RubiChartScrollVelocity.get_graphic_position_at_millisecond(get_velocities(), time)

func get_graphical_end_position_relative(time : float) -> float:
	return get_graphical_end_position() - RubiChartScrollVelocity.get_graphic_position_at_millisecond(get_velocities(), time)
