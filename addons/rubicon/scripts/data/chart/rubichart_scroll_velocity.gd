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
## A WeakRef to the list's first entry, not the list itself. Holding the
## array would keep those velocity Resources alive past the song that owns
## them - the same kind of cycle-by-another-name that leaked whole charts,
## and not something a cache is allowed to do.
static var _memo_first : WeakRef
static var _memo_time : float = NAN
static var _memo_position : float = 0.0

## Initialising a chart rewrites position and millisecond_time on the very
## objects the memo answered about, so the same list at the same time can
## legitimately mean something different afterwards.
static func clear_memo() -> void:
	_memo_first = null
	_memo_time = NAN
	_memo_position = 0.0

static func get_graphic_position_at_millisecond(velocities : Array[RubiChartScrollVelocity], millisecond_time : float) -> float:
	if millisecond_time == _memo_time and _memo_first != null and not velocities.is_empty() \
			and is_same(_memo_first.get_ref(), velocities[0]):
		return _memo_position

	var vel_index: int = velocities.size() - 1
	for i in velocities.size():
		if velocities[i].millisecond_time > millisecond_time:
			vel_index = i - 1
			break

	var velocity: RubiChartScrollVelocity = velocities[vel_index]
	var position_here: float = velocity.position + ((millisecond_time - velocity.millisecond_time) * velocity.multiplier)

	_memo_first = weakref(velocities[0]) if not velocities.is_empty() else null
	_memo_time = millisecond_time
	_memo_position = position_here
	return position_here
