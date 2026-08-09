@tool
class_name TypingChallenge extends Node


@export var celebi_start_scale: Vector2 = Vector2(0.7, 0.7)
@export var celebi_end_scale: Vector2 = Vector2(1.2, 1.2)

@export var show_celebi: bool = false:
	get:
		return _show_celebi
	set(val):
		if val != _show_celebi:
			if val:
				$Celebi.scale = celebi_start_scale
				$Celebi.modulate = Color("333333")

				celebi_animator.get_parent().visible = true
				celebi_animator.play(celebi_enter_animation)
				celebi_animator.seek(0.0)

			else:
				celebi_animator.get_parent().visible = false

		_show_celebi = val

@export var active: bool = false:
	get:
		return _active
	set(val):
		if _active != val:
			if val:
				initiate_challenge()
			else:
				end_challenge()

		if Debugger and Debugger.fps_display and "_disable_quick_restart" in Debugger.fps_display:
			Debugger.fps_display._disable_quick_restart = _active

		_active = val

@export var prompt_user: bool = false:
	get:
		return _prompt_user
	set(val):
		if _prompt_user != val:
			if val:
				start_challenge()

		_prompt_user = val

@export var autoplay: bool = false
@export var choose_from_list: bool = true

@export var time_end: float = 4.0:
	get:
		return _time_end
	set(val):
		if _time_end != val:
			passed_challenge = false
			challenge_over = false

		_time_end = val

@export var end_offset: float = 0.0

@export_group("Words", "word_")
@export var current_word: String = ""
@export var custom_word: String = ""
@export var word_list: Array[String] = ["report bug"]:
	set(val):
		if word_list != val:
			word_list = val
			_words_used.clear()

@export_group("Celebi", "celebi_")
@export var celebi_animator: AnimationPlayer
@export var celebi_enter_animation: StringName = &"Celebi idle"
@export var celebi_success_animation: StringName = &"Celebi return"
@export var celebi_fail_animation: StringName = &"Celebi Song"
@export var celebi_tick_animation: StringName = &"Celebi tick"
@export var celebi_tick_sprite: Node2D
@export var celebi_tick_offset: float = 0.5
@export var celebi_sound_tick: AudioStreamPlayer
@export var celebi_sound_tick_danger: AudioStreamPlayer
@export var celebi_sound_fail: AudioStreamPlayer
@export var celebi_curve: Curve

@export_group("Unown", "unown_")
@export var unown_scene: PackedScene
@export var unown_letter_parent: Node

@export_subgroup("Flyby", "unown_flyby_")
@export var unown_flyby: AnimationPlayer
@export var unown_flyby_animation: StringName = &"UnownFlyBy copy"

@export_group("References", "reference_")
@export var reference_level: RubiconLevel
@export var bar_animation: AnimationPlayer
@export var health_module: RubiconHealthModule

signal challenge_started
signal challenge_fail(failure: int)
signal force_second_fail

var fail_count: int = 0

var unowns: Array[UnownLetter] = []

var passed_challenge: bool = false
var challenge_over: bool = false
var letters_passed: int = 0

var _show_celebi: bool = false
var _active: bool = false
var _prompt_user: bool = false
var _time_end: float = 0.0

var _words_used: Array[String] = []

var _celebi_last_second: int = 0
var _celebi_tween: Tween

var _autoplay_time_passed: float = 0.0

## show_celebi's setter only does anything when the value CHANGES, so starting
## at false (the default, matching _show_celebi) means it never runs and never
## hides anything. Celebi is authored visible in mch_typing.tscn - verified
## identical in the original PC pck, so this isn't a porting mistake in the
## scene - which left it on screen from the first frame until the mechanic
## first toggled the property. Applying the starting state here is what the
## setter can't do for the initial value.
func _ready() -> void :
	if Engine.is_editor_hint():
		return

	if celebi_animator:
		celebi_animator.get_parent().visible = _show_celebi

