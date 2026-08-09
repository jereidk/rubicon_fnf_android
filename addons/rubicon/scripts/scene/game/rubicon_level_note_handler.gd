@tool
@abstract class_name RubiconLevelNoteHandler extends Control

@export var settings : RubiconLevelNoteSettings

@export_group("Spawning", "spawning_")
@export var spawning_bound_maximum : float = 2000.0
@export var spawning_bound_minimum : float = -1000.0

var data : Array[RubiChartNote]
var graphics : Array[RubiconLevelNote]
var results : Array[RubiconLevelNoteHitResult]

## Data indexes whose combo was broken by something other than the note's
## own judgment - today only a misplay (a press with no note in range while
## allow_misplays is off). update_performance() zeroes the running combo
## when it walks over one of these.
var break_combo_indexes : Array[int] = []

var note_spawn_start : int = 0
var note_spawn_end : int = 0
var note_hit_index : int = 0
var last_hit_note_index : int = 0

var pressed: bool = false

var _controller : RubiconLevelNoteController
var _note_pool : Dictionary[StringName, Array]

## Notes that have been used and are waiting to be used again, still children
## of this handler.
##
## Taking a note out of the tree and putting it back is the expensive half of
## spawning one. The funkin mania note is 21 nodes carrying 5 AnimationPlayers
## and 3 AnimationTrees, and every one of those mixers marks its track cache
## dirty on NOTIFICATION_ENTER_TREE and rebuilds it - resolving a NodePath per
## track - the next time it processes. Doing that for a stream of notes is
## what the diagnostics log sees as node counts swinging 1088 <-> 1928 within
## a second while orphan counts move the other way, and it is why the frame
## spikes get blamed on whichever lane animation happened to start on the same
## frame: the animation is not the cost, it is only what the blame heuristic
## can see.
##
## A parked note skips all of it - it never leaves the tree, so no mixer is
## ever invalidated. Hiding it and disabling its process_mode is what stops it
## costing anything while it waits.
var _parked_notes : Dictionary[StringName, Array]

## Accounting for what note churn actually costs, read and cleared by the
## diagnostics log.
##
## The log can already see that it is happening - node counts swing by
## hundreds within a second while orphan counts move the other way, which is
## notes entering and leaving the tree in bulk - but not how much of the
## frame it is. proc= cannot answer that either: it is the whole engine
## process step, and Godot reports it as a per-second maximum rather than
## per frame, so a 73ms proc says only that one frame in that second was bad.
##
## Static because every handler in a level contributes to the same frame, and
## because this addon must not know that the mod's logger exists. Nothing
## here allocates and nothing here runs on a frame with no churn.
static var churn_spawned : int = 0
static var churn_despawned : int = 0
## Of those spawns, how many reused a note that had stayed in the tree. Once
## the parked set has filled this should equal spawn, and every tree
## operation the handler used to do has gone.
static var churn_unparked : int = 0
## Spawns that missed the pool and had to instantiate mid-song. Should be
## zero after prewarm_pool(); anything else means the prewarm undercounted.
static var churn_instantiated : int = 0
## Total time in the spawn/despawn block since the last read.
static var churn_usec : int = 0
## Worst single frame since the last read, summed across every handler that
## churned on that frame - which is the figure that matches what the player
## felt, rather than the worst one lane happened to do on its own.
static var churn_peak_usec : int = 0

## Total time inside the _process of every note and every lane, since the
## last read - the whole call, not just the churn block inside it.
##
## churn_usec already answers "what does spawning and despawning cost": it is
## 0.28ms/frame, which is how that got ruled out. This answers the larger
## question churn_usec cannot, which is how much of the frame's script time
## these objects account for at all.
##
## It exists because guessing failed twice. The note and lane state machines
## were measured at 15.5us per note per frame and cut by 77% in a bench, and
## on the device the change moved nothing - because the bench timed notes at
## rest, which is not a state a song is ever in. Rather than guess a third
## time at what the remaining 8ms is, this measures the part that can be
## measured, so the next log either indicts the notes and lanes or clears
## them.
static var note_process_usec : int = 0

static var _churn_frame : int = -1
static var _churn_frame_usec : int = 0

## Reads the counters and clears them, so each caller sees the interval since
## the previous call rather than a total since boot. Returns usec; the caller
## decides how to present them.
static func take_churn_stats() -> Dictionary:
	var stats := {
		&"spawned": churn_spawned,
		&"despawned": churn_despawned,
		&"unparked": churn_unparked,
		&"instantiated": churn_instantiated,
		&"usec": churn_usec,
		&"peak_usec": churn_peak_usec,
		&"note_usec": note_process_usec,
	}
	churn_spawned = 0
	churn_despawned = 0
	churn_unparked = 0
	churn_instantiated = 0
	churn_usec = 0
	churn_peak_usec = 0
	note_process_usec = 0
	return stats

