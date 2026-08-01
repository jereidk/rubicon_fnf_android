class_name LullabyShowcaseNoteSync extends Node

## While Settings.lullaby_showcase_mode is on, mirrors the Player's
## autoplay note hits onto RubiconMobileControls' visual lane hitboxes
## (_press_lane/_release_lane, underscored but plain public methods -
## Godot doesn't enforce GDScript privacy) so the on-screen touch zones
## flash in sync even though nothing is actually touching the screen. The
## actual note timing/scoring is untouched - this only drives the touch
## hitbox's own press/release bookkeeping and redraw, exactly like a real
## tap would.
##
## note_controller.handler_just_pressed/released only fire while
## should_autoplay() is true (see RubiconLevelNoteHandler.hit_note()), so
## this is inert during normal keyboard/touch play - it just happens to
## also fire for showcase mode's forced autoplay, which is the whole
## point. Hold notes get a real press/release pair; plain taps only ever
## emit a press (see hit_note()'s is_start logic), so those get a short
## timed flash instead of hanging pressed forever.

const TAP_FLASH_SECONDS: float = 0.08

@export var note_controller: RubiconLevelNoteController
@export var mobile_controls: RubiconMobileControls

func _ready() -> void:
	if not note_controller or not mobile_controls:
		return
	note_controller.handler_just_pressed.connect(_on_handler_pressed)
	note_controller.handler_just_released.connect(_on_handler_released)

func _on_handler_pressed(handler_name: StringName) -> void:
	if not Settings.lullaby_showcase_mode:
		return

	var lane: int = _lane_for(handler_name)
	if lane < 0:
		return

	mobile_controls._press_lane(lane)
	if _is_tap(handler_name):
		var timer: SceneTreeTimer = get_tree().create_timer(TAP_FLASH_SECONDS)
		timer.timeout.connect(mobile_controls._release_lane.bind(lane))

func _on_handler_released(handler_name: StringName) -> void:
	if not Settings.lullaby_showcase_mode:
		return

	var lane: int = _lane_for(handler_name)
	if lane < 0:
		return

	mobile_controls._release_lane(lane)

func _lane_for(handler_name: StringName) -> int:
	var name_string: String = String(handler_name)
	if not name_string.begins_with("mania_lane"):
		return -1
	return name_string.trim_prefix("mania_lane").to_int()

## Whether the note that just triggered handler_name is a plain tap (no
## ending_row) rather than a hold - hold notes get a real release later
## from handler_just_released, so only taps need the timed flash above.
func _is_tap(handler_name: StringName) -> bool:
	var handler: RubiconLevelNoteHandler = note_controller.note_handlers.get(String(handler_name))
	if handler == null or handler.data.is_empty():
		return true

	var index: int = clampi(handler.last_hit_note_index, 0, handler.data.size() - 1)
	return handler.data[index].ending_row == null
