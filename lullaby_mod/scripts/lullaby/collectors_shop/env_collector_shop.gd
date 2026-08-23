class_name CollectorShop
extends Node3D

enum ShopStates{
	BUSY = 0, 
	FREE_LOOK = 1, 
	FOCUSED = 2, 
}

static var previous_state: String = ""



static var last_trigger: TriggerArea3D
static var current_area: FocusArea3D:
	set(new_focus):
		if new_focus == current_area:
			return

		if current_area != null:
			current_area.is_focused = false
		if new_focus != null:
			new_focus.is_focused = true

		current_area = new_focus

@export var state: ShopStates = ShopStates.BUSY:
	set(value):
		state = value

		if mouse_controller != null:
			mouse_controller.should_cast_ray = value != ShopStates.BUSY

		if value != ShopStates.FREE_LOOK:
			_idle_timer = 0.0

		# Zooming back out means the camera is no longer in any area, and
		# nothing else says so. current_area only ever changed when some other
		# area took focus, so the last one the player entered kept is_focused
		# true for the rest of the visit - "the area the camera is in" quietly
		# meant "the last area the camera was in".
		#
		# Two contextual buttons read that and both were wrong in free look.
		# Power is gated on FocusAreaRight.is_focused, so it hung around while
		# the player walked the room; and clearing this fires
		# FocusArea3D.is_focused's setter, whose _focus_changed(false) is the
		# one thing that drops Console.focused - see focus_console.gd, which
		# already exists for exactly this failure reached from a different
		# direction - so F stayed offering a cartridge switch out in the room.
		#
		# Only FREE_LOOK. BUSY is a menu open inside an area, and the console
		# being open is not the camera having left it.
		if value == ShopStates.FREE_LOOK:
			CollectorShop.current_area = null

		# The touch overlay's OK button is shared across every active
		# state (see RubiconMenuTouchControls' own doc comment - one
		# persistent instance, not swapped per sub-state). MouseController's
		# 3D raycast+"RightClick" confirm (see its own should_cast_ray,
		# gated the same way below) drives BOTH area-select in FREE_LOOK
		# and clicking a sub-item once FOCUSED (e.g. the TV screen itself,
		# to actually open the console) - only once truly BUSY (forwarded
		# into a SubViewport's own 2D GUI, e.g. the console's Home tab) does
		# OK's job switch to a real "ui_accept" menu confirm.
		if touch_confirm_button != null:
			touch_confirm_button.action = &"ui_accept" if value == ShopStates.BUSY else &"RightClick"

@export var touch_confirm_button: RubiconActionButton
@export var mouse_controller: MouseController
@export var console: Console
@export var sequence_controller: ShopSequences
@export var voiceline: AudioStreamPlayer3D
@export var voiceline_group_name: String
@export var voiceline_is_active: bool
@export var voiceline_is_skippable: bool
@export var dialogue: CollectorDialogue
@export var entry_voicelines: EntryVoicelines
@export var camera: RubiconInterpolatedCamera3D
@export var screen_transitions: AnimationPlayer
@export var fake_candle_shadow: Node3D

@export var voiceline_groups: Array[VoicelineGroup] = []

## How far through voiceline_groups the background warm-up has got.
##
## Voicelines are no longer loaded with the room - see VoicelineEntry - which
## takes 109 files off a cold load that is bound by per-file cost. The tradeoff
## is that the first play of a line would otherwise pay for its own load, so
## one line is pulled in per frame from here until they are all resident. At
## 60fps the shop's 109 lines are in memory inside two seconds, long before
## the Collector has anything to say.
var _warm_group: int = 0

## Loads at most one voiceline per frame, in order, and stops once done.
func _warm_one_voiceline() -> void:
	while _warm_group < voiceline_groups.size():
		var group: VoicelineGroup = voiceline_groups[_warm_group]
		if group != null and group.warm_next():
			return
		_warm_group += 1

@export_group("Idle Voicelines")

@export var idle_voiceline_group: String = "idletoolong"
@export var idle_voiceline_time: float = 30.0

