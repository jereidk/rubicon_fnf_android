@tool
class_name RubiChartSection extends Resource

@export var measure : int
@export var rows : Array[RubiChartRow]

## The chart this section belongs to, held weakly.
##
## A chart owns its sections through its own sections array, so a section
## owning the chart back is a reference cycle - and Resource is RefCounted,
## so a cycle never reaches zero. This one leaked every chart the game ever
## loaded. See RubiChartNote.starting_row for the measurement.
var chart : RubiChart:
	get:
		return _chart.get_ref() if _chart != null else null
	set(value):
		_chart = weakref(value) if value != null else null

var _chart : WeakRef
