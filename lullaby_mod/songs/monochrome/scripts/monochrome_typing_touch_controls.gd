extends Control
class_name MonochromeTypingTouchControls

## Android touch support for Monochrome's TypingChallenge mechanic
## (Stage/TypingChallenge). Desktop players type on a physical keyboard;
## TypingChallenge._input() reads raw InputEventKey letter by letter.
##
## This used to draw its own on-screen keyboard (RubiconOnScreenKeyboard).
## It now focuses a real LineEdit instead, which is what makes Android open
## the system keyboard - the same thing the Collector Shop's Codes tab does
## (hacks_tab.gd's code_input), and the reason that screen already felt
## native while this one did not. The player gets their own autocorrect,
## layout, language and swipe input rather than a hand-drawn approximation.
##
## The LineEdit is deliberately transparent and non-interactive: it exists to
## hold focus and receive characters, never to be seen or tapped. Typed text
## is drained into TypingChallenge.input_letter() and the field is cleared
## again immediately, so it never accumulates state of its own and the
## mechanic stays the single source of truth for what has been typed.
##
## Focus is what drives the keyboard, so it is also what closes it: releasing
## focus when the challenge stops prompting dismisses the system keyboard
## without having to call any platform API.

## True while a keyboard - the system one or the drawn one - is actually on
## screen for this challenge.
##
## The note lanes have to get out of the way while the player is typing, and
## RubiconMobileControls was pointed at TypingChallenge.active to decide
## that. But active is a song animation track that stays true for the whole
## bout - 11 seconds at 73-84, again at 110-121, and so on - while the
## keyboard only wants the screen for `active and prompt_user and not
## challenge_over`. Finish the word in three seconds and challenge_over goes
## true, the keyboard leaves, and the lanes stayed hidden and inert for the
## remaining eight while notes kept arriving. Reported from the device as
## "you cannot press the notes until the hitbox comes back".
##
## So the lanes now hide on the condition that actually puts a keyboard over
## them, which is this, computed in the same place and the same frame as the
## keyboard itself.
var keyboard_showing: bool = false

## How much of the screen the keyboard covers, from the bottom, as a fraction
## of viewport height. 0 when no keyboard is up.
##
## This is what the note hitbox reads now, and it replaces keyboard_showing in
## that role for a reason the chart makes plain: Monochrome puts player notes
## INSIDE its typing bouts - five of them, 59 notes in total, grouped at the
## END of each window, which is exactly where a player who is still typing has
## not finished. Hiding the whole hitbox made those notes unreachable rather
## than merely hard, and the report was "no me dejo tocar las flechas,
## perdiendo en el proceso".
##
## keyboard_showing stays and is still maintained, but nothing reads it any
## more - it was the lanes' condition and that is now this. Kept rather than
## deleted because it is the honest answer to "is a keyboard on screen", which
## is a different question from "how much of the screen does it cover", and
## because the comment above it is the record of the bug before this one.
var keyboard_occlusion: float = 0.0

@export var typing_challenge: TypingChallenge
@export var text_input: LineEdit

## Nodes that must not end up behind the system keyboard - the unowns and
## their letters, which sit low enough on screen to be covered by it. The
## keyboard's height is only known at runtime (it varies by device, language
## and whether a suggestion strip is showing), so this can't be baked into
## the scene as a fixed offset and has to be applied live.
@export var raise_targets: Array[Node2D] = []

## Extra clearance above the keyboard, in the same units as the targets'
## positions. Their position is used as a stand-in for where their artwork
## actually ends, so this absorbs that difference.
@export var raise_margin: float = 120.0

@export_group("Drawn keyboard")

## Showcase Mode cannot use the system keyboard: it belongs to another app
## (Gboard, or whatever the player installed), is drawn in its own window,
## and nothing can highlight its keys - not Godot, not Android. So showcase
## gets the drawn keyboard this screen used to use instead, which is ours and
## can therefore be animated. It is also what the Mobile > Keyboard setting
## selects when the player prefers the game's own keys, so it is a real input
## method and not only a showcase prop - see _on_drawn_key_pressed.
##
## Bigger than RubiconPaintedKeyboard's default on purpose: 96px keys are
## comfortable thumb targets on a phone and still legible from across a room
## in a showcase, so one size serves both uses.
@export var drawn_key_size: Vector2 = Vector2(96, 96)
@export var drawn_key_gap: float = 10.0
@export var drawn_space_width: float = 460.0

