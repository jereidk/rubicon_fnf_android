@tool
extends Label


@export var divisor: String = "/"
@export var note_controller: RubiconLevelNoteController

var _last_score: int = -1
var _last_accuracy: float = -1.0
var _last_misses: int = -1


## Reassigning Label.text triggers a re-layout/redraw even when the
## string content ends up identical, so skip the format+assign entirely
## on frames where score/accuracy/misses haven't actually changed -
## which is most frames, since these only update on note hits/misses,
## not every frame.
func _process(_delta: float) -> void :
	if not note_controller:
		return

	var score: int = note_controller.performance_score_value
	var accuracy: float = note_controller.performance_accuracy_percent
	var misses: int = note_controller.performance_hits_miss

	if score == _last_score and accuracy == _last_accuracy and misses == _last_misses:
		return

	_last_score = score
	_last_accuracy = accuracy
	_last_misses = misses

	text = "Score: %d %s Accuracy: %.2f%% %s Misses: %d" % [
		score,
		divisor,
		accuracy,
		divisor,
		misses,
	]