static func _record_churn(begin_usec : int) -> void:
	var spent : int = Time.get_ticks_usec() - begin_usec
	churn_usec += spent

	var frame : int = Engine.get_process_frames()
	if frame != _churn_frame:
		_churn_frame = frame
		_churn_frame_usec = 0
	_churn_frame_usec += spent
	churn_peak_usec = maxi(churn_peak_usec, _churn_frame_usec)

func get_controller() -> RubiconLevelNoteController:
	return _controller

@abstract func get_mode_id() -> StringName
@abstract func get_unique_id() -> StringName

@abstract func sort_graphic(data_index : int) -> void

@abstract func _press(event : InputEvent) -> void
@abstract func _release(event : InputEvent) -> void
@abstract func _autoplay_process(millisecond_position : float) -> void

signal just_pressed
signal just_released

func update_notes() -> void:
	if _controller == null:
		return

	if _controller.chart == null:
		return

	note_spawn_start = 0
	note_spawn_end = 0
	note_hit_index = 0
	last_hit_note_index = 0

	for i in data.size():
		if graphics[i] == null:
			continue

		despawn_note(i)

	data = get_controller().chart.get_notes_of_id(get_unique_id())

	graphics.clear()
	graphics.resize(data.size())

	results.clear()
	results.resize(data.size())

	prewarm_pool()

## Fills the note pool before the song starts.
##
## spawn_note() takes a note out of _note_pool and, when the pool is empty,
## instantiates one instead - on the main thread, mid-song. The pool starts
## empty, so every note type pays that cost the first time it appears, and a
## dense section pays it for a whole batch at once.
##
## That is what Chimera's stutters are. The diagnostics log shows frames of
## 140ms whose script time is only 35ms: instantiate() is engine-side work
## and does not appear in TIME_PROCESS at all. It also shows orphan nodes
## climbing to 589 and then flat - this pool filling to its working size -
## while node counts jump by tens (+72 TextureRect, +45 AnimationPlayer) on
## exactly the frames that spike.
##
## Instantiating them up front moves that cost into the load. This is
## deliberately NOT the same kind of change as revealing hidden nodes: a
## prewarmed note is never added to the tree, never made visible and never
## initialised - it sits in the same array despawn_note() would have put it
## in, so spawn_note() cannot tell it apart from one that has already been
## used and freed once.
func prewarm_pool() -> void:
	if Engine.is_editor_hint() or _controller == null:
		return

	# How many of each type can be on screen at once is what the pool has to
	# cover; anything beyond that is memory spent for nothing. Counting the
	# chart's own notes per type gives an upper bound for free, capped so a
	# pathological chart cannot allocate thousands.
	var wanted: Dictionary = {}
	for note in data:
		var note_type: StringName = note.type
		var define_key: StringName = "%s_%s" % [note_type, get_mode_id()] if not note_type.is_empty() else get_mode_id()
		wanted[define_key] = mini(wanted.get(define_key, 0) + 1, POOL_PREWARM_MAX)

	var database: Dictionary = get_controller().get_note_database()
	for define_key in wanted:
		if not database.has(define_key):
			continue

		var skin: RubiconLevelNoteMetadata = database[define_key]
		if skin == null or skin.scene == null:
			continue

		if not _note_pool.has(define_key):
			_note_pool[define_key] = Array()

		var pool: Array = _note_pool[define_key]
		while pool.size() < wanted[define_key]:
			pool.append(skin.scene.instantiate())

## Cap per note type. Well above what any Lullaby chart keeps on screen at
## once, and low enough that a broken chart cannot allocate its way out of
## memory.
const POOL_PREWARM_MAX := 48

## How many notes of each type a handler keeps parked in its own tree.
##
## The diagnostics log peaks at 22 notes alive across every lane at once, so
## per lane this is several times the working set and the handler stops
## touching the tree entirely after the first bars. The cap exists only so a
## pathological chart cannot grow the scene tree without bound; past it,
## despawning falls back to taking the note out of the tree as before.
const PARK_MAX := 24