func _process(delta: float) -> void :
	if reference_level == null or reference_level.clock == null or not active or not show_celebi or not prompt_user or challenge_over:
		return

	var current_time: float = reference_level.clock.animation_player.current_animation_position
	var time_left: float = time_end + end_offset - current_time

	if time_left <= 0:
		active = false
		return

	if autoplay and prompt_user:
		_autoplay_process(delta, time_left)

	if time_left > 6:
		celebi_tick_sprite.modulate.a = 0.4
	else:
		celebi_tick_sprite.modulate.a = 0.4 + ((1 - (time_left / 6.0)) * 0.6)

	var celebi_second: int = floori(time_left - celebi_tick_offset)

	if celebi_second != _celebi_last_second:
		if celebi_second == -1:
			celebi_sound_fail.play()
		elif celebi_second < 3:
			celebi_sound_tick_danger.play()
		else:
			celebi_sound_tick.play()

		celebi_animator.play(celebi_tick_animation if celebi_second >= 0 else celebi_fail_animation)
		celebi_animator.seek(0.0)

	_celebi_last_second = celebi_second

## One letter every fifth of a second, which is the rate the mechanic has
## always autoplayed at, and still the rate of the debug autoplay toggle.
const AUTOPLAY_INTERVAL := 0.2

## How much of the time still on the clock a showcase run is allowed to spend
## on the letters it has left. The rest is margin - the challenge ends the
## moment the last letter lands, so this is not a deadline being approached,
## it is how much of the window is deliberately left unused.
const SHOWCASE_AUTOPLAY_BUDGET := 0.6

## And an upper bound on the interval, so a challenge with a generous timer
## does not end up typing at one letter per second. Just over half a second
## reads as somebody typing rather than as a machine, and still clears a
## ten-letter word in under six.
const SHOWCASE_AUTOPLAY_MAX_INTERVAL := 0.55

## Floor for the showcase rate, which is deliberately FASTER than
## AUTOPLAY_INTERVAL rather than equal to it.
##
## The fixed 0.2s rate cannot type every word in every window this song sets:
## "John Monochrome" is 14 keystrokes, the fourth challenge runs from 189.75s
## to 192.5s, and 14 x 0.2 = 2.8s does not fit in 2.75s. The word is drawn
## with pick_random() from a list of 19, so roughly one run in twenty loses
## that challenge to the clock with nobody at fault. On PC that never
## mattered - autoplay is a debug toggle nobody watches - but a showcase that
## randomly fails is a broken showcase, so here the rate is allowed to go
## below 0.2s when that is what finishing needs.
##
## Twenty letters a second, only ever reached if a word is far tighter than
## anything this song actually asks for.
const SHOWCASE_AUTOPLAY_MIN_INTERVAL := 0.05

func _autoplay_process(delta: float, time_left: float) -> void :
	# Counted in song time, not in real time.
	#
	# time_left comes off the clock, so it shrinks twice as fast when the
	# song is playing at 2x - while delta does not. Left in real seconds the
	# autoplay would keep typing at its usual pace against a deadline
	# arriving twice as quickly, and lose a challenge it can normally clear.
	# Taken from the clock's own speed rather than from the setting, so it is
	# right whatever moved it.
	_autoplay_time_passed += delta * _song_speed()

	if _autoplay_time_passed < _autoplay_interval(time_left):
		return

	input_letter(current_word[letters_passed])
	_autoplay_time_passed = 0.0

## Autoplay exists for two different reasons and they want different speeds.
##
## For the debug toggle it only has to not lose, and 0.2s does that, so that
## path is left exactly as it was. In Showcase Mode the autoplay IS the thing
## being watched - and five keystrokes a second is not something a person
## does, so the drawn keyboard flickers rather than reading as typing.
##
## Rather than pick a slower constant and hope it fits, the interval is
## spread across the time actually left over the letters actually left.
##
## That cannot overrun the challenge by construction. Each letter spends a
## fixed fraction of what is still on the clock, so the remaining time falls
## by a factor of (1 - budget/letters_left) each step and the last letter
## still lands with 40% of its own slice to spare - no arithmetic about the
## word or the window has to be right for that to hold. It also adapts to
## whatever time_end the song's animation set, and self-corrects: if a
## stutter eats a moment, the next interval is computed from the clock as it
## now stands rather than from what was planned.
## How many seconds of song pass per real second. 1.0 unless something is
## scaling the timeline - Settings.lullaby_speed_hack, today.
func _song_speed() -> float:
	if reference_level == null or reference_level.clock == null:
		return 1.0
	var timeline: AnimationPlayer = reference_level.clock.animation_player
	if timeline == null or timeline.speed_scale <= 0.0:
		return 1.0
	return timeline.speed_scale