@onready var music: AudioStreamPlayer3D = $Audio / Music
@onready var collector: Collector = $Collector

@onready var voiceline_dial_end: Timer = %VoiceEndDialogueTimer
@onready var voiceline_state_end: Timer = %VoiceEndDialogueTimer

@export var skip_time: float = 0.1
@export var skips_needed: int = 3
@export var current_skips: int = 0

var regular_shop_music: AudioStream = preload("res://lullaby_mod/resources/audio/mus/mus_shop.ogg")

var _ending_dialogue: = false
var _current_ending_state: ShopStates = ShopStates.FREE_LOOK
var _group_indexes: Dictionary[String, int] = {}

var _idle_timer: float = 0.0

signal voice_entry_started(entry: VoicelineEntry)
signal voice_entry_finished()
signal voice_group_finished()
signal voice_interrupted()

func _ready() -> void :
	current_area = null
	last_trigger = null

	# Exported NodePaths (touch_confirm_button included) aren't guaranteed
	# resolved yet when state's own setter first ran during scene
	# deserialization - re-run it now that every @export is populated, so
	# touch_confirm_button.action reliably reflects the initial state
	# instead of only updating on the first later change.
	state = state


	LullabyGameoverModule.has_died = false

	get_viewport().warp_mouse(get_viewport().get_visible_rect().size / 2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if fake_candle_shadow != null:
		fake_candle_shadow.visible = false

	if voiceline != null and not voiceline.finished.is_connected(_on_voiceline_finished):
		voiceline.finished.connect(_on_voiceline_finished)

	if voiceline_dial_end:
		voiceline_dial_end.timeout.connect( func():
			if dialogue != null:
				dialogue.play_scale_out()

			if voiceline_state_end:
				voiceline_state_end.start()
		)

	if voiceline_state_end:
		voiceline_state_end.timeout.connect( func():
			if not current_area and _current_ending_state != ShopStates.BUSY:

				if _current_ending_state < ShopStates.FOCUSED:
					state = _current_ending_state
			_ending_dialogue = false
			_idle_timer = 0.0

			voiceline_state_end.stop()
		)

	# The armed one-shot is checked first so it can force the tour on a save
	# that has already seen it, and is spent here - this runs in _ready, so
	# reading the stored preference directly replayed the 152-second tour on
	# every load of the room, including walking back in after a song.
	# intro_seen is still set below either way: the forced path is additive,
	# and turning the preference back off has to leave a normal save behind
	# rather than one that replays the intro once more.
	if Settings.force_shop_intro_pending or not SaveData.get_flag("intro_seen"):
		Settings.force_shop_intro_pending = false
		_add_intro_animation()

		if sequence_controller != null and sequence_controller._animation_player != null:
			sequence_controller._animation_player.play("sequence_intro")

		SaveData.set_flag("intro_seen", true)
		SaveData.save()

	elif SaveData.get_flag(&"credits_scroll_seen") and not SaveData.get_flag("outro_seen"):
		if sequence_controller != null and sequence_controller._animation_player != null:
			sequence_controller._animation_player.play("sequence_outro")

		SaveData.set_flag("outro_seen", true)
		SaveData.save()
	else:
		match previous_state:
			# Coming back from a training drill. Without this you reload into
			# the shop entrance and have to walk to the TV again, which after
			# a thirty-second drill is most of the round trip.
			#
			# FocusConsole.trigger() is the same path the player's own click
			# takes - it plays focus_console, fades the music in, sets
			# console.focused and grabs the Cartridges focus - so this borrows
			# it whole rather than reimplementing four of those five things.
			# Deferred because trigger() reaches into the console living in a
			# SubViewport, which is not built yet this frame; and guarded by
			# its own ShopConsolePower/can_interact checks, so if the TV is off
			# you simply land in the ordinary shop.
			"Console":
				default_shop(false)
				_return_to_console.call_deferred()
			"Kollectadex":
				default_entry()
				music.volume_linear = 0.0

				sequence_controller.animation_player.play(&"focus_left")

				screen_transitions.play(&"out")
				sequence_controller.animation_player.seek(0.0, true)

				camera.global_position = camera.position_interpolate_target + camera.position_interpolate_offset
				camera.global_rotation = camera.rotation_interpolate_target + camera.rotation_interpolate_offset
			_:
				default_shop()

	previous_state = ""

func _process(delta: float) -> void :
	# Before the state gates on purpose: the whole point is to get the audio
	# in memory while the player is doing anything at all, including standing
	# in a menu, so that no line is ever the one that has to wait.
	_warm_one_voiceline()

	if state != ShopStates.FREE_LOOK:
		return

	if _ending_dialogue:
		return

	_idle_timer += delta

	if _idle_timer >= idle_voiceline_time:
		_idle_timer = 0.0

		if idle_voiceline_group != "":
			play_voiceline_group("idletoolong", true)

func _input(event: InputEvent) -> void :
	if event.is_echo() or not event.is_pressed():
		return

	if event.is_action(&"ui_cancel"):
		# Every guard below, on one line, the moment the player presses Back.
		#
		# The board screen was reported as impossible to leave, and reading
		# the scene says it should be leavable: sequence_board sets state to
		# FOCUSED, FocusBoard takes over current_area so no sibling's
		# is_focused-gated handler can swallow the press first, and nothing
		# between here and the root marks the event handled. One of those is
		# false on the device and static reading cannot say which, so it says
		# so itself.
		if DiagnosticsLog != null:
			DiagnosticsLog.mark("ui_cancel state=%s console_focused=%s area=%s handled=%s" % [
				ShopStates.keys()[state] if state < ShopStates.size() else state,
				"?" if console == null else str(console.focused),
				"none" if current_area == null else current_area.name,
				str(get_viewport().is_input_handled()),
			])
			# And again once every other handler has had the press.
			#
			# The line above reads is_input_handled() from inside _input(),
			# which is *before* the console's own handler runs - so it says
			# "handled=false" whether or not anything downstream took it, and
			# the twelve device samples collected so far therefore cannot
			# answer the question this mark exists for.
			#
			# Nine of those twelve are state=BUSY console_focused=true
			# area=FocusConsole - the player at the console, in a menu - and
			# three of them arrive in pairs less than 1.2s apart, which is
			# what "it did not respond" looks like. But the shop's own branch
			# below only fires on FOCUSED, so in BUSY this handler is inert by
			# construction and whether the CONSOLE took the press is exactly
			# what is unknown.
			#
			# Deferred rather than awaited: this runs at the end of the same
			# frame's idle step, after _input propagation is complete. (The
			# call_deferred-after-a-scene-change trap in CLAUDE.md is a
			# different case - nothing here changes scene.)
			_mark_cancel_outcome.call_deferred()

		# While the console is actively grabbing GUI focus for Home-tab/
		# submenu navigation (Console.focused, set by focus_console.gd's
		# trigger() - see FocusConsoleEntry's own doc comment), let
		# Console.back_out() (forwarded via SubmenuArea._input()) handle
		# this press instead: it steps out one level (submenu -> Home tab
		# -> un-focused) at a time. Only once that's unwound all the way
		# does this fire, fully zooming the camera back out - otherwise
		# both handlers would fire on the very same keypress and fight
		# over the same AnimationPlayer.
		# ... and the area the player is actually looking at, because a flag
		# on its own is not enough. Console.focused is what decides whether
		# the console gets this press, and until focus_console.gd's
		# _focus_changed() it had no writer that could ever clear it from
		# outside the console. Requiring the console's area to be the
		# current one as well means a stale flag can only ever cost the
		# console its own Back handling, never the whole shop's.
		var at_console: bool = (console != null and console.focused
				and current_area != null
				and current_area == get_node_or_null(CONSOLE_AREA_PATH))

		if state == ShopStates.FOCUSED and not at_console:
			sequence_controller.animation_player.play(&"focus_center")

## Whether anything at all consumed the Back press, read once the frame's
## input propagation is over. See the mark in _input().
func _mark_cancel_outcome() -> void :
	if DiagnosticsLog == null or not is_inside_tree():
		return
	DiagnosticsLog.mark("ui_cancel despues state=%s console_focused=%s area=%s handled=%s" % [
		ShopStates.keys()[state] if state < ShopStates.size() else state,
		"?" if console == null else str(console.focused),
		"none" if current_area == null else current_area.name,
		str(get_viewport().is_input_handled()),
	])

## Path is fixed rather than exported because this is only ever the one
## area, and an export would be a fifth thing to keep wired for a case that
## already degrades safely when it finds nothing.
const CONSOLE_AREA_PATH := ^"Environment/Areas/FocusConsole"

func _return_to_console() -> void :
	var area: Node = get_node_or_null(CONSOLE_AREA_PATH)
	if area == null or not area.has_method("trigger"):
		return
	area.call("trigger")

func default_shop(play_voicelines: bool = true) -> void :
	default_entry()

	if play_voicelines and entry_voicelines != null:
		entry_voicelines.play_entry_voiceline()

func default_entry() -> void :
	music.stream = regular_shop_music
	music.volume_db = -24.124
	music.play()

	collector_unseen()

func save_collector_memory() -> void :
	SaveData.save()

func collector_unseen() -> void :
	if state != ShopStates.BUSY and state != ShopStates.FOCUSED:
		collector.play_random_idle()

func _check_voiceline_group(group_name):
	var group: = get_voiceline_group(group_name)

	if group == null:
		push_warning("Missing voiceline group: " + group_name)
		return null

	if group.voicelines.is_empty():
		push_warning("Voiceline group is empty: " + group_name)
		return null

	return group


func play_full_voiceline_group(group_name: String, from_start: bool = true) -> void :
	var group: VoicelineGroup = _check_voiceline_group(group_name)

	if group == null:
		return

	voiceline_group_name = group_name
	if from_start:
		_group_indexes.set(group_name, 0)

	_next_line = func _next():
		var index: = _group_indexes.get(group_name, 0) as int

		if index >= group.voicelines.size():
			_group_indexes.set(group_name, 0)

			_next_line = null
			_on_voiceline_finished()

			voiceline_group_name = ""
			voice_group_finished.emit()

			return

		var entry: VoicelineEntry = _get_next_ordered_voiceline(group_name, group, false)
		play_voiceline_entry(entry, true)

	_next_line.call()


func play_voiceline_group(group_name: String, _randomize: bool = true, _wrap_index: bool = true) -> void :
	var group: VoicelineGroup = _check_voiceline_group(group_name)

	if group == null:
		return

	voiceline_group_name = group_name
	var entry: VoicelineEntry

	if _randomize:
		entry = group.voicelines.pick_random()
	else:
		entry = _get_next_ordered_voiceline(group_name, group, _wrap_index)

	play_voiceline_entry(entry, false)

func _get_next_ordered_voiceline(group_name: String, group: VoicelineGroup, wrap_index: bool = true) -> VoicelineEntry:
	var index: = _group_indexes.get(group_name, 0) as int

	if wrap_index:
		index = wrapi(index, 0, group.voicelines.size())
		_group_indexes[group_name] = wrapi(index + 1, 0, group.voicelines.size())
	else:
		index = index
		_group_indexes[group_name] = index + 1

	return group.voicelines[index]

func play_voiceline_entry(entry: VoicelineEntry, skippable: bool = false) -> void :
	if entry == null:
		return

	_idle_timer = 0.0
	_ending_dialogue = false


	if entry.state < ShopStates.FOCUSED:
		state = entry.state as ShopStates
	if entry.ending_state > ShopStates.FOCUSED:
		_current_ending_state = 3

	if dialogue != null:
		dialogue.start_dialogue([entry.dialogue_text])

	if voiceline == null:
		_on_voiceline_finished()
		return

	voiceline.stop()
	# get_stream() rather than .stream: entries hold a path now and resolve on
	# first use, so reading the field directly gets null on every migrated one.
	var stream: AudioStream = entry.get_stream()
	voiceline.stream = stream

	if stream != null:
		voiceline.play()
	else:
		_on_voiceline_finished()

	voiceline_is_skippable = skippable

	voiceline_is_active = true
	voice_entry_started.emit(entry)

	voiceline_dial_end.stop()
	voiceline_state_end.stop()

func stop_voiceline():
	_next_line = null

	_idle_timer = 0.0
	_ending_dialogue = false

	voiceline_is_skippable = false
	voiceline_group_name = ""

	if dialogue != null:
		dialogue.end_dialogue()

	_on_voiceline_finished()
	voiceline.stop()

	voiceline_dial_end.stop()
	voiceline_state_end.stop()

func get_voiceline_group(group_name: String) -> VoicelineGroup:
	for group in voiceline_groups:
		if group != null and group.group_name == group_name:
			return group

	return null

var _next_line = null

func _on_voiceline_finished() -> void :
	voiceline_is_active = false;
	voice_entry_finished.emit()

	if _next_line != null:
		if not voiceline_is_skippable:
			_next_line.call()
		return
	else:
		voiceline_group_name = ""

	if _ending_dialogue:
		return

	_ending_dialogue = true
	voiceline_dial_end.start()

var _skipped_time: float = -1

func skip_voiceline() -> void :
	voiceline.stop()
	_on_voiceline_finished()

	dialogue.finish_line()

	var current_time: float = Time.get_ticks_msec() / 1000.0

	if _skipped_time == -1:
		_skipped_time = current_time;
		return

	var time_diff: float = (current_time - _skipped_time)

	if time_diff < skip_time:
		current_skips += 1
		if current_skips >= skips_needed:
			voice_interrupted.emit()

			current_skips = 0
	else:
		current_skips = 0

	_skipped_time = current_time


func _exit_tree() -> void :
	last_trigger = null
	current_area = null


## Where the Collector's intro animation lives, and which library it belongs to
## once it is loaded.
##
## sequence_intro.tres is 4.17MB - a 152-second baked animation, and thirteen
## times the size of the next biggest in the same library, whose others are all
## under 0.31MB. It used to be an ExtResource in the Collector's
## AnimationLibrary, so it loaded on every visit to the shop.
##
## It plays once in a save's lifetime. The branch above is the only caller and
## it sets intro_seen immediately afterwards, so on every visit after the first
## the file was loaded, parsed and held for an animation that could not run.
const INTRO_ANIMATION_PATH := "res://lullaby_mod/resources/animations/collector/sequence_intro.tres"
const INTRO_ANIMATION_NAME := &"sequence_intro"

## Puts the intro animation into the Collector's library, for the one run that
## needs it.
##
## Called from _ready() rather than at the moment the animation starts, so the
## cost lands inside the load the player is already waiting through instead of
## as a hitch on the first frame of the cutscene. The Sequences animation drives
## the Collector's own player by name, so it has to be in the library before
## anything plays.
## Takes the player rather than only reading it off the Collector, so this can
## be exercised without one. `collector` is typed as Collector, and assigning
## anything else to it is rejected silently - which is what made the first
## version of the test look like a code failure when it was a stand-in that
## never landed.
func _add_intro_animation(player: AnimationPlayer = null) -> void:
	if player == null:
		if collector == null:
			return
		player = collector.animation_player
	if player == null:
		return

	if player.has_animation(INTRO_ANIMATION_NAME):
		return

	var anim: Animation = load(INTRO_ANIMATION_PATH) as Animation
	if anim == null:
		push_warning("shop: no pude cargar la animacion de intro %s" % INTRO_ANIMATION_PATH)
		return

	# The Collector's animations sit in the default (unnamed) library, which is
	# what has_animation() above searches and what play("sequence_intro") will.
	var library: AnimationLibrary = player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		player.add_animation_library(&"", library)

	library.add_animation(INTRO_ANIMATION_NAME, anim)