## Gap between the bottom of the keyboard and the bottom of the screen.
@export var drawn_bottom_margin: float = 56.0

## Keycap styling, taken from Monochrome's own art rather than from a neutral
## dark theme. Everything in this song is drawn the same way - a near-black
## shape behind a heavy chalk outline, on a black stage - so the keys are
## built to the same rule instead of looking like a phone keyboard that
## wandered in:
##
##   the cap is the stage's black with the faintest lift, so 28 of them along
##   the bottom of the screen do not become the brightest thing on it;
##
##   the outline and the letters are the chalk the note arrows and the cracks
##   across the stage are drawn in - sampled at #f8e0e0 on screen, which is
##   warm only because the unowns' glow bleeds into it, so it is cooled back
##   to the tone the art actually uses;
##
##   and a typed key goes to the unowns' red. That colour is exactly #ff0000
##   across 220k pixels of tex_mch_unown.png - it is the one saturated thing
##   in the whole song, which is what makes it read instantly as "this is the
##   letter" and why gold was the wrong choice here.
@export var drawn_key_color: Color = Color("15131a")
@export var drawn_outline_color: Color = Color("d8d2cc")
@export var drawn_outline_width: float = 3.0
@export var drawn_label_color: Color = Color("f0ebe6")
@export var drawn_font_size: int = 34

## How long a key stays lit after the autoplay presses it, and what colour it
## goes. This replaces the keycap's colour rather than multiplying it -
## multiplying a near-black keycap is what made the first version invisible.
@export var drawn_flash_seconds: float = 0.22
@export var drawn_flash_color: Color = Color("ff0000")

var _base_positions: PackedVector2Array
var _draining: bool = false

## Painted rather than built out of Buttons: 28 Buttons on rounded styleboxes
## cost 255 unbatchable draw calls whenever the keyboard was up, measured on
## device against two censuses with an identical scene population. See
## painted_keyboard.gd.
var _drawn_keyboard: RubiconPaintedKeyboard
## Watching this advance is how a typed letter is spotted;
## TypingChallenge._autoplay_process emits no signal, and that file is the
## pck's too.
var _last_letters_passed: int = -1

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Has to keep running through get_tree().paused = true so it can put the
	# keyboard away when that happens - the same reason RubiconMobileControls
	# and ChimeraHeartbeatTouchZone both override this. Without it the pause
	# menu comes up underneath a system keyboard nobody can dismiss, because
	# Godot only lowers it as a side effect of a focus change, and the focus
	# change is exactly what this _process was frozen out of making.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for t in raise_targets:
		_base_positions.append(t.position if t else Vector2.ZERO)

	if text_input:
		text_input.text_changed.connect(_on_text_changed)
		_set_input_available(false)

func _process(_delta: float) -> void:
	if not text_input or not typing_challenge:
		return

	# Paused is not "the challenge stopped" - it is "nothing may be on top of
	# the pause menu", which the drawn keyboard and the system one both are.
	var paused: bool = get_tree().paused

	var challenge_wants: bool = (
		typing_challenge.active
		and typing_challenge.prompt_user
		and not typing_challenge.challenge_over
		and not paused
	)

	# Showcase overrides the setting rather than reading it. The system
	# keyboard is another app's window - its keys cannot be shown being
	# pressed, and raising it would cover the song - so a showcase always
	# gets the drawn one no matter what the player picked.
	var drawn: bool = (LullabyShowcase.is_active()
		or Settings.lullaby_mobile_keyboard_type == Settings.MobileKeyboardType.IN_GAME)

	# The hidden LineEdit is only ever focused for the system keyboard. On the
	# drawn path it stays unreachable, which is what keeps Android from
	# raising its keyboard behind ours.
	# The system keyboard is raised on `active` rather than on prompt_user,
	# which is a couple of seconds earlier, because it does not appear for
	# free: Android animates it in, and that animation comes out of the
	# player's typing window rather than out of the song.
	#
	# The windows are short and get shorter - prompt_user to time_end runs
	# 6.7s, 6.3s, 4.2s, 2.75s and 3.1s across the five bouts - so half a
	# second of keyboard animation is up to a fifth of the last ones. That is
	# the difference the device reported between the system keyboard and the
	# drawn one, which appears instantly and needs none of this.
	#
	# The two seconds it borrows are already dead: show_celebi comes up at
	# 69 and active at 73 against prompt_user at 75.26, so the game has been
	# announcing the challenge for six seconds by then.
	var keyboard_wants: bool = (
		typing_challenge.active
		and not typing_challenge.challenge_over
		and not paused
	)

	var wants_input: bool = keyboard_wants and not typing_challenge.autoplay and not drawn

	if wants_input:
		_set_input_available(true)
		if not text_input.has_focus():
			text_input.grab_focus()
	else:
		_set_input_available(false)

	var drawn_height: float = _process_drawn_keyboard(drawn and challenge_wants)
	_apply_raise(wants_input, drawn_height)

	keyboard_showing = wants_input or (drawn and challenge_wants)