func _autoplay_interval(time_left: float) -> float:
	if not LullabyShowcase.is_active():
		return AUTOPLAY_INTERVAL

	# input_letter() walks over runs of spaces without spending an interval
	# on them, so the letters left are the non-space ones. Counting the
	# spaces would make it type faster than intended, not slower.
	var keystrokes_left: int = 0
	for i in range(letters_passed, current_word.length()):
		if current_word[i] != " ":
			keystrokes_left += 1

	if keystrokes_left <= 0 or time_left <= 0.0:
		return AUTOPLAY_INTERVAL

	var spread: float = (time_left * SHOWCASE_AUTOPLAY_BUDGET) / keystrokes_left
	return clampf(spread, SHOWCASE_AUTOPLAY_MIN_INTERVAL,
		SHOWCASE_AUTOPLAY_MAX_INTERVAL)

func _input(event: InputEvent) -> void :
	if autoplay:
		return

	if not active or not prompt_user or challenge_over:
		return

	if event is not InputEventKey or event.is_released() or event.is_echo():
		return

	var letter: String = event.as_text_key_label()
	input_letter(letter.to_lower())

func input_letter(character: String) -> void :
	while letters_passed < current_word.length() and current_word[letters_passed] == " ":
		letters_passed += 1

	if letters_passed >= current_word.length():
		passed_challenge = true
		end_challenge()
		return

	if character != current_word[letters_passed].to_lower():
		fail_current_unown()
		end_offset -= 0.25
		return

	letters_passed += 1

	while letters_passed < current_word.length() and current_word[letters_passed] == " ":
		letters_passed += 1

	if letters_passed >= current_word.length():
		passed_challenge = true
		end_challenge()
		return

	update_unowns()


func get_challenge_word() -> String:
	if choose_from_list:
		var word: String = word_list.pick_random()
		if _words_used.size() < word_list.size():
			while _words_used.has(word):
				word = word_list.pick_random()

		if not _words_used.has(word):
			_words_used.append(word)

		return word

	return custom_word


func update_unowns() -> void :
	for i in current_word.length():
		if not has_unown_index(i):
			continue

		var unown: UnownLetter = unowns[i]
		if current_word[i] == " ":
			unown.visible = false
			continue

		unown.visible = true

		if i == letters_passed:
			unown.move_to_front()
			unown.activate()
		elif i < letters_passed:
			unown.succeed()


func fail_current_unown() -> void :
	while letters_passed < current_word.length() and current_word[letters_passed] == " ":
		letters_passed += 1

	if letters_passed < unowns.size():
		unowns[letters_passed].fail()

	end_offset -= 0.25


