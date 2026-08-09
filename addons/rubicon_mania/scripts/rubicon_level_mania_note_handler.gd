@tool
class_name RubiconLevelManiaNoteHandler extends RubiconLevelNoteHandler

enum LaneState {
	LANE_STATE_NEUTRAL = 0,
	LANE_STATE_PUSH = 1,
	LANE_STATE_HIT = 2
}

@export var global_direction : float = -1.571

## When false, pressing a lane with no note in range breaks the combo and
## emits [signal misplayed] - the "ghost tapping off" behaviour. Restored
## from the mod's own Rubicon, where the console's Ghost Tapping row drives
## it through lullaby_song_settings.gd.
@export var allow_misplays : bool = true

@export_group("Lane", "lane_")
@export var lane_id : int = 0

## The lane's AnimationTree is twenty-four advance_expressions reading this
## and lane_id, evaluated every frame for as long as the lane exists. Since
## nothing else can move that state machine, the tree is only advanced from
## here - see RubiconMixerPump, and _pump below.
##
## Guarded so that assigning the value it already holds does not count as a
## change: _process reassigns NEUTRAL on autoplayed lanes, and _press
## reassigns PUSH on every press that hits nothing.
@export var lane_state : LaneState:
	set(value):
		if lane_state == value:
			return

		lane_state = value
		if _pump != null:
			_pump.wake()

## Whether an autoplayed hit keeps the lane lit long enough to be seen.
##
## hit_note() sets lane_state to HIT, and the autoplay branch of _process
## clears it again - both inside the same _process call, because that branch
## runs immediately after the super() that hit the note. The lane's
## AnimationTree is a child and so processes after its handler, which means
## it only ever observes NEUTRAL: the "neutral -> hit_init" transition that
## draws the receptor's confirm never fires, and an autoplayed lane does not
## light up at all.
##
## That is upstream behaviour, read out of the PC pck rather than assumed,
## and it is invisible in a normal run - the only autoplayed strumline is the
## opponent's, and all three songs hide it. It stops being invisible the
## moment something deliberately puts an autoplayed strumline on screen,
## which is exactly what Lullaby's Showcase Mode does.
##
## One frame is the whole fix: the tree needs a single evaluation to reach
## hit_init, and "hit -> neutral" is an at-end transition, so the confirm
## plays out on its own once the state clears afterwards. Off by default, so
## nothing that has not asked for it changes.
@export var lane_autoplay_hit_lingers : bool = false

## Process frame on which lane_state last became HIT, so the clear can tell
## "the hit was this frame" from "the hit was an earlier one".
var _lane_hit_frame : int = -1

## The lane's own AnimationTree. Direct children only - the notes are
## children too, and each one pumps the three trees it carries itself.
var _pump : RubiconMixerPump = RubiconMixerPump.new()

## Emitted on a press that hit nothing while misplays are disallowed.
## RubiconCharacterManiaMisplay plays the miss animation off it,
## RubiconHealthModuleManiaMisplay docks health, and LullabyVocalMuter
## mutes the vocal track.
signal misplayed(lane_id: int)

func _init() -> void:
	settings = load("res://addons/rubicon_mania/resources/default_settings.tres")

func hit_note(index : int, time_when_hit : float, hit_type : RubiconLevelNoteHitResult.Hit) -> void:
	super(index, time_when_hit, hit_type)

	if results[index].scoring_rating < RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS and results[index].scoring_rating != RubiconLevelNoteHitResult.Judgment.JUDGMENT_NONE:
		lane_state = LaneState.LANE_STATE_HIT
		_lane_hit_frame = Engine.get_process_frames()

	if hit_type == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE:
		results[index].scoring_value = 0.25
		return
	
	match results[index].scoring_rating:
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT:
			results[index].scoring_value = 1.0
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_GREAT:
			results[index].scoring_value = 0.9375
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_GOOD:
			results[index].scoring_value = 0.625
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY:
			results[index].scoring_value = 0.3125
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD:
			results[index].scoring_value = 0.9375
		RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS:
			results[index].scoring_value = 0.15625

func sort_graphic(data_index : int) -> void:
	var graphic : RubiconLevelNote = graphics[data_index]
	
	# Easy sorting
	if data_index > 0 and data_index < data.size() and graphics[data_index - 1] != null: # Get the note behind
		move_child(graphic, graphics[data_index - 1].get_index() + 1)
		return
	
	if data_index + 1 < data.size() and graphics[data_index + 1] != null: # Get the note in front
		move_child(graphic, graphics[data_index + 1].get_index())
		return
	
	var target_index : int = -1
	for i in graphics.size():
		var current : RubiconLevelNote = graphics[i]
		if current != null:
			if i < data_index:
				target_index = current.get_index() + 1
			else:
				target_index = current.get_index()
			
			break
	
	move_child(graphic, target_index)