func spawn_note(index : int) -> void:
	var note_type : StringName = data[index].type
	var define_key : StringName = "%s_%s" % [note_type, get_mode_id()] if not note_type.is_empty() else get_mode_id()
	if not _note_pool.has(define_key):
		_note_pool[define_key] = Array()

	churn_spawned += 1

	# Preferred over the pool because it costs no tree operation at all: the
	# note is already a child, and the mixers inside it were never
	# invalidated.
	var graphic : RubiconLevelNote = _take_parked_note(define_key)
	var was_parked : bool = graphic != null

	if graphic == null:
		graphic = _note_pool[define_key].pop_back()
	if graphic == null:
		var skin : RubiconLevelNoteMetadata = get_controller().get_note_database()[define_key]
		var packed : PackedScene = skin.scene

		graphic = packed.instantiate()
		churn_instantiated += 1

	graphic.initialize(self, index)

	# Parked notes keep the name of whatever they were last used for, so a
	# live note can occasionally find its own name taken by a parked sibling
	# and get a suffix from Godot. Nothing reads these names - sorting is by
	# child index and lookups go through graphics[] - so this is only ever a
	# cosmetic wrinkle in the remote scene tree, and it costs the same sibling
	# name scan add_child() was already doing.
	graphic.name = "Note %s" % index
	graphics[index] = graphic

	if not was_parked:
		add_child(graphic)

	## Temporary removal of seeing notes in editor scene tree
	#if Engine.is_editor_hint():
	#	graphic.owner = owner

	sort_graphic(index)

func despawn_note(index : int) -> void:
	var note_type : StringName = data[index].type
	var graphic : RubiconLevelNote = graphics[index]

	churn_despawned += 1

	var define_key : StringName = "%s_%s" % [note_type, get_mode_id()] if not note_type.is_empty() else get_mode_id()
	if not _park_note(define_key, graphic):
		remove_child(graphic)
		_note_pool[define_key].append(graphic)

	## Temporary removal of seeing notes in editor scene tree
	# graphics[index].owner = null
	graphics[index] = null

## Hides a finished note and stops it processing, leaving it in the tree.
## Returns false when it should be taken out of the tree the old way instead
## - the parked set is full, or this is the editor, whose behaviour is left
## exactly as it was.
func _park_note(define_key : StringName, graphic : RubiconLevelNote) -> bool:
	if Engine.is_editor_hint() or graphic == null:
		return false

	if not _parked_notes.has(define_key):
		_parked_notes[define_key] = Array()

	var parked : Array = _parked_notes[define_key]
	if parked.size() >= PARK_MAX:
		return false

	graphic.visible = false
	# Inherited by the whole subtree, which is what stops the note's five
	# AnimationPlayers and three AnimationTrees while it waits. Hiding alone
	# would leave every one of them ticking.
	graphic.process_mode = Node.PROCESS_MODE_DISABLED
	# RubiconLevelNote._exit_tree() is what used to clear this, and a parked
	# note never leaves the tree.
	graphic.missed = false

	parked.append(graphic)
	return true

func _take_parked_note(define_key : StringName) -> RubiconLevelNote:
	if not _parked_notes.has(define_key):
		return null

	var parked : Array = _parked_notes[define_key]
	if parked.is_empty():
		return null

	var graphic : RubiconLevelNote = parked.pop_back()
	graphic.process_mode = Node.PROCESS_MODE_INHERIT
	graphic.visible = true
	churn_unparked += 1
	return graphic