## Returns how much of the screen the drawn keyboard is covering, in viewport
## units, so the unowns can be lifted clear of it exactly the way they are
## lifted clear of the system one. Zero whenever it isn't shown.
##
## Autoplay is deliberately not part of `showing`: in showcase it is always
## on, and the keyboard staying up is the entire point.
func _process_drawn_keyboard(showing: bool) -> float:
	if not showing:
		if _drawn_keyboard:
			_drawn_keyboard.visible = false
			_drawn_keyboard.clear_flashes()
		_last_letters_passed = -1
		return 0.0

	if _drawn_keyboard == null:
		_build_drawn_keyboard()
		if _drawn_keyboard == null:
			return 0.0

	_drawn_keyboard.visible = true
	_layout_drawn_keyboard()
	_flash_typed_key()
	return _drawn_keyboard.get_block_size().y + drawn_bottom_margin

## The keyboard reads its exported values in _ready() to lay its keys out, so
## all of them are set before it enters the tree.
func _build_drawn_keyboard() -> void:
	_drawn_keyboard = RubiconPaintedKeyboard.new()
	_drawn_keyboard.name = "DrawnKeyboard"
	_drawn_keyboard.key_size = drawn_key_size
	_drawn_keyboard.key_gap = drawn_key_gap
	_drawn_keyboard.space_width = drawn_space_width
	_drawn_keyboard.key_color = drawn_key_color
	_drawn_keyboard.outline_color = drawn_outline_color
	_drawn_keyboard.outline_width = drawn_outline_width
	_drawn_keyboard.label_color = drawn_label_color
	_drawn_keyboard.font_size = drawn_font_size
	_drawn_keyboard.flash_seconds = drawn_flash_seconds
	_drawn_keyboard.flash_color = drawn_flash_color
	add_child(_drawn_keyboard)

	# Tappable, because this is a real input method when the player picks
	# In-Game and not only a showcase prop. In showcase nobody taps it, so
	# the connection simply never fires there.
	_drawn_keyboard.key_pressed.connect(_on_drawn_key_pressed)

## Centres the keyboard horizontally and sits it above the bottom edge. Done
## every frame rather than once because the viewport can change size
## (rotation, or the render-scale settings) and this control is what decides
## how far the unowns have to be lifted.
func _layout_drawn_keyboard() -> void:
	var wanted: Vector2 = _drawn_keyboard.get_block_size()
	if wanted.x <= 0.0 or wanted.y <= 0.0:
		return

	var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	_drawn_keyboard.position = Vector2(
		roundf((area.x - wanted.x) * 0.5),
		roundf(area.y - wanted.y - drawn_bottom_margin))

## input_letter() consumes current_word[letters_passed] and advances, and it
## skips runs of spaces first, so the counter can jump by more than one. The
## last non-space character it swallowed is the one that was actually typed.
func _flash_typed_key() -> void:
	var passed: int = typing_challenge.letters_passed
	if _last_letters_passed < 0:
		_last_letters_passed = passed
		return
	if passed <= _last_letters_passed:
		_last_letters_passed = passed
		return

	var word: String = typing_challenge.current_word
	var typed: String = ""
	for i in range(_last_letters_passed, mini(passed, word.length())):
		if word[i] != " ":
			typed = word[i]
	_last_letters_passed = passed

	if typed.is_empty():
		return
	# The keyboard is keyed by label, and only letters are ever flashed - the
	# loop above skips spaces, so the space bar is never lit from here.
	_drawn_keyboard.flash(typed.to_upper())