func get_mode_id() -> StringName:
	return "mania"

func get_unique_id() -> StringName:
	return "mania_lane%s" % lane_id 

func _ready() -> void:
	# The editor keeps the stock behaviour, so the scene previews the way it
	# always has.
	if Engine.is_editor_hint():
		return

	_pump.adopt_children_of(self)

## Split from the body so the whole call - including the base handler's
## spawn/despawn walk - can be timed past its early returns. See
## RubiconLevelNoteHandler.note_process_usec.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_process_lane(delta)
		return

	var began : int = Time.get_ticks_usec()
	_process_lane(delta)
	note_process_usec += Time.get_ticks_usec() - began

func _process_lane(delta: float) -> void:
	super._process(delta)

	if not Engine.is_editor_hint():
		_pump.pump(delta)

	if not _should_process():
		return

	if get_controller().should_autoplay() and note_hit_index > 0 and lane_state == LaneState.LANE_STATE_HIT and (results[note_hit_index - 1] == null or results[note_hit_index - 1].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_COMPLETE):
		# See lane_autoplay_hit_lingers: clearing this on the frame it was set
		# is what stops an autoplayed lane ever lighting up.
		var lit_this_frame : bool = lane_autoplay_hit_lingers and _lane_hit_frame == Engine.get_process_frames()
		if not lit_this_frame:
			lane_state = LaneState.LANE_STATE_NEUTRAL

func _press(event : InputEvent) -> void:
	var controller: RubiconLevelNoteController = get_controller()
	if note_hit_index >= data.size():
		lane_state = LaneState.LANE_STATE_PUSH

		just_pressed.emit()
		controller.handler_just_pressed.emit(get_unique_id())
		return
	
	var precise_time : float = controller.get_level_clock().get_time_precise() + controller.offset_input
	var bad_window : float = settings.judgment_window_bad * settings.leniency_multiplier
	var hit_time : float = data[note_hit_index].get_millisecond_start_position() - precise_time
	while data[note_hit_index].get_millisecond_start_position() <= -bad_window:
		hit_note(note_hit_index, precise_time, RubiconLevelNoteHitResult.Hit.HIT_COMPLETE)
		note_hit_index += 1
		controller.update_performance()

		hit_time = data[note_hit_index].get_millisecond_start_position() - precise_time

	if absf(hit_time) <= bad_window:
		if data[note_hit_index].ending_row != null:
			hit_note(note_hit_index, precise_time, RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE)
			controller.update_performance()
		else:
			hit_note(note_hit_index, precise_time, RubiconLevelNoteHitResult.Hit.HIT_COMPLETE)
			note_hit_index += 1
			controller.update_performance()
		
	else:
		lane_state = LaneState.LANE_STATE_PUSH

		if not allow_misplays:
			if not break_combo_indexes.has(note_hit_index - 1):
				break_combo_indexes.append(note_hit_index - 1)

			misplayed.emit(lane_id)

	just_pressed.emit()
	controller.handler_just_pressed.emit(get_unique_id())

func _release(event : InputEvent) -> void:
	var controller: RubiconLevelNoteController = get_controller()
	if note_hit_index < data.size() and results[note_hit_index] != null and results[note_hit_index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE:
		hit_note(note_hit_index, controller.get_level_clock().get_time_precise() + controller.offset_input, RubiconLevelNoteHitResult.Hit.HIT_COMPLETE)
		note_hit_index += 1
		controller.update_performance()

	if lane_state != LaneState.LANE_STATE_NEUTRAL:
		lane_state = LaneState.LANE_STATE_NEUTRAL
	
	just_pressed.emit()
	controller.handler_just_released.emit(get_unique_id())

func _autoplay_process(millisecond_position : float) -> void:
	while note_hit_index < data.size() and data[note_hit_index].get_millisecond_start_position() - millisecond_position <= 0:
		# Hold note logic
		if data[note_hit_index].ending_row != null:
			if results[note_hit_index] == null or results[note_hit_index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_NONE:
				hit_note(note_hit_index, data[note_hit_index].get_millisecond_start_position(), RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE)
				get_controller().update_performance()
			
			break

		hit_note(note_hit_index,data[note_hit_index].get_millisecond_end_position(), RubiconLevelNoteHitResult.Hit.HIT_COMPLETE)
		note_hit_index += 1
		
		get_controller().update_performance()

func _property_get_revert(property : StringName) -> Variant:
	if property == "settings" and ResourceLoader.exists("res://addons/rubicon_mania/resources/default_settings.tres"):
		return load("res://addons/rubicon_mania/resources/default_settings.tres")
	
	return super(property)