func hit_note(index : int, time_when_hit : float, hit_type : RubiconLevelNoteHitResult.Hit) -> void:
	var result : RubiconLevelNoteHitResult
	if results[index] != null:
		result = results[index]
	else:
		result = RubiconLevelNoteHitResult.new(self)

	result.data_index = index
	result.scoring_hit = hit_type
	result.time_when_hit = time_when_hit

	var is_start : bool = (hit_type == RubiconLevelNoteHitResult.Hit.HIT_COMPLETE and data[index].ending_row == null) or (hit_type == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE and data[index].ending_row != null)
	var millisecond_position : float = data[index].get_millisecond_start_position() if is_start else data[index].get_millisecond_end_position()
	result.time_distance = time_when_hit - millisecond_position

	var ratings : Array[RubiconLevelNoteHitResult.Judgment]
	var hit_windows : Array[float]
	if settings.judgment_enabled & RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT == RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT:
		ratings.append(RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT)
		hit_windows.append(settings.judgment_window_perfect * settings.leniency_multiplier)
	if settings.judgment_enabled & RubiconLevelNoteHitResult.Judgment.JUDGMENT_GREAT == RubiconLevelNoteHitResult.Judgment.JUDGMENT_GREAT:
		ratings.append(RubiconLevelNoteHitResult.Judgment.JUDGMENT_GREAT)
		hit_windows.append(settings.judgment_window_great * settings.leniency_multiplier)
	if settings.judgment_enabled & RubiconLevelNoteHitResult.Judgment.JUDGMENT_GOOD == RubiconLevelNoteHitResult.Judgment.JUDGMENT_GOOD:
		ratings.append(RubiconLevelNoteHitResult.Judgment.JUDGMENT_GOOD)
		hit_windows.append(settings.judgment_window_good * settings.leniency_multiplier)
	if settings.judgment_enabled & RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY == RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY:
		ratings.append(RubiconLevelNoteHitResult.Judgment.JUDGMENT_OKAY)
		hit_windows.append(settings.judgment_window_okay * settings.leniency_multiplier)
	if settings.judgment_enabled & RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD == RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD:
		ratings.append(RubiconLevelNoteHitResult.Judgment.JUDGMENT_BAD)
		hit_windows.append(settings.judgment_window_bad * settings.leniency_multiplier)

	var rating : RubiconLevelNoteHitResult.Judgment = RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS
	for i in hit_windows.size():
		if absf(result.time_distance) <= hit_windows[i]:
			rating = ratings[i]
			break

	result.scoring_rating = rating

	var controller: RubiconLevelNoteController = get_controller()
	var has_ending_row:bool = data[index].ending_row != null

	last_hit_note_index = index
	results[index] = result

	var note_type : StringName = data[index].type
	var define_key : StringName = "%s_%s" % [note_type, get_mode_id()] if not note_type.is_empty() else get_mode_id()
	controller.get_note_database()[define_key].note_hit(result)

	if controller.should_autoplay():
		pressed = is_start
		if pressed:
			just_pressed.emit()
			get_controller().handler_just_pressed.emit(get_unique_id())
		else:
			just_released.emit()
			get_controller().handler_just_released.emit(get_unique_id())

	controller.note_changed.emit(result, has_ending_row)

## Frees the notes the pool is holding, which are orphans and so would leak
## otherwise. Parked notes are not touched here: they are children, and the
## engine frees them with the handler.
##
## Cleared afterwards because leaving the freed instances in the dictionary
## makes every entry a dangling reference, and a handler that leaves the tree
## and comes back - which NOTIFICATION_PARENTED does allow - would then pop
## one of them out of the pool and spawn it.
func _exit_tree() -> void:
	for pool: Array in _note_pool.values():
		for value: Variant in pool:
			if value is Node:
				value.free()

	_note_pool.clear()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			if _controller != null:
				_controller.note_handlers.erase(get_unique_id())

			_controller = null

			var parent : Node = get_parent()
			if parent is RubiconLevelNoteController:
				_controller = parent
				_controller.note_handlers[get_unique_id()] = self
				update_notes()

		NOTIFICATION_EDITOR_PRE_SAVE:
			if not Engine.is_editor_hint():
				return

			## Temporary removal of seeing notes in editor scene tree
			#for i in range(note_spawn_start, note_spawn_end):
			#	graphics[i].owner = null
		NOTIFICATION_EDITOR_POST_SAVE:
			if not Engine.is_editor_hint():
				return

			## Temporary removal of seeing notes in editor scene tree
			#for i in range(note_spawn_start, note_spawn_end):
			#	graphics[i].owner = owner

func _should_process() -> bool:
	return not data.is_empty() and settings != null and _controller != null and _controller.get_level_clock() != null