## The mechanic is the single source of truth for what has been typed, the
## same as the LineEdit path - this only forwards the character.
func _on_drawn_key_pressed(character: String) -> void:
	if typing_challenge == null or typing_challenge.autoplay:
		return
	typing_challenge.input_letter(character)

## Releasing focus is not enough on its own. The challenge's flags are reused
## between rounds (start_challenge() clears challenge_over while active and
## prompt_user are still set from the round before), so wants_input can blip
## back on for a frame after the unowns are gone - and a single frame of focus
## is a whole system keyboard back on screen, sitting over the note lanes.
##
## So when input isn't wanted the field is made genuinely unreachable rather
## than merely unfocused: focus_mode NONE means nothing can hand it focus,
## and hidden means Godot won't either. virtual_keyboard_hide() is belt and
## braces for the case where the keyboard is already up when that happens -
## Godot only lowers it as a side effect of a focus change it can see.
func _set_input_available(available: bool) -> void:
	if available:
		if not text_input.visible:
			text_input.focus_mode = Control.FOCUS_ALL
			text_input.visible = true
		return

	if not text_input.visible and text_input.focus_mode == Control.FOCUS_NONE:
		return

	if text_input.has_focus():
		text_input.release_focus()
	text_input.focus_mode = Control.FOCUS_NONE
	text_input.visible = false
	text_input.text = ""
	DisplayServer.virtual_keyboard_hide()

## Lifts each target by exactly how much the keyboard overlaps it, and no
## more, so nothing moves on a device whose keyboard is short enough to leave
## it clear anyway.
func _apply_raise(wants_input: bool, drawn_height: float = 0.0) -> void:
	var overlap_source: float = 0.0
	var viewport_height: float = get_viewport_rect().size.y

	if wants_input:
		# virtual_keyboard_get_height() is in real screen pixels while the
		# targets live in the viewport's base resolution, so it has to be
		# scaled by the stretch ratio before it means anything to them.
		var window_height: float = float(DisplayServer.window_get_size().y)
		var to_viewport: float = viewport_height / window_height if window_height > 0.0 else 1.0
		var keyboard_height: float = float(DisplayServer.virtual_keyboard_get_height()) * to_viewport
		if keyboard_height > 0.0:
			overlap_source = viewport_height - keyboard_height
	elif drawn_height > 0.0:
		# The drawn keyboard is already in viewport units - it is a Control in
		# this scene, not an OS window - so it needs no conversion. The two are
		# mutually exclusive by construction (wants_input is false whenever the
		# drawn keyboard is up) but the branch keeps them from ever stacking.
		overlap_source = viewport_height - drawn_height

	# Published for RubiconMobileControls, which shrinks the note hitbox up to
	# this line instead of hiding it outright. It is the same measurement the
	# unowns are lifted by, taken in the same frame, so the lanes stop exactly
	# where the letters start being moved clear - one number, one source of
	# truth, and no second way for them to disagree.
	#
	# `overlap_source` is the y where the keyboard starts, so what is covered
	# is everything below it.
	keyboard_occlusion = 0.0
	if overlap_source > 0.0 and viewport_height > 0.0:
		keyboard_occlusion = clampf(
			(viewport_height - overlap_source) / viewport_height, 0.0, 1.0)

	for i in raise_targets.size():
		var target: Node2D = raise_targets[i]
		if target == null:
			continue

		var base: Vector2 = _base_positions[i]
		var lift: float = 0.0
		if overlap_source > 0.0:
			lift = maxf((base.y + raise_margin) - overlap_source, 0.0)

		target.position = Vector2(base.x, base.y - lift)

## Everything the player types arrives here as the field's full contents, so
## it is forwarded a character at a time and then wiped. The guard is because
## clearing the text re-emits text_changed.
func _on_text_changed(new_text: String) -> void:
	if _draining or not typing_challenge:
		return

	if new_text.is_empty():
		return

	# The field is focused before the challenge asks for input, to get the
	# keyboard animated in ahead of time. Anything typed in that gap has to
	# be dropped rather than fed through: input_letter() has no guard of its
	# own, so an early keystroke would be judged against current_word, count
	# as a wrong letter and take 0.25s off the deadline.
	if not typing_challenge.prompt_user:
		_draining = true
		text_input.text = ""
		_draining = false
		return

	_draining = true
	for character in new_text:
		typing_challenge.input_letter(character)
	text_input.text = ""
	_draining = false
