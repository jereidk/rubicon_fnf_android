@tool
class_name RubiChartRow extends Resource

@export var offset : int
@export var quant : RubiChart.Quant
@export var starts : Array[RubiChartNote]
@export var ends : Array[RubiChartNote]

## The section this row belongs to, held weakly.
##
## A section owns its rows through its own rows array, so a row owning the
## section back is a reference cycle - and Resource is RefCounted, so a cycle
## never reaches zero. See RubiChartNote.starting_row for the measurement.
##
## measure_time is still computed on assignment rather than on read: it
## depends only on the section's measure and this row's own offset, both
## fixed, so nothing needs the reference again afterwards.
var section : RubiChartSection :
	get:
		return _section.get_ref() if _section != null else null
	set(value):
		_section = weakref(value) if value != null else null
		if value != null:
			_measure_time = value.measure + (offset / float(quant))

var measure_time : float:
	get:
		return _measure_time

var millisecond_time : float:
	get:
		return _millisecond_time

var _section : WeakRef
var _measure_time : float
var _millisecond_time : float

func initaliize(time_changes : Array[RubiconTimeChange]) -> void:
	_millisecond_time = RubiconTimeChange.get_millisecond_at_measure(time_changes, measure_time)
	
	for start in starts:
		start.starting_row = self
	
	for end in ends:
		end.ending_row = self

func get_note_with_id(id : String, include_ends : bool = false) -> RubiChartNote:
	var valid_starts : Array[RubiChartNote] = starts.filter(func(x : RubiChartNote) -> bool: return x.id.ends_with(id))
	var note : RubiChartNote = null
	if not valid_starts.is_empty():
		note = valid_starts.front()
	
	if note == null and include_ends:
		var valid_ends : Array[RubiChartNote] = ends.filter(func(x : RubiChartNote) -> bool : return x.id.ends_with(id))
		
		if not valid_ends.is_empty():
			note = valid_ends.front()
	
	return note

func has_note_with_id(id : String, include_ends : bool = false) -> bool:
	return not starts.filter(func(x : RubiChartNote) -> bool : return x.id.ends_with(id)).is_empty() or (include_ends and not ends.filter(func(x : RubiChartNote) -> bool : return x.id.ends_with(id)).is_empty())