func _process(delta: float) -> void:
	if not _should_process():
		return

	var millisecond_position : float = get_controller().get_level_clock().time_milliseconds

	# Handle going forward
	while note_spawn_start < data.size() and data[note_spawn_start].get_millisecond_end_position() - millisecond_position < spawning_bound_minimum:
		note_spawn_start += 1

	while note_spawn_end < data.size() and data[note_spawn_end].get_millisecond_start_position() - millisecond_position <= spawning_bound_maximum:
		note_spawn_end += 1

	# Handle rewinding
	var autoplay:bool = get_controller().should_autoplay() and not get_controller().disable_inputs
	if autoplay:
		while _has_passed_last_note(millisecond_position):
			_roll_hit_back()

		if note_hit_index < data.size():
			if _has_passed_current_long_note(millisecond_position) and results[note_hit_index] != null:
				results[note_hit_index].reset(RubiconLevelNoteHitResult.Hit.HIT_NONE)
			elif _is_inside_of_incomplete_note(millisecond_position):
				_reset_to_incomplete_note()

	while note_spawn_start > 0 and data[note_spawn_start - 1].get_millisecond_end_position() - millisecond_position > spawning_bound_minimum:
		note_spawn_start -= 1

	while note_spawn_end - 1 > 0 and data[note_spawn_end - 1].get_millisecond_start_position() - millisecond_position > spawning_bound_maximum:
		note_spawn_end -= 1

	# Timed as one block rather than per note: what is being asked is "how
	# much of this frame went to note churn", and the answer has to include
	# the loops themselves, which walk the whole chart on either side of the
	# spawn window every frame. Two clock reads on a frame that churns
	# nothing is not worth guarding against.
	var churn_begin : int = Time.get_ticks_usec()

	for i in range(0, note_spawn_start):
		if graphics[i] != null:
			despawn_note(i)

	for i in range(note_spawn_end, data.size()):
		if graphics[i] != null:
			despawn_note(i)

	for i in range(note_spawn_start, note_spawn_end):
		if graphics[i] == null:
			spawn_note(i)

	_record_churn(churn_begin)

	if note_hit_index >= data.size():
		return

	if autoplay:
		_autoplay_process(millisecond_position)

	var should_complete : bool = note_hit_index < data.size() and results[note_hit_index] != null and results[note_hit_index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE and data[note_hit_index].get_millisecond_end_position() - millisecond_position <= 0.0
	if should_complete:
		hit_note(note_hit_index, data[note_hit_index].get_millisecond_end_position(), RubiconLevelNoteHitResult.Hit.HIT_COMPLETE)
		note_hit_index += 1

		get_controller().update_performance()

	while not autoplay and note_hit_index < data.size() and data[note_hit_index].get_millisecond_start_position() - millisecond_position < -(settings.judgment_window_bad * settings.leniency_multiplier) and (results[note_hit_index] == null or results[note_hit_index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_NONE):
		# TODO: LESS BANDAID FIX THEN + 1000 RATING TIME OFFSET
		hit_note(note_hit_index, data[note_hit_index].get_millisecond_start_position() + (settings.judgment_window_bad * settings.leniency_multiplier) + 1000, RubiconLevelNoteHitResult.Hit.HIT_COMPLETE) # TODO: Add more forgiving hold notes
		note_hit_index += 1

		get_controller().update_performance()

func _has_passed_last_note(millisecond_position : float) -> bool:
	var has_last_note : bool = note_hit_index > 0
	if not has_last_note:
		return false

	var passed_end_of_last_single_note : bool = data[note_hit_index - 1].ending_row == null and data[note_hit_index - 1].get_millisecond_end_position() - millisecond_position >= settings.judgment_window_bad * settings.leniency_multiplier
	var passed_end_of_last_long_note : bool = data[note_hit_index - 1].ending_row != null and data[note_hit_index - 1].get_millisecond_end_position() - millisecond_position >= 0.0
	return passed_end_of_last_single_note or passed_end_of_last_long_note

func _has_passed_current_long_note(millisecond_position : float) -> bool:
	var passed_start_of_current_long_note : bool = data[note_hit_index].ending_row != null and data[note_hit_index].get_millisecond_start_position() - millisecond_position >= settings.judgment_window_bad * settings.leniency_multiplier
	return passed_start_of_current_long_note

func _is_inside_of_incomplete_note(millisecond_position : float) -> bool:
	var passed_start_of_current_long_note : bool = data[note_hit_index].ending_row != null and data[note_hit_index].get_millisecond_start_position() - millisecond_position >= settings.judgment_window_bad * settings.leniency_multiplier
	return results[note_hit_index] != null and results[note_hit_index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE

func _roll_hit_back() -> void:
	note_hit_index -= 1
	last_hit_note_index -= 1

	break_combo_indexes.erase(note_hit_index)

	var controller: RubiconLevelNoteController = get_controller()
	results[note_hit_index].reset(RubiconLevelNoteHitResult.Hit.HIT_NONE)

	controller.update_performance()
	controller.note_changed.emit(results[note_hit_index], data[note_hit_index].ending_row != null)

func _reset_to_incomplete_note() -> void:
	if results[note_hit_index] == null or results[note_hit_index].scoring_hit != RubiconLevelNoteHitResult.Hit.HIT_COMPLETE:
		return

	results[note_hit_index].reset(RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE)

func _property_can_revert(property: StringName) -> bool:
	if property == "settings":
		return true

	return false

func _property_get_revert(property : StringName) -> Variant:
	if property == "settings":
		return RubiconLevelNoteSettings.new()

	return
