@tool
class_name RubiChartScrollVelocity extends Resource

@export var measure_time : float
@export_range(0, 100, 0.001, "or_greater") var multiplier : float = 1

var millisecond_time : float
var position : float

func initialize(time_changes : Array[RubiconTimeChange]) -> void:
	millisecond_time = RubiconTimeChange.get_millisecond_at_measure(time_changes, measure_time)
	position = millisecond_time

func initialize_with_previous(time_changes : Array[RubiconTimeChange], last_velocity : RubiChartScrollVelocity) -> void:
	initialize(time_changes)
	position = last_velocity.position + ((millisecond_time - last_velocity.millisecond_time) * last_velocity.multiplier)

## The last answer this gave, so that asking the same question again is free.
##
## Every note on screen asks where the playhead is on every frame, and within
## a frame that is one question with one answer - the notes of a handler are
## processed back to back, so a single slot catches all of them. is_same()
## rather than == because the interesting thing is whether it is literally
## the same velocity list, which is O(1); == would walk it.
static var _memo_velocities : Array[RubiChartScrollVelocity]
static var _memo_time : float = NAN
static var _memo_position : float = 0.0

## Initialising a chart rewrites position and millisecond_time on the very
## objects the memo answered about, so the same list at the same time can
## legitimately mean something different afterwards.
static func clear_memo() -> void:
	_memo_velocities = []
	_memo_time = NAN
	_memo_position = 0.0

static func get_graphic_position_at_millisecond(velocities : Array[RubiChartScrollVelocity], millisecond_time : float) -> float:
	if millisecond_time == _memo_time and is_same(velocities, _memo_velocities):
		return _memo_position

	var vel_index: int = velocities.size() - 1
	for i in velocities.size():
		if velocities[i].millisecond_time > millisecond_time:
			vel_index = i - 1
			break

	var velocity: RubiChartScrollVelocity = velocities[vel_index]
	var position_here: float = velocity.position + ((millisecond_time - velocity.millisecond_time) * velocity.multiplier)

	_memo_velocities = velocities
	_memo_time = millisecond_time
	_memo_position = position_here
	return position_here