func initiate_challenge() -> void :
	if reference_level == null or reference_level.clock == null:
		return

	var current_time: float = reference_level.clock.animation_player.current_animation_position
	var final_time: float = time_end + end_offset

	if current_time >= final_time or (current_time < final_time and challenge_over):
		return

	current_word = get_challenge_word()

	letters_passed = 0
	end_offset = 0.0

	passed_challenge = false
	challenge_over = false

	unown_flyby.play(unown_flyby_animation)
	unown_flyby.seek(0.0)

	for unown in unowns:
		unown.visible = false

	while unowns.size() < current_word.length():
		var unown: UnownLetter = unown_scene.instantiate()
		unown.visible = false

		unown_letter_parent.add_child(unown)
		unowns.append(unown)

	for i in range(current_word.length(), unowns.size()):
		unowns[i].visible = false

	var spacing_x: float = 160
	var size_multiplier: float = 1.0

	if current_word.length() > 10:
		size_multiplier = 10.0 / (current_word.length() - 1)

	var offset_x: float = spacing_x * size_multiplier * (current_word.length() - 1) * 0.5

	for word_index in current_word.length():
		var unown: UnownLetter = unowns[word_index]
		var current_character: String = current_word[word_index]

		unown.character = ""

		var random_scale: float = randf_range(0.6, 0.7) * size_multiplier
		unown.scale = random_scale * Vector2.ONE

		var random_x: float = (((spacing_x * word_index) + randf_range(-20, 20)) * size_multiplier) - offset_x
		var random_y: float = randf_range(-60, 60)

		unown.position = Vector2(random_x, random_y)

		if current_character == " ":
			unown.visible = false
		else:
			unown.visible = true
			unown.enter(randf_range(0.125, 1.0 / 3.0))


func start_challenge() -> void :
	if reference_level == null or reference_level.clock == null or not active:
		return

	var current_time: float = reference_level.clock.animation_player.current_animation_position
	var final_time: float = time_end + end_offset

	if current_time >= final_time or (current_time < final_time and challenge_over):
		return

	var time_left: float = final_time - current_time
	_celebi_last_second = floori(time_left - celebi_tick_offset)

	for word_index in current_word.length():
		var current_character: String = current_word[word_index]
		var unown: UnownLetter = unowns[word_index]

		unown.character = "" if current_character == " " else current_character

	letters_passed = 0
	update_unowns()

	challenge_started.emit()

	if _celebi_tween and _celebi_tween.is_running():
		_celebi_tween.kill()

	_celebi_tween = create_tween()
	_celebi_tween.tween_method(_celebi_tween_func, 0.0, 1.0, time_left)


func _celebi_tween_func(progress: float) -> void :
	var curve_progress: float = celebi_curve.sample(progress)
	$Celebi.scale = lerp(celebi_start_scale, celebi_end_scale, curve_progress)
	$Celebi.modulate = lerp(Color("333333"), Color("ffffff"), curve_progress)


func end_challenge() -> void :
	if challenge_over:
		return

	if passed_challenge:
		succeed()
	else:
		fail()


func succeed() -> void :
	passed_challenge = true
	challenge_over = true

	celebi_sound_tick.stop()
	celebi_sound_tick_danger.stop()
	celebi_sound_fail.stop()

	celebi_animator.play(celebi_success_animation)
	celebi_animator.seek(0.0)

	for i in current_word.length():
		if current_word[i] == " ":
			continue

		if has_unown_index(i):
			unowns[i].succeed()

	await get_tree().create_timer(0.5, false).timeout

	for i in current_word.length():
		if current_word[i] == " ":
			continue

		if has_unown_index(i):
			unowns[i].exit(randf_range(0.0, 0.2))


func add_one_fail() -> void :
	if fail_count >= 2:
		return

	fail_count += 1
	challenge_fail.emit(fail_count)

	if fail_count == 2:
		force_second_fail.emit()


func fail() -> void :
	challenge_over = true

	if _celebi_tween and _celebi_tween.is_running():
		_celebi_tween.kill()

	if celebi_animator.current_animation != celebi_fail_animation:
		if not celebi_sound_fail.playing:
			celebi_sound_fail.play()

		celebi_animator.play(celebi_fail_animation)
		celebi_animator.seek(0.0)

	for i in current_word.length():
		if current_word[i] == " ":
			continue

		if has_unown_index(i):
			unowns[i].succeed()

	fail_count += 1
	challenge_fail.emit(fail_count)

	if fail_count == 3:
		return

	await get_tree().create_timer(0.5, false).timeout

	for i in current_word.length():
		if current_word[i] == " ":
			continue

		if has_unown_index(i):
			unowns[i].exit(randf_range(0.0, 0.2))


func has_unown_index(index: int) -> bool:
	return index >= 0 and index < unowns.size() and is_instance_valid(unowns[index])
