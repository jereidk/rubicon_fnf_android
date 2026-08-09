@tool
class_name RubiChartNote extends Resource

@export var id : String
@export var type : StringName
@export var metadata : Dictionary[String, Variant]

var starting_row : RubiChartRow
var ending_row : RubiChartRow

var chart : RubiChart:
	get:
		return starting_row.section.chart

func get_millisecond_start_position() -> float:
	if not starting_row:
		return 0.0
	
	return starting_row.millisecond_time

func get_millisecond_end_position() -> float:
	if ending_row != null:
		return ending_row.millisecond_time
	
	return get_millisecond_start_position()

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
